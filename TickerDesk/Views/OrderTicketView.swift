import SwiftUI

struct OrderTicketView: View {
    /// Owned by the presenting screen. Creating it here in `init` would hand the toolbar
    /// a fresh, unedited copy whenever a price tick rebuilds this view.
    @Bindable var ticket: OrderTicketViewModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false
    @State private var pendingOrder: PendingOrder?
    @State private var submitError: String?

    /// Snapshot taken on Review, so the order placed is exactly the one confirmed.
    private struct PendingOrder {
        let side: OrderSide
        let quantity: Int
        let type: OrderType
    }

    private var symbol: String { ticket.symbol }
    private var quote: Quote? { app.quoteStore.quotes[symbol] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Side", selection: $ticket.side) {
                        ForEach(OrderSide.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Last", value: quote?.last.currencyString ?? "—")
                    LabeledContent("Bid / Ask", value: "\(quote?.bid?.currencyString ?? "—") / \(quote?.ask?.currencyString ?? "—")")
                }

                Section("Order") {
                    LabeledContent("Quantity") {
                        TextField("Shares", text: $ticket.quantityText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: $ticket.kind) {
                        ForEach(OrderKind.allCases) { Text($0.title).tag($0) }
                    }
                    if ticket.kind == .limit {
                        LabeledContent("Limit price") {
                            TextField("0.00", text: $ticket.limitText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Estimate") {
                    LabeledContent("Price", value: ticket.estimatedPrice(quote: quote)?.currencyString ?? "—")
                    LabeledContent(
                        ticket.side == .buy ? "Est. cost" : "Est. proceeds",
                        value: ticket.estimatedNotional(quote: quote)?.currencyString ?? "—"
                    )
                    if ticket.side == .buy {
                        LabeledContent("Buying power", value: app.trading.buyingPower.currencyString)
                    } else {
                        LabeledContent("Shares available", value: "\(app.trading.availableShares(for: symbol))")
                    }
                }

                if let message = ticket.validationMessage ?? submitError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("\(ticket.side.title) \(symbol)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review", action: review)
                        .disabled(!ticket.isValid)
                }
            }
            .confirmationDialog("Confirm order", isPresented: $isConfirming, titleVisibility: .visible, presenting: pendingOrder) { order in
                Button("Place order") { submit(order) }
            } message: { order in
                Text("\(order.side.title) \(order.quantity) \(symbol) · \(order.type.title)\nPaper trading: no real money.")
            }
            .onChange(of: ticket.side) { submitError = nil }
        }
    }

    private func review() {
        guard let quantity = ticket.quantity, let type = ticket.orderType else { return }
        pendingOrder = PendingOrder(side: ticket.side, quantity: quantity, type: type)
        isConfirming = true
    }

    private func submit(_ order: PendingOrder) {
        do {
            try app.trading.submit(symbol: symbol, side: order.side, quantity: order.quantity, type: order.type, quote: quote)
            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
    }
}
