# TickerDesk

A SwiftUI paper-trading app: live quotes, a watchlist, market and limit orders, and a portfolio with live P&L. No real money is involved.

## Running it

1. Open `TickerDesk.xcodeproj` in Xcode 16 or later.
2. Select the **TickerDesk** scheme and an iPhone simulator, then press ⌘R.
3. Press ⌘U to run the unit tests.

The app starts on **simulated** market data, so it works offline. For live US prices, get a free key at [finnhub.io](https://finnhub.io/register), then go to **Settings → Market Data**, choose **Finnhub (live)** and paste the key in. Live trades only arrive while the US market is open.

To run it on your own phone, set your team under *Signing & Capabilities* and change the bundle ID from `com.example.TickerDesk`.

## Features

- **Watchlist**: search, add, delete and reorder symbols, stored with SwiftData. Prices flash green or red when they tick.
- **Stock detail**: a Swift Charts price chart (1D / 1W / 1M) where the intraday line follows the live price, plus bid/ask, previous close, volume and your position.
- **Order ticket**: buy or sell, market or limit, an estimate of cost or proceeds, and a confirmation step.
- **Matching engine**: market orders fill at the ask (buys) or bid (sells); limit orders wait until the price crosses.
- **Portfolio**: account value, cash, buying power, and unrealized and realized P&L.
- **Orders**: open orders (swipe to cancel) and a history of fills, cancellations and rejections.
- **Security**: the API key is stored in the Keychain, and an optional Face ID / passcode lock comes back whenever the app goes to the background.
- **Resilience**: a connection banner, and automatic reconnect with exponential backoff and jitter.

## Architecture

```
Views (SwiftUI)  ──▶  ViewModels / AppModel (@Observable, @MainActor)
                              │
           ┌──────────────────┼────────────────────┐
           ▼                  ▼                    ▼
      QuoteStore        TradingService      SwiftData (watchlist)
   (throttled UI feed)  (account + orders)
           ▲                  ▲
           │  every tick ─────┘   OrderMatchingEngine, Portfolio (pure value types)
           │
   MarketDataProvider (protocol)
     ├── MockMarketDataProvider      random walk, offline
     └── FinnhubMarketDataProvider   WebSocket + REST
```

| Folder | What's in it |
|---|---|
| `Models/` | `Quote`, `Order`, `Fill`, `Portfolio`, `Position`, `WatchlistItem` |
| `Engine/` | `OrderMatchingEngine` (pure fill rules) and `TradingService` (orders, reservations, persistence) |
| `Services/` | Market data providers, `QuoteStore`, Keychain, biometrics |
| `ViewModels/` | Screen state for the stock detail screen and the order ticket |
| `Views/` | SwiftUI screens and shared components |

## Design decisions

- **`Decimal` for every amount of money.** `Double` can't store 0.10 exactly; `100_000 - 3 × 0.10` comes out as `99999.69999999999`. A test checks this. JSON numbers are converted to `Decimal` as soon as they enter the app.
- **Throttled UI, unthrottled matching.** The feed can tick hundreds of times a second. `QuoteStore` buffers quotes and publishes them to SwiftUI every 250 ms, but every tick still goes to `TradingService` so no limit order misses its price.
- **Protocol-based data layer.** Views never know which feed they're using. The mock makes the app demoable offline and keeps tests deterministic.
- **Pure core logic.** `OrderMatchingEngine` and `Portfolio` have no side effects, so the money rules are covered by fast unit tests.
- **Reserved buying power.** Open limit buys reserve their cash and open sells reserve their shares, so two orders can't spend the same money.
- **Reconnect with backoff and jitter.** Retries wait about 1s, 2s, 4s and so on, capped at 30s. The random jitter stops thousands of clients from reconnecting at the same moment after an outage.
- **Concurrency.** Feeds are `AsyncStream`s; cancelling the consuming `Task` closes the socket. UI state is `@MainActor`.
- **Secrets.** The API key is stored in the Keychain with `WhenUnlockedThisDeviceOnly`. REST calls send it in a header, not the URL. The account file on disk uses `.completeFileProtection`.

## Roadmap

- [ ] Candlestick chart with a volume overlay
- [ ] Price alerts with local notifications
- [ ] Home-screen widget for the top watchlist symbols
- [ ] Stop orders and time-in-force (DAY / GTC)
- [ ] Dynamic Type and VoiceOver pass, plus UI tests
- [ ] Index open orders by symbol so each tick isn't O(n)
