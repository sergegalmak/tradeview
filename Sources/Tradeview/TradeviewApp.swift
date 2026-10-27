import SwiftUI

@main
struct TradeviewApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1_080, minHeight: 700)
        }
    }
}
