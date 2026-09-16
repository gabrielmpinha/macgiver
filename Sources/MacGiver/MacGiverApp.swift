import SwiftUI

@main
struct MacGiverApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var batteryMonitor = BatteryMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(batteryMonitor)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .help("MacGiver")
        }
        .menuBarExtraStyle(.window)
    }
}
