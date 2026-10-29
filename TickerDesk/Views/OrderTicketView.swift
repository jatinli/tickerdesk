import SwiftUI

struct OrderTicketView: View {
    let symbol: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var ticket: OrderTicketViewModel
    @State private var isConfirming = false
    @State private var submitError: String?

    init(symbol: String, initialSide: OrderSide) {
        self.symbol = symbol
        _ticket = State(initialValue: OrderTicketViewModel(symbol: symbol, side: initialSide))
    }

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
                    Button("Review") { isConfirming = true }
                        .disabled(!ticket.isValid)
                }
            }
            .confirmationDialog("Confirm order", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Place order", action: submit)
            } message: {
                if let quantity = ticket.quantity, let type = ticket.orderType {
                    Text("\(ticket.side.title) \(quantity) \(symbol) · \(type.title)\nPaper trading: no real money.")
                }
            }
            .onChange(of: ticket.side) { submitError = nil }
        }
    }

    private func submit() {
        guard let quantity = ticket.quantity, let type = ticket.orderType else { return }
        do {
            try app.trading.submit(symbol: symbol, side: ticket.side, quantity: quantity, type: type, quote: quote)
            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
    }
}
