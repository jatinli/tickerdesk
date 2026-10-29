import Foundation

/// Anything that can stream quotes. The app only talks to this protocol, so the
/// simulated feed, Finnhub, or a test double are interchangeable.
protocol MarketDataProvider: Sendable {
    /// A stream of quotes and connection-state changes for `symbols`.
    /// Cancelling the consuming task tears the connection down.
    func events(for symbols: Set<String>) -> AsyncStream<MarketEvent>

    func history(for symbol: String, range: ChartRange) async throws -> [PricePoint]

    func search(_ query: String) async throws -> [SymbolInfo]
}

enum ProviderError: LocalizedError {
    case badResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(let statusCode): return "The market data server returned an error (\(statusCode))."
        }
    }
}
