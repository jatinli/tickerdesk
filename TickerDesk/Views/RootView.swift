import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WatchlistItem.sortIndex) private var watchlist: [WatchlistItem]
    @AppStorage(SettingsKeys.requireBiometrics) private var requireBiometrics = false
    @State private var isUnlocked = false

    /// Everything that needs live prices: watchlist, holdings, open orders, open detail screens.
    private var streamSymbols: Set<String> {
        var symbols = Set(watchlist.map(\.symbol))
        symbols.formUnion(app.trading.portfolio.positions.keys)
        symbols.formUnion(app.trading.openOrders.map(\.symbol))
        symbols.formUnion(app.extraSymbols)
        return symbols
    }

    /// Restart the stream only when the symbol set or the provider actually changes.
    private var streamKey: String {
        "\(app.providerGeneration)|" + streamSymbols.sorted().joined(separator: ",")
    }

    var body: some View {
        TabView {
            WatchlistView()
                .tabItem { Label("Watchlist", systemImage: "list.bullet") }
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.pie") }
            OrdersView()
                .tabItem { Label("Orders", systemImage: "doc.text") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { seedWatchlistIfNeeded() }
        .task(id: streamKey) { app.startStreaming(symbols: streamSymbols) }
        .overlay {
            if requireBiometrics && !isUnlocked {
                LockView { isUnlocked = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { isUnlocked = false }
        }
    }

    private func seedWatchlistIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKeys.didSeedWatchlist) else { return }
        for symbol in MockMarketDataProvider.defaultWatchlist {
            let name = MockMarketDataProvider.catalog.first { $0.info.symbol == symbol }?.info.name ?? symbol
            WatchlistItem.add(SymbolInfo(symbol: symbol, name: name), to: modelContext)
        }
        defaults.set(true, forKey: SettingsKeys.didSeedWatchlist)
    }
}
