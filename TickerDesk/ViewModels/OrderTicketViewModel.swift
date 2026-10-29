import Foundation
import Observation

/// Form state for the order ticket. Only checks input shape; the account rules
/// (funds, shares) are enforced by `TradingService` on submit.
@Observable
final class OrderTicketViewModel {
    let symbol: String
    var side: OrderSide
    var kind: OrderKind = .market
    var quantityText = "1"
    var limitText = ""

    init(symbol: String, side: OrderSide) {
        self.symbol = symbol
        self.side = side
    }

    var quantity: Int? {
        guard let value = Int(quantityText), value > 0 else { return nil }
        return value
    }

    var limitPrice: Decimal? {
        guard let value = Decimal(string: limitText, locale: .current), value > 0 else { return nil }
        return value.rounded(scale: 2)
    }

    var orderType: OrderType? {
        switch kind {
        case .market: return .market
        case .limit: return limitPrice.map(OrderType.limit)
        }
    }

    var isValid: Bool { quantity != nil && orderType != nil }

    var validationMessage: String? {
        if !quantityText.isEmpty, quantity == nil { return "Enter a whole number of shares." }
        if kind == .limit, !limitText.isEmpty, limitPrice == nil { return "Enter a valid limit price." }
        return nil
    }

    func estimatedPrice(quote: Quote?) -> Decimal? {
        if case .limit(let price) = orderType { return price }
        guard let quote else { return nil }
        return side == .buy ? (quote.ask ?? quote.last) : (quote.bid ?? quote.last)
    }

    func estimatedNotional(quote: Quote?) -> Decimal? {
        guard let price = estimatedPrice(quote: quote), let quantity else { return nil }
        return price * Decimal(quantity)
    }
}
