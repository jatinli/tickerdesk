import Foundation
import Testing
@testable import TickerDesk

private func d(_ string: String) -> Decimal { Decimal(string: string)! }

private func makeQuote(_ symbol: String = "AAPL", last: String, bid: String? = nil, ask: String? = nil) -> Quote {
    Quote(
        symbol: symbol,
        last: d(last),
        bid: bid.map(d),
        ask: ask.map(d),
        previousClose: d(last),
        volume: 0,
        timestamp: .now
    )
}

private func makeFill(_ side: OrderSide, _ quantity: Int, at price: String, symbol: String = "AAPL") -> Fill {
    Fill(orderID: UUID(), symbol: symbol, side: side, quantity: quantity, price: d(price), date: .now)
}

struct OrderMatchingEngineTests {
    @Test func marketBuyFillsAtAsk() {
        let order = Order(symbol: "AAPL", side: .buy, quantity: 10, type: .market)
        let quote = makeQuote(last: "100.00", bid: "99.99", ask: "100.01")
        #expect(OrderMatchingEngine.fillPrice(for: order, quote: quote) == d("100.01"))
    }

    @Test func marketSellFallsBackToLastWithoutBid() {
        let order = Order(symbol: "AAPL", side: .sell, quantity: 10, type: .market)
        #expect(OrderMatchingEngine.fillPrice(for: order, quote: makeQuote(last: "100.00")) == d("100.00"))
    }

    @Test(arguments: zip(["149.50", "150.00", "150.01"], [true, true, false]))
    func limitBuyFillsOnlyAtOrBelowLimit(ask: String, shouldFill: Bool) {
        let order = Order(symbol: "AAPL", side: .buy, quantity: 1, type: .limit(d("150.00")))
        let fill = OrderMatchingEngine.match(order, against: makeQuote(last: ask, ask: ask))
        #expect((fill != nil) == shouldFill)
    }

    @Test(arguments: zip(["150.50", "150.00", "149.99"], [true, true, false]))
    func limitSellFillsOnlyAtOrAboveLimit(bid: String, shouldFill: Bool) {
        let order = Order(symbol: "AAPL", side: .sell, quantity: 1, type: .limit(d("150.00")))
        let fill = OrderMatchingEngine.match(order, against: makeQuote(last: bid, bid: bid))
        #expect((fill != nil) == shouldFill)
    }

    @Test func ignoresQuotesForOtherSymbols() {
        let order = Order(symbol: "AAPL", side: .buy, quantity: 1, type: .market)
        #expect(OrderMatchingEngine.match(order, against: makeQuote("MSFT", last: "400.00")) == nil)
    }
}

struct PortfolioTests {
    @Test func buyReducesCashAndOpensPosition() throws {
        var portfolio = Portfolio()
        try portfolio.apply(makeFill(.buy, 10, at: "100.00"))
        #expect(portfolio.cash == Portfolio.startingCash - 1_000)
        #expect(portfolio.positions["AAPL"] == Position(symbol: "AAPL", quantity: 10, averageCost: 100))
    }

    @Test func averageCostIsWeighted() throws {
        var portfolio = Portfolio()
        try portfolio.apply(makeFill(.buy, 10, at: "100.00"))
        try portfolio.apply(makeFill(.buy, 30, at: "110.00"))
        #expect(portfolio.positions["AAPL"]?.averageCost == d("107.5"))
    }

    @Test func sellRealizesPnLAndClosesPosition() throws {
        var portfolio = Portfolio()
        try portfolio.apply(makeFill(.buy, 10, at: "100.00"))
        try portfolio.apply(makeFill(.sell, 10, at: "112.50"))
        #expect(portfolio.realizedPnL == d("125.00"))
        #expect(portfolio.positions["AAPL"] == nil)
        #expect(portfolio.cash == Portfolio.startingCash + d("125.00"))
    }

    @Test func cannotSpendMoreThanCash() {
        var portfolio = Portfolio(cash: 500)
        #expect(throws: Portfolio.PortfolioError.self) {
            try portfolio.apply(makeFill(.buy, 10, at: "100.00"))
        }
        #expect(portfolio.cash == 500)
    }

    @Test func cannotSellSharesYouDontOwn() {
        var portfolio = Portfolio()
        #expect(throws: Portfolio.PortfolioError.insufficientShares(requested: 1, available: 0)) {
            try portfolio.apply(makeFill(.sell, 1, at: "100.00"))
        }
    }

    /// With Double, 100_000 - 3 × 0.1 is 99999.69999999999.
    @Test func decimalCashMathIsExact() throws {
        var portfolio = Portfolio()
        for _ in 0..<3 {
            try portfolio.apply(makeFill(.buy, 1, at: "0.10"))
        }
        #expect(portfolio.cash == d("99999.70"))
    }
}

@MainActor
struct TradingServiceTests {
    @Test func limitOrderStaysOpenUntilPriceCrosses() throws {
        let trading = TradingService(storageURL: nil)
        try trading.submit(symbol: "AAPL", side: .buy, quantity: 10, type: .limit(d("100.00")), quote: makeQuote(last: "101.00", ask: "101.01"))
        #expect(trading.openOrders.count == 1)
        #expect(trading.buyingPower == Portfolio.startingCash - 1_000)

        trading.process(makeQuote(last: "99.98", ask: "99.99"))
        #expect(trading.openOrders.isEmpty)
        #expect(trading.portfolio.positions["AAPL"]?.quantity == 10)
        #expect(trading.portfolio.cash == Portfolio.startingCash - d("999.90"))
    }

    @Test func marketOrderNeedsAQuote() {
        let trading = TradingService(storageURL: nil)
        #expect(throws: TradingError.self) {
            try trading.submit(symbol: "AAPL", side: .buy, quantity: 1, type: .market, quote: nil)
        }
    }

    @Test func openOrdersReserveCash() throws {
        let trading = TradingService(storageURL: nil)
        let farBelow = makeQuote(last: "200.00", ask: "200.01")
        try trading.submit(symbol: "AAPL", side: .buy, quantity: 900, type: .limit(d("100.00")), quote: farBelow)
        #expect(throws: Portfolio.PortfolioError.self) {
            try trading.submit(symbol: "AAPL", side: .buy, quantity: 200, type: .limit(d("100.00")), quote: farBelow)
        }
    }

    @Test func cancellingReleasesReservedCash() throws {
        let trading = TradingService(storageURL: nil)
        let order = try trading.submit(symbol: "AAPL", side: .buy, quantity: 10, type: .limit(d("50.00")), quote: makeQuote(last: "60.00"))
        trading.cancel(order.id)
        #expect(trading.buyingPower == Portfolio.startingCash)
        #expect(trading.orders.first?.status == .cancelled)
    }
}

struct BackoffTests {
    @Test func backoffGrowsExponentiallyAndCaps() {
        #expect((1.0...1.5).contains(FinnhubMarketDataProvider.backoffDelay(attempt: 1)))
        #expect((8.0...8.5).contains(FinnhubMarketDataProvider.backoffDelay(attempt: 4)))
        #expect(FinnhubMarketDataProvider.backoffDelay(attempt: 50) <= 30.5)
    }
}
