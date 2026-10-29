import SwiftData
import SwiftUI

@main
struct TickerDeskApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(for: WatchlistItem.self)
    }
}
