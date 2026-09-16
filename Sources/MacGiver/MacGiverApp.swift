import SwiftUI

@main
struct MacGiverApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var batteryMonitor = BatteryMonitor()
    @StateObject private var storageMonitor = StorageMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(batteryMonitor)
                .environmentObject(storageMonitor)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .help("MacGiver")
        }
        .menuBarExtraStyle(.window)
    }
}
