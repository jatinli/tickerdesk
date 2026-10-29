import Foundation

/// Offline feed: a random walk around seed prices. Also used for demos and UI tests.
struct MockMarketDataProvider: MarketDataProvider {
    struct CatalogEntry: Sendable {
        let info: SymbolInfo
        let price: Decimal

        init(_ symbol: String, _ name: String, _ price: String) {
            info = SymbolInfo(symbol: symbol, name: name)
            self.price = Decimal(string: price)!
        }
    }

    static let catalog: [CatalogEntry] = [
        CatalogEntry("AAPL", "Apple Inc.", "228.50"),
        CatalogEntry("MSFT", "Microsoft Corp.", "418.20"),
        CatalogEntry("NVDA", "NVIDIA Corp.", "135.40"),
        CatalogEntry("TSLA", "Tesla Inc.", "251.30"),
        CatalogEntry("AMZN", "Amazon.com Inc.", "186.70"),
        CatalogEntry("GOOGL", "Alphabet Inc.", "165.80"),
        CatalogEntry("META", "Meta Platforms Inc.", "520.10"),
        CatalogEntry("NFLX", "Netflix Inc.", "690.25"),
        CatalogEntry("JPM", "JPMorgan Chase & Co.", "212.45"),
        CatalogEntry("V", "Visa Inc.", "278.90"),
        CatalogEntry("IBKR", "Interactive Brokers Group", "160.40"),
        CatalogEntry("INFY", "Infosys Ltd. ADR", "21.35"),
        CatalogEntry("HDB", "HDFC Bank Ltd. ADR", "61.20"),
    ]

    static let defaultWatchlist = ["AAPL", "MSFT", "NVDA", "TSLA", "IBKR"]

    /// The latest simulated price per symbol, shared by the live feed and `history`.
    private final class PriceBook: @unchecked Sendable {
        static let shared = PriceBook()

        private let lock = NSLock()
        private var prices: [String: Decimal] = [:]

        func price(for symbol: String) -> Decimal {
            lock.withLock { prices[symbol] ?? MockMarketDataProvider.seedPrice(for: symbol) }
        }

        func set(_ price: Decimal, for symbol: String) {
            lock.withLock { prices[symbol] = price }
        }
    }

    var tickInterval: Duration = .milliseconds(100)
    /// Drops the "connection" about once a minute so the reconnect UI can be demoed.
    var simulateDropouts = true

    static func seedPrice(for symbol: String) -> Decimal {
        catalog.first { $0.info.symbol == symbol }?.price ?? 100
    }

    /// Moves `price` by a random number of basis points, staying in whole cents.
    private static func step(_ price: Decimal, maxBasisPoints: Int) -> Decimal {
        let basisPoints = Decimal(Int.random(in: -maxBasisPoints...maxBasisPoints))
        return max(.cent, (price * (1 + basisPoints / 10_000)).rounded(scale: 2))
    }

    /// Starts from the shared simulated price, where `history` ends, so the live line continues the chart.
    private static func initialQuote(for symbol: String) -> Quote {
        let last = PriceBook.shared.price(for: symbol)
        let previousClose = step(last, maxBasisPoints: 150)
        return Quote(
            symbol: symbol,
            last: last,
            bid: last - .cent,
            ask: last + .cent,
            previousClose: previousClose,
            volume: Int.random(in: 100_000...2_000_000),
            timestamp: .now
        )
    }

    func events(for symbols: Set<String>) -> AsyncStream<MarketEvent> {
        let tickInterval = tickInterval
        let simulateDropouts = simulateDropouts

        return AsyncStream { continuation in
            let task = Task {
                continuation.yield(.status(.connecting))
                try? await Task.sleep(for: .milliseconds(400))

                var quotes = Dictionary(uniqueKeysWithValues: symbols.map { ($0, Self.initialQuote(for: $0)) })
                continuation.yield(.status(.connected))
                for quote in quotes.values { continuation.yield(.quote(quote)) }

                let ordered = Array(symbols)
                var ticks = 0
                while !Task.isCancelled, let symbol = ordered.randomElement(), var quote = quotes[symbol] {
                    do { try await Task.sleep(for: tickInterval) } catch { break }

                    quote.last = Self.step(quote.last, maxBasisPoints: 20)
                    quote.bid = quote.last - .cent
                    quote.ask = quote.last + .cent
                    quote.volume += Int.random(in: 100...5_000)
                    quote.timestamp = .now
                    quotes[symbol] = quote
                    PriceBook.shared.set(quote.last, for: symbol)
                    continuation.yield(.quote(quote))

                    ticks += 1
                    if simulateDropouts, ticks.isMultiple(of: 600) {
                        continuation.yield(.status(.reconnecting(attempt: 1, retryIn: 2)))
                        do { try await Task.sleep(for: .seconds(2)) } catch { break }
                        continuation.yield(.status(.connected))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func history(for symbol: String, range: ChartRange) async throws -> [PricePoint] {
        try await Task.sleep(for: .milliseconds(250)) // pretend it's a network call

        // Walk backwards from the current simulated price so the chart ends where the live feed is.
        let now = Date()
        var price = PriceBook.shared.price(for: symbol)
        var points: [PricePoint] = []
        for index in 0..<range.pointCount {
            points.append(PricePoint(date: now.addingTimeInterval(-Double(index) * range.interval), price: price))
            price = Self.step(price, maxBasisPoints: 40)
        }
        return points.reversed()
    }

    func search(_ query: String) async throws -> [SymbolInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let infos = Self.catalog.map(\.info)
        guard !trimmed.isEmpty else { return infos }
        return infos.filter {
            $0.symbol.localizedCaseInsensitiveContains(trimmed) || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
