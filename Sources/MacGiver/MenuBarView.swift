import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

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

            if let message = appState.keyboardLockMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
