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

        Window("Battery — MacGiver", id: "battery") {
            BatteryDashboardView()
                .environmentObject(batteryMonitor)
        }
        .defaultSize(width: 960, height: 850)
        .windowResizability(.contentMinSize)
    }
}
