import Foundation
import Observation

enum DataSource: String, CaseIterable, Identifiable {
    case simulated
    case finnhub

    var id: Self { self }

    var title: String {
        switch self {
        case .simulated: return "Simulated"
        case .finnhub: return "Finnhub (live)"
        }
    }
}

enum SettingsKeys {
    static let dataSource = "dataSource"
    static let requireBiometrics = "requireBiometrics"
    static let didSeedWatchlist = "didSeedWatchlist"
}

/// App-wide dependencies, injected into the view tree with `.environment(_:)`.
@Observable
@MainActor
final class AppModel {
    let quoteStore = QuoteStore()
    let trading: TradingService

    /// Symbols that need live prices but aren't on the watchlist, e.g. an open detail screen.
    var extraSymbols: Set<String> = []

    var dataSource: DataSource {
        didSet {
            guard dataSource != oldValue else { return }
            UserDefaults.standard.set(dataSource.rawValue, forKey: SettingsKeys.dataSource)
            rebuildProvider()
        }
    }

    private(set) var provider: any MarketDataProvider
    /// Bumped whenever `provider` changes so views can restart the stream.
    private(set) var providerGeneration = 0
    /// True when Finnhub is selected but no API key is saved yet.
    private(set) var isUsingFallbackData = false

    init(trading: TradingService? = nil) {
        self.trading = trading ?? TradingService()

        let source = DataSource(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.dataSource) ?? "") ?? .simulated
        dataSource = source
        let (provider, isFallback) = Self.makeProvider(for: source)
        self.provider = provider
        isUsingFallbackData = isFallback

        quoteStore.onTick = { [weak trading = self.trading] quote in
            trading?.process(quote)
        }
    }

    func rebuildProvider() {
        let (provider, isFallback) = Self.makeProvider(for: dataSource)
        self.provider = provider
        isUsingFallbackData = isFallback
        providerGeneration += 1
    }

    func startStreaming(symbols: Set<String>) {
        quoteStore.start(provider: provider, symbols: symbols)
    }

    private static func makeProvider(for source: DataSource) -> (any MarketDataProvider, Bool) {
        switch source {
        case .simulated:
            return (MockMarketDataProvider(), false)
        case .finnhub:
            if let key = KeychainStore.string(for: KeychainKey.finnhubAPIKey), !key.isEmpty {
                return (FinnhubMarketDataProvider(apiKey: key), false)
            }
            return (MockMarketDataProvider(), true)
        }
    }
}
