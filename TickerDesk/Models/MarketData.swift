import Foundation

struct Quote: Identifiable, Equatable, Sendable {
    let symbol: String
    var last: Decimal
    var bid: Decimal?
    var ask: Decimal?
    var previousClose: Decimal
    var volume: Int
    var timestamp: Date

    var id: String { symbol }
    var change: Decimal { last - previousClose }
    var changePercent: Decimal { previousClose == 0 ? 0 : change / previousClose }
}

struct SymbolInfo: Identifiable, Hashable, Sendable {
    let symbol: String
    let name: String

    var id: String { symbol }
}

struct PricePoint: Identifiable, Sendable {
    let date: Date
    let price: Decimal

    var id: Date { date }
}

enum ChartRange: String, CaseIterable, Identifiable, Sendable {
    case day = "1D"
    case week = "1W"
    case month = "1M"

    var id: Self { self }

    var pointCount: Int {
        switch self {
        case .day: return 78     // 6.5 trading hours of 5-minute bars
        case .week: return 168
        case .month: return 180
        }
    }

    var interval: TimeInterval {
        switch self {
        case .day: return 5 * 60
        case .week: return 60 * 60
        case .month: return 4 * 60 * 60
        }
    }
}

enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int, retryIn: TimeInterval)
}

enum MarketEvent: Sendable {
    case quote(Quote)
    case status(ConnectionState)
}
