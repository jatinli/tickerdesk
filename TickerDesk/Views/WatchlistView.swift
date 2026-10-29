import SwiftData
import SwiftUI

struct WatchlistView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchlistItem.sortIndex) private var items: [WatchlistItem]
    @State private var isAddingSymbol = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    NavigationLink(value: item.symbol) {
                        QuoteRow(symbol: item.symbol, name: item.name, quote: app.quoteStore.quotes[item.symbol])
                    }
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Symbols",
                        systemImage: "star",
                        description: Text("Tap + to add a stock to your watchlist.")
                    )
                }
            }
            .connectionBanner()
            .navigationTitle("Watchlist")
            .navigationDestination(for: String.self) { StockDetailView(symbol: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAddingSymbol = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add symbol")
                }
            }
            .sheet(isPresented: $isAddingSymbol) { SymbolSearchView() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.sortIndex = index
        }
    }
}

struct SymbolSearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SymbolInfo] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { info in
                Button {
                    WatchlistItem.add(info, to: modelContext)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(info.symbol).font(.headline)
                        Text(info.name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .overlay {
                if let errorMessage {
                    ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Symbol or company")
            .autocorrectionDisabled()
            .navigationTitle("Add Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // Debounce: .task(id:) cancels the previous search when the query changes.
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                do {
                    results = try await app.provider.search(query)
                    errorMessage = nil
                } catch is CancellationError {
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
