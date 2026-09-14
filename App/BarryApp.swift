import SwiftUI

@main
struct BarryApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            SessionsView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
