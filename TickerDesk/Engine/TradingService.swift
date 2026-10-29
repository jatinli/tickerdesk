import Foundation
import Observation

enum TradingError: LocalizedError {
    case invalidQuantity
    case invalidLimitPrice
    case noMarketData

    var errorDescription: String? {
        switch self {
        case .invalidQuantity: return "Quantity must be at least 1 share."
        case .invalidLimitPrice: return "Limit price must be greater than zero."
        case .noMarketData: return "No live price yet. Wait for a quote or use a limit order."
        }
    }
}

private struct TradingSnapshot: Codable {
    var portfolio: Portfolio
    var orders: [Order]
}

/// Owns the paper account: accepts orders, matches open ones on every tick, and persists to disk.
@Observable
@MainActor
final class TradingService {
    private(set) var portfolio: Portfolio
    private(set) var orders: [Order]

    @ObservationIgnored private let storageURL: URL?

    nonisolated static var defaultStorageURL: URL {
        URL.applicationSupportDirectory.appending(path: "TickerDesk/trading.json")
    }

    /// Pass `nil` for an in-memory account (tests, previews).
    init(storageURL: URL? = TradingService.defaultStorageURL) {
        self.storageURL = storageURL
        if let storageURL,
           let data = try? Data(contentsOf: storageURL),
           let snapshot = try? JSONDecoder().decode(TradingSnapshot.self, from: data) {
            portfolio = snapshot.portfolio
            orders = snapshot.orders
        } else {
            portfolio = Portfolio()
            orders = []
        }
    }

    var openOrders: [Order] { orders.filter(\.isOpen) }
    var closedOrders: [Order] { orders.filter { !$0.isOpen } }

    /// Cash promised to open buy orders, so two limit orders can't spend the same dollars.
    var reservedCash: Decimal {
        openOrders.reduce(0) { total, order in
            guard order.side == .buy, case .limit(let price) = order.type else { return total }
            return total + price * Decimal(order.quantity)
        }
    }

    var buyingPower: Decimal { portfolio.cash - reservedCash }

    func reservedShares(for symbol: String) -> Int {
        openOrders
            .filter { $0.side == .sell && $0.symbol == symbol }
            .reduce(0) { $0 + $1.quantity }
    }

    func availableShares(for symbol: String) -> Int {
        (portfolio.positions[symbol]?.quantity ?? 0) - reservedShares(for: symbol)
    }

    @discardableResult
    func submit(symbol: String, side: OrderSide, quantity: Int, type: OrderType, quote: Quote?) throws -> Order {
        guard quantity > 0 else { throw TradingError.invalidQuantity }

        let referencePrice: Decimal
        switch type {
        case .limit(let price):
            guard price > 0 else { throw TradingError.invalidLimitPrice }
            referencePrice = price
        case .market:
            guard let quote else { throw TradingError.noMarketData }
            referencePrice = side == .buy ? (quote.ask ?? quote.last) : (quote.bid ?? quote.last)
        }

        try portfolio.validate(
            side: side,
            symbol: symbol,
            quantity: quantity,
            price: referencePrice,
            reservedCash: reservedCash,
            reservedShares: reservedShares(for: symbol)
        )

        let order = Order(symbol: symbol, side: side, quantity: quantity, type: type)
        orders.insert(order, at: 0)
        if let quote { process(quote) }
        save()
        return orders.first { $0.id == order.id } ?? order
    }

    /// Called for every tick (not the throttled UI stream) so limit orders never miss a cross.
    func process(_ quote: Quote) {
        var changed = false
        for index in orders.indices where orders[index].isOpen && orders[index].symbol == quote.symbol {
            guard let fill = OrderMatchingEngine.match(orders[index], against: quote) else { continue }
            do {
                try portfolio.apply(fill)
                orders[index].status = .filled(fill)
            } catch {
                orders[index].status = .rejected(error.localizedDescription)
            }
            changed = true
        }
        if changed { save() }
    }

    func cancel(_ orderID: UUID) {
        guard let index = orders.firstIndex(where: { $0.id == orderID && $0.isOpen }) else { return }
        orders[index].status = .cancelled
        save()
    }

    func resetAccount() {
        portfolio = Portfolio()
        orders = []
        save()
    }

    private func save() {
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(TradingSnapshot(portfolio: portfolio, orders: orders))
            try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
        } catch {
            print("TradingService: failed to save account: \(error)")
        }
    }
}
