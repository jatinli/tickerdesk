import Foundation

enum OrderSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case buy
    case sell

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum OrderType: Codable, Equatable, Sendable {
    case market
    case limit(Decimal)

    var title: String {
        switch self {
        case .market: return "MKT"
        case .limit(let price): return "LMT \(price.currencyString)"
        }
    }
}

/// Flat version of `OrderType` for pickers.
enum OrderKind: String, CaseIterable, Identifiable {
    case market
    case limit

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

struct Fill: Codable, Equatable, Sendable {
    let orderID: UUID
    let symbol: String
    let side: OrderSide
    let quantity: Int
    let price: Decimal
    let date: Date
}

enum OrderStatus: Codable, Equatable, Sendable {
    case open
    case filled(Fill)
    case cancelled
    case rejected(String)
}

struct Order: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let symbol: String
    let side: OrderSide
    let quantity: Int
    let type: OrderType
    let createdAt: Date
    var status: OrderStatus

    init(
        id: UUID = UUID(),
        symbol: String,
        side: OrderSide,
        quantity: Int,
        type: OrderType,
        createdAt: Date = .now,
        status: OrderStatus = .open
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.type = type
        self.createdAt = createdAt
        self.status = status
    }

    var isOpen: Bool { status == .open }

    /// "BUY 10 AAPL · LMT $180.00"
    var summary: String { "\(side.rawValue.uppercased()) \(quantity) \(symbol) · \(type.title)" }

    var statusText: String {
        switch status {
        case .open: return "Open"
        case .filled(let fill): return "Filled \(fill.quantity) @ \(fill.price.currencyString)"
        case .cancelled: return "Cancelled"
        case .rejected(let reason): return "Rejected: \(reason)"
        }
    }
}
