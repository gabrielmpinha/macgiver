import SwiftUI

@main
struct MacGiverApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var batteryMonitor = BatteryMonitor()
    @StateObject private var storageMonitor = StorageMonitor()
    @StateObject private var audioMixer = AudioMixer()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(batteryMonitor)
                .environmentObject(storageMonitor)
                .environmentObject(audioMixer)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .help("MacGiver")
        }
        .menuBarExtraStyle(.window)
    }
}
