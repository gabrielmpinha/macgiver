import SwiftUI

@main
struct MacGiverApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .help("MacGiver")
        }
        .menuBarExtraStyle(.window)
    }
}
