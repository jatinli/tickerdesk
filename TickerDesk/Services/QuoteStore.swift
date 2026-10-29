import Foundation
import Observation

/// Holds the latest quote per symbol for the UI.
///
/// A busy feed can deliver hundreds of ticks a second. Publishing each one would
/// re-render SwiftUI constantly, so ticks are buffered and flushed a few times a second.
/// Order matching still sees every tick through `onTick`.
@Observable
@MainActor
final class QuoteStore {
    private(set) var quotes: [String: Quote] = [:]
    private(set) var connection: ConnectionState = .disconnected

    /// Unthrottled, called for every tick.
    @ObservationIgnored var onTick: (@MainActor (Quote) -> Void)?

    @ObservationIgnored private var pending: [String: Quote] = [:]
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let flushInterval: Duration

    init(flushInterval: Duration = .milliseconds(250)) {
        self.flushInterval = flushInterval
    }

    func start(provider: any MarketDataProvider, symbols: Set<String>) {
        stop()
        guard !symbols.isEmpty else { return }

        let stream = provider.events(for: symbols)
        streamTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }

        let interval = flushInterval
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                self.flush()
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        flushTask?.cancel()
        streamTask = nil
        flushTask = nil
        flush()
        connection = .disconnected
    }

    private func handle(_ event: MarketEvent) {
        switch event {
        case .quote(let quote):
            pending[quote.symbol] = quote
            onTick?(quote)
        case .status(let state):
            connection = state
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        quotes.merge(pending) { _, new in new }
        pending.removeAll(keepingCapacity: true)
    }
}
