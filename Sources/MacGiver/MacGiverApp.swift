import SwiftUI

@main
struct MacGiverApp: App {
    @StateObject private var appState = AppState(registerGlobalShortcut: true)
    @StateObject private var batteryMonitor = BatteryMonitor()
    @StateObject private var storageMonitor = StorageMonitor()
    @StateObject private var audioMixer = AudioMixer()
    @StateObject private var homebrewManager = HomebrewManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(batteryMonitor)
                .environmentObject(storageMonitor)
                .environmentObject(audioMixer)
                .environmentObject(homebrewManager)
        } label: {
            Image(systemName: appState.menuBarSymbolName)
                .symbolRenderingMode(.hierarchical)
                .help("MacGiver")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
