import Foundation

/// Live US trades from Finnhub's free WebSocket API (https://finnhub.io/docs/api/websocket-trades).
///
/// The free feed only sends trades, so `bid`/`ask` stay `nil` and the matching engine
/// falls back to the last price.
struct FinnhubMarketDataProvider: MarketDataProvider {
    let apiKey: String

    private static let restBase = URL(string: "https://finnhub.io/api/v1")!

    func events(for symbols: Set<String>) -> AsyncStream<MarketEvent> {
        let apiKey = apiKey
        return AsyncStream { continuation in
            let task = Task {
                await Self.stream(symbols: symbols, apiKey: apiKey, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Exponential backoff with jitter: ~1s, 2s, 4s … capped at 30s.
    /// Jitter stops every client reconnecting at the same instant after an outage.
    static func backoffDelay(attempt: Int) -> TimeInterval {
        min(30, pow(2, Double(max(attempt, 1) - 1))) + Double.random(in: 0...0.5)
    }

    private static func stream(
        symbols: Set<String>,
        apiKey: String,
        continuation: AsyncStream<MarketEvent>.Continuation
    ) async {
        continuation.yield(.status(.connecting))

        // The trade feed has no previous close, so fetch it once over REST for the change %.
        var previousCloses: [String: Decimal] = [:]
        for symbol in symbols {
            guard let snapshot = try? await fetchSnapshot(symbol: symbol, apiKey: apiKey) else { continue }
            previousCloses[symbol] = snapshot.previousClose
            continuation.yield(.quote(Quote(
                symbol: symbol,
                last: snapshot.last,
                bid: nil,
                ask: nil,
                previousClose: snapshot.previousClose,
                volume: 0,
                timestamp: .now
            )))
        }

        var sessionVolumes: [String: Int] = [:]
        var attempt = 0

        while !Task.isCancelled {
            var components = URLComponents(string: "wss://ws.finnhub.io")!
            components.queryItems = [URLQueryItem(name: "token", value: apiKey)]
            let socket = URLSession.shared.webSocketTask(with: components.url!)
            socket.resume()

            do {
                for symbol in symbols {
                    try await socket.send(.string(#"{"type":"subscribe","symbol":"\#(symbol)"}"#))
                }
                continuation.yield(.status(.connected))
                attempt = 0

                while !Task.isCancelled {
                    let message = try await withTaskCancellationHandler {
                        try await socket.receive()
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }

                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let raw): data = raw
                    @unknown default: continue
                    }

                    guard let payload = try? JSONDecoder().decode(TradeMessage.self, from: data),
                          payload.type == "trade" else { continue } // also skips {"type":"ping"}

                    for trade in payload.data ?? [] {
                        // Convert at the boundary: JSON numbers arrive as Double, the app uses Decimal.
                        guard let price = Decimal(string: String(trade.p))?.rounded(scale: 2) else { continue }
                        sessionVolumes[trade.s, default: 0] += Int(trade.v)
                        continuation.yield(.quote(Quote(
                            symbol: trade.s,
                            last: price,
                            bid: nil,
                            ask: nil,
                            previousClose: previousCloses[trade.s] ?? price,
                            volume: sessionVolumes[trade.s] ?? 0,
                            timestamp: Date(timeIntervalSince1970: trade.t / 1000)
                        )))
                    }
                }
            } catch {
                // Fall through to the reconnect below.
            }

            socket.cancel(with: .goingAway, reason: nil)
            guard !Task.isCancelled else { break }

            attempt += 1
            let delay = backoffDelay(attempt: attempt)
            continuation.yield(.status(.reconnecting(attempt: attempt, retryIn: delay)))
            do { try await Task.sleep(for: .seconds(delay)) } catch { break }
        }

        continuation.yield(.status(.disconnected))
        continuation.finish()
    }

    // Finnhub's free plan no longer includes candles, so charts use simulated history.
    func history(for symbol: String, range: ChartRange) async throws -> [PricePoint] {
        try await MockMarketDataProvider(simulateDropouts: false).history(for: symbol, range: range)
    }

    func search(_ query: String) async throws -> [SymbolInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let url = Self.restBase.appending(path: "search").appending(queryItems: [URLQueryItem(name: "q", value: trimmed)])
        let response: SearchResponse = try await Self.get(url, apiKey: apiKey)
        return response.result
            .filter { $0.type == "Common Stock" && !$0.symbol.contains(".") } // US listings only
            .map { SymbolInfo(symbol: $0.symbol, name: $0.description.capitalized) }
    }

    // MARK: - REST

    private static func fetchSnapshot(symbol: String, apiKey: String) async throws -> (last: Decimal, previousClose: Decimal) {
        let url = restBase.appending(path: "quote").appending(queryItems: [URLQueryItem(name: "symbol", value: symbol)])
        let snapshot: QuoteSnapshot = try await get(url, apiKey: apiKey)
        let last = Decimal(string: String(snapshot.c))?.rounded(scale: 2) ?? 0
        let previousClose = Decimal(string: String(snapshot.pc))?.rounded(scale: 2) ?? last
        return (last, previousClose)
    }

    private static func get<T: Decodable>(_ url: URL, apiKey: String) async throws -> T {
        var request = URLRequest(url: url)
        // Header rather than query string, so the key doesn't end up in server or proxy logs.
        request.setValue(apiKey, forHTTPHeaderField: "X-Finnhub-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else { throw ProviderError.badResponse(statusCode: statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Wire formats

    private struct TradeMessage: Decodable {
        struct Trade: Decodable {
            let s: String  // symbol
            let p: Double  // price
            let v: Double  // volume
            let t: Double  // unix ms
        }

        let type: String
        let data: [Trade]?
    }

    private struct QuoteSnapshot: Decodable {
        let c: Double   // current
        let pc: Double  // previous close
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            let symbol: String
            let description: String
            let type: String
        }

        let result: [Item]
    }
}
