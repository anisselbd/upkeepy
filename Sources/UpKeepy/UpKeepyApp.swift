import SwiftUI

@main
struct UpKeepyApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.status.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
