import Foundation

struct Position: Codable, Equatable, Sendable {
    let symbol: String
    var quantity: Int
    var averageCost: Decimal

    var costBasis: Decimal { averageCost * Decimal(quantity) }

    func marketValue(at price: Decimal) -> Decimal { price * Decimal(quantity) }

    func unrealizedPnL(at price: Decimal) -> Decimal { (price - averageCost) * Decimal(quantity) }
}

/// Cash + long positions. Pure value type so the accounting rules are easy to unit test.
/// Short selling isn't supported: you can only sell shares you hold.
struct Portfolio: Codable, Equatable, Sendable {
    static let startingCash: Decimal = 100_000

    var cash: Decimal
    var positions: [String: Position]
    var realizedPnL: Decimal

    init(cash: Decimal = Portfolio.startingCash, positions: [String: Position] = [:], realizedPnL: Decimal = 0) {
        self.cash = cash
        self.positions = positions
        self.realizedPnL = realizedPnL
    }

    enum PortfolioError: LocalizedError, Equatable {
        case insufficientFunds(required: Decimal, available: Decimal)
        case insufficientShares(requested: Int, available: Int)

        var errorDescription: String? {
            switch self {
            case let .insufficientFunds(required, available):
                return "Needs \(required.currencyString), but only \(available.currencyString) is available."
            case let .insufficientShares(requested, available):
                return "Can't sell \(requested) shares; only \(available) available."
            }
        }
    }

    /// Pre-trade check. `reservedCash` / `reservedShares` are held by other open orders.
    func validate(
        side: OrderSide,
        symbol: String,
        quantity: Int,
        price: Decimal,
        reservedCash: Decimal = 0,
        reservedShares: Int = 0
    ) throws {
        switch side {
        case .buy:
            let required = price * Decimal(quantity)
            let available = cash - reservedCash
            if required > available {
                throw PortfolioError.insufficientFunds(required: required, available: available)
            }
        case .sell:
            let available = (positions[symbol]?.quantity ?? 0) - reservedShares
            if quantity > available {
                throw PortfolioError.insufficientShares(requested: quantity, available: available)
            }
        }
    }

    mutating func apply(_ fill: Fill) throws {
        try validate(side: fill.side, symbol: fill.symbol, quantity: fill.quantity, price: fill.price)
        let notional = fill.price * Decimal(fill.quantity)

        switch fill.side {
        case .buy:
            cash -= notional
            var position = positions[fill.symbol] ?? Position(symbol: fill.symbol, quantity: 0, averageCost: 0)
            let newQuantity = position.quantity + fill.quantity
            position.averageCost = ((position.costBasis + notional) / Decimal(newQuantity)).rounded(scale: 4)
            position.quantity = newQuantity
            positions[fill.symbol] = position

        case .sell:
            guard var position = positions[fill.symbol] else { return }
            cash += notional
            realizedPnL += (fill.price - position.averageCost) * Decimal(fill.quantity)
            position.quantity -= fill.quantity
            positions[fill.symbol] = position.quantity == 0 ? nil : position
        }
    }

    func marketValue(quotes: [String: Quote]) -> Decimal {
        positions.values.reduce(0) { total, position in
            total + position.marketValue(at: quotes[position.symbol]?.last ?? position.averageCost)
        }
    }

    func equity(quotes: [String: Quote]) -> Decimal { cash + marketValue(quotes: quotes) }

    func unrealizedPnL(quotes: [String: Quote]) -> Decimal {
        positions.values.reduce(0) { total, position in
            total + position.unrealizedPnL(at: quotes[position.symbol]?.last ?? position.averageCost)
        }
    }
}
