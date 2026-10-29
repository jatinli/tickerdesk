import Foundation
import SwiftData

@Model
final class WatchlistItem {
    @Attribute(.unique) var symbol: String
    var name: String
    var sortIndex: Int

    init(symbol: String, name: String, sortIndex: Int) {
        self.symbol = symbol
        self.name = name
        self.sortIndex = sortIndex
    }
}

extension WatchlistItem {
    static func contains(_ symbol: String, in context: ModelContext) -> Bool {
        let target = symbol
        let descriptor = FetchDescriptor<WatchlistItem>(predicate: #Predicate { $0.symbol == target })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    static func add(_ info: SymbolInfo, to context: ModelContext) {
        guard !contains(info.symbol, in: context) else { return }
        let count = (try? context.fetchCount(FetchDescriptor<WatchlistItem>())) ?? 0
        context.insert(WatchlistItem(symbol: info.symbol, name: info.name, sortIndex: count))
    }

    static func remove(_ symbol: String, from context: ModelContext) {
        let target = symbol
        let descriptor = FetchDescriptor<WatchlistItem>(predicate: #Predicate { $0.symbol == target })
        for item in (try? context.fetch(descriptor)) ?? [] {
            context.delete(item)
        }
    }
}
