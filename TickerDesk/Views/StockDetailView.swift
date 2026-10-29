import Charts
import SwiftData
import SwiftUI

struct StockDetailView: View {
    let symbol: String

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query private var watchlistMatches: [WatchlistItem]
    @State private var model: StockDetailViewModel
    @State private var ticket: OrderTicketViewModel?

    init(symbol: String) {
        self.symbol = symbol
        _model = State(initialValue: StockDetailViewModel(symbol: symbol))
        let target = symbol
        _watchlistMatches = Query(filter: #Predicate<WatchlistItem> { $0.symbol == target })
    }

    private var quote: Quote? { app.quoteStore.quotes[symbol] }
    private var position: Position? { app.trading.portfolio.positions[symbol] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                chartSection
                statsSection
                if let position { positionSection(position) }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { tradeButtons }
        .connectionBanner()
        .navigationTitle(symbol)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: toggleWatchlist) {
                    Image(systemName: watchlistMatches.isEmpty ? "star" : "star.fill")
                }
                .accessibilityLabel(watchlistMatches.isEmpty ? "Add to watchlist" : "Remove from watchlist")
            }
        }
        .task(id: model.range) { await model.loadHistory(using: app.provider) }
        .onAppear { app.extraSymbols.insert(symbol) }
        .onDisappear { app.extraSymbols.remove(symbol) }
        .sheet(item: $ticket) { ticket in
            OrderTicketView(ticket: ticket)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quote?.last.currencyString ?? "—")
                .font(.largeTitle.bold().monospacedDigit())
                .contentTransition(.numericText())
                .animation(.default, value: quote?.last)
            if let quote {
                Text("\(quote.change.signedCurrencyString) (\(quote.changePercent.signedPercentString)) today")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(quote.change.trendColor)
            }
        }
    }

    private var chartSection: some View {
        let points = model.chartPoints(live: quote)
        // Match the header: colour by today's change when live, else by the chart's own move.
        let trend = quote?.change ?? ((points.last?.price ?? 0) - (points.first?.price ?? 0))

        return VStack(spacing: 12) {
            Chart(points) { point in
                LineMark(x: .value("Time", point.date), y: .value("Price", point.price.doubleValue))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(trend >= 0 ? Color.green : Color.red)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 220)
            .overlay {
                if model.isLoading && points.isEmpty {
                    ProgressView()
                } else if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Picker("Range", selection: $model.range) {
                ForEach(ChartRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
            StatCell(title: "Bid", value: quote?.bid?.currencyString ?? "—")
            StatCell(title: "Ask", value: quote?.ask?.currencyString ?? "—")
            StatCell(title: "Prev. close", value: quote?.previousClose.currencyString ?? "—")
            StatCell(title: "Volume", value: quote.map { $0.volume.formatted(.number.notation(.compactName).locale(.usMarket)) } ?? "—")
        }
    }

    private func positionSection(_ position: Position) -> some View {
        let price = quote?.last ?? position.averageCost
        let pnl = position.unrealizedPnL(at: price)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Your position").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                StatCell(title: "Shares", value: "\(position.quantity)")
                StatCell(title: "Avg. cost", value: position.averageCost.currencyString)
                StatCell(title: "Market value", value: position.marketValue(at: price).currencyString)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unrealized P&L").font(.caption).foregroundStyle(.secondary)
                    Text(pnl.signedCurrencyString).font(.body.monospacedDigit()).foregroundStyle(pnl.trendColor)
                }
            }
        }
    }

    private var tradeButtons: some View {
        HStack(spacing: 12) {
            Button { ticket = OrderTicketViewModel(symbol: symbol, side: .buy) } label: { Text("Buy").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            Button { ticket = OrderTicketViewModel(symbol: symbol, side: .sell) } label: { Text("Sell").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(position == nil)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private func toggleWatchlist() {
        if watchlistMatches.isEmpty {
            let name = MockMarketDataProvider.catalog.first { $0.info.symbol == symbol }?.info.name ?? symbol
            WatchlistItem.add(SymbolInfo(symbol: symbol, name: name), to: modelContext)
        } else {
            WatchlistItem.remove(symbol, from: modelContext)
        }
    }
}
