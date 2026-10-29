import Foundation

/// Decides whether an order fills against a quote. Pure functions, no state.
///
/// Buys execute at the ask and sells at the bid (falling back to the last trade
/// when the feed has no quotes), so a market order always "crosses the spread".
enum OrderMatchingEngine {
    static func fillPrice(for order: Order, quote: Quote) -> Decimal? {
        guard order.isOpen, order.symbol == quote.symbol else { return nil }

        let buyPrice = quote.ask ?? quote.last
        let sellPrice = quote.bid ?? quote.last

        switch (order.type, order.side) {
        case (.market, .buy):
            return buyPrice
        case (.market, .sell):
            return sellPrice
        case (.limit(let limit), .buy):
            return buyPrice <= limit ? buyPrice : nil
        case (.limit(let limit), .sell):
            return sellPrice >= limit ? sellPrice : nil
        }
    }

    static func match(_ order: Order, against quote: Quote, at date: Date = .now) -> Fill? {
        guard let price = fillPrice(for: order, quote: quote) else { return nil }
        return Fill(orderID: order.id, symbol: order.symbol, side: order.side, quantity: order.quantity, price: price, date: date)
    }
}
