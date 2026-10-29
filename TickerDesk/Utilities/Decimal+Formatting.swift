import Foundation

extension Locale {
    static let usMarket = Locale(identifier: "en_US")
}

// Money is always `Decimal`. `Double` is binary floating point and can't represent
// values like 0.10 exactly, so cash balances would drift after a few hundred trades.
extension Decimal {
    /// One cent, built without going through a `Double` literal.
    static let cent = Decimal(sign: .plus, exponent: -2, significand: 1)

    func rounded(scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .bankers) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }

    /// For display-only APIs such as Swift Charts. Never use the result for arithmetic.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// US listings are quoted in US format whatever the phone's region ($100,000.00, not $1,00,000.00).
    var currencyString: String { formatted(.currency(code: "USD").locale(.usMarket)) }

    var signedCurrencyString: String { (self > 0 ? "+" : "") + currencyString }

    /// `0.0123` → `"+1.23%"`
    var signedPercentString: String {
        let percent = (self * 100).formatted(.number.precision(.fractionLength(2)).locale(.usMarket))
        return (self > 0 ? "+" : "") + percent + "%"
    }
}
