import SwiftUI

struct PortfolioView: View {
    @Environment(AppModel.self) private var app
    @State private var isConfirmingReset = false

    private var quotes: [String: Quote] { app.quoteStore.quotes }
    private var portfolio: Portfolio { app.trading.portfolio }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Account value", value: portfolio.equity(quotes: quotes).currencyString)
                        .font(.headline)
                    LabeledContent("Cash", value: portfolio.cash.currencyString)
                    LabeledContent("Buying power", value: app.trading.buyingPower.currencyString)
                    pnlRow("Unrealized P&L", portfolio.unrealizedPnL(quotes: quotes))
                    pnlRow("Realized P&L", portfolio.realizedPnL)
                }
                .monospacedDigit()

                Section("Positions") {
                    if portfolio.positions.isEmpty {
                        Text("No positions yet. Open a stock from your watchlist and tap Buy.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(portfolio.positions.values.sorted { $0.symbol < $1.symbol }, id: \.symbol) { position in
                            NavigationLink(value: position.symbol) {
                                PositionRow(position: position, quote: quotes[position.symbol])
                            }
                        }
                    }
                }
            }
            .connectionBanner()
            .navigationTitle("Portfolio")
            .navigationDestination(for: String.self) { StockDetailView(symbol: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reset Paper Account", role: .destructive) { isConfirmingReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Reset paper account?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { app.trading.resetAccount() }
            } message: {
                Text("Clears all positions and orders and restores \(Portfolio.startingCash.currencyString) in cash.")
            }
        }
    }

    private func pnlRow(_ title: String, _ value: Decimal) -> some View {
        LabeledContent(title) {
            Text(value.signedCurrencyString).foregroundStyle(value.trendColor)
        }
    }
}

private struct PositionRow: View {
    let position: Position
    let quote: Quote?

    var body: some View {
        let price = quote?.last ?? position.averageCost
        let pnl = position.unrealizedPnL(at: price)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.symbol).font(.headline)
                Text("\(position.quantity) shares @ \(position.averageCost.currencyString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.marketValue(at: price).currencyString)
                Text(pnl.signedCurrencyString).font(.caption).foregroundStyle(pnl.trendColor)
            }
            .monospacedDigit()
        }
    }
}
