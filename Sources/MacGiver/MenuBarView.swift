import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            BatteryMenuSummary()

            Divider()

            Toggle(isOn: Binding(
                get: { appState.keepAwakeEnabled },
                set: { _ in appState.toggleKeepAwake() }
            )) {
                FeatureRow(
                    symbol: "moon.zzz.fill",
                    title: "Keep Awake",
                    subtitle: "Prevent the Mac from sleeping"
                )
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(
                get: { appState.keyboardLockEnabled },
                set: { _ in appState.toggleKeyboardLock() }
            )) {
                FeatureRow(
                    symbol: "keyboard.fill",
                    title: "Lock Keyboard",
                    subtitle: "Clean the keys without triggering input"
                )
            }
            .toggleStyle(.switch)

            Toggle(isOn: Binding(
                get: { appState.keyboardLightEnabled ?? false },
                set: { enabled in Task { await appState.setKeyboardLightEnabled(enabled) } }
            )) {
                FeatureRow(
                    symbol: "light.min",
                    title: "Keyboard Light",
                    subtitle: appState.keyboardLightEnabled == nil
                        ? "Keyboard brightness unavailable"
                        : "Turn the keyboard backlight on or off"
                )
            }
            .toggleStyle(.switch)
            .disabled(appState.keyboardLightEnabled == nil || appState.keyboardLightChanging)

            if let message = appState.keyboardLockMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = appState.keyboardLightMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry Keyboard Light") { appState.retryKeyboardLight() }
                    .font(.caption)
            }

            Divider()

            HStack {
                Text("MacGiver 0.1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            // This task is cancelled when the panel closes. Refresh external
            // brightness changes only while the controls are visible.
            while !Task.isCancelled {
                appState.refreshKeyboardLight()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacGiver")
                    .font(.headline)
                Text("Utilities for your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
