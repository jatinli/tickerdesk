import SwiftUI

extension Decimal {
    var trendColor: Color {
        if self > 0 { return .green }
        if self < 0 { return .red }
        return .secondary
    }
}

/// Watchlist row. Briefly flashes green/red when the price ticks up/down.
struct QuoteRow: View {
    let symbol: String
    let name: String
    let quote: Quote?

    @State private var flash: Color?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(symbol).font(.headline)
                Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let quote {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(quote.last.currencyString)
                        .font(.body.monospacedDigit())
                        .padding(.horizontal, 4)
                        .background(flash?.opacity(0.3) ?? .clear, in: RoundedRectangle(cornerRadius: 4))
                    ChangePill(percent: quote.changePercent)
                }
            } else {
                ProgressView()
            }
        }
        .onChange(of: quote?.last) { old, new in
            guard let old, let new, old != new else { return }
            flash = new > old ? .green : .red
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeOut(duration: 0.5)) { flash = nil }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChangePill: View {
    let percent: Decimal

    var body: some View {
        Text(percent.signedPercentString)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 64)
            .background(percent >= 0 ? Color.green : Color.red, in: Capsule())
    }
}

struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Connection banner

private struct ConnectionBannerModifier: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = message(for: app.quoteStore.connection) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text(message).font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                    .background(Color.orange)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: app.quoteStore.connection)
    }

    private func message(for state: ConnectionState) -> String? {
        switch state {
        case .connected, .disconnected:
            return nil
        case .connecting:
            return "Connecting to market data…"
        case let .reconnecting(attempt, retryIn):
            return "Connection lost. Retrying in \(Int(retryIn.rounded(.up)))s (attempt \(attempt))"
        }
    }
}

extension View {
    func connectionBanner() -> some View {
        modifier(ConnectionBannerModifier())
    }
}
