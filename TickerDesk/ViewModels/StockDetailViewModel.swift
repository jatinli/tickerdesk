import Foundation
import Observation

@Observable
@MainActor
final class StockDetailViewModel {
    let symbol: String
    var range: ChartRange = .day
    private(set) var points: [PricePoint] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(symbol: String) {
        self.symbol = symbol
    }

    func loadHistory(using provider: any MarketDataProvider) async {
        isLoading = true
        defer { isLoading = false }
        do {
            points = try await provider.history(for: symbol, range: range)
            errorMessage = nil
        } catch is CancellationError {
            // The range changed mid-load; the next load will replace this one.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends the live price to the intraday chart so it moves with the ticker.
    func chartPoints(live quote: Quote?) -> [PricePoint] {
        guard range == .day, let quote, let last = points.last, quote.timestamp > last.date else { return points }
        return points + [PricePoint(date: quote.timestamp, price: quote.last)]
    }
}
