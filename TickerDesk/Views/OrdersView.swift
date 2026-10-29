import SwiftUI

struct OrdersView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                if !app.trading.openOrders.isEmpty {
                    Section("Open") {
                        ForEach(app.trading.openOrders) { order in
                            OrderRow(order: order)
                                .swipeActions {
                                    Button("Cancel", role: .destructive) { app.trading.cancel(order.id) }
                                }
                        }
                    }
                }
                if !app.trading.closedOrders.isEmpty {
                    Section("History") {
                        ForEach(app.trading.closedOrders) { OrderRow(order: $0) }
                    }
                }
            }
            .overlay {
                if app.trading.orders.isEmpty {
                    ContentUnavailableView("No Orders", systemImage: "doc.text", description: Text("Orders you place will show up here."))
                }
            }
            .navigationTitle("Orders")
        }
    }
}

private struct OrderRow: View {
    let order: Order

    private var statusColor: Color {
        switch order.status {
        case .open: return .orange
        case .filled: return .green
        case .cancelled: return .secondary
        case .rejected: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(order.summary).font(.subheadline.weight(.semibold))
            HStack {
                Text(order.statusText).foregroundStyle(statusColor)
                Spacer()
                Text(order.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}
