import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Text Extractor") {
                HStack {
                    Label("Text Extractor Shortcut", systemImage: "keyboard")
                    Spacer(minLength: 20)
                    ShortcutRecorderView(shortcut: appState.textExtractorShortcut) { shortcut in
                        _ = appState.setTextExtractorShortcut(shortcut)
                    }
                    .frame(width: 150, height: 26)
                }

                Text("Choose a shortcut to start Text Extractor from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = appState.textExtractorShortcutMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text("The default shortcut is Command-Shift-7.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset to Default") {
                        appState.resetTextExtractorShortcut()
                    }
                    .disabled(appState.textExtractorShortcut != .defaultValue)
                }
            }

            Section {
                Label("Screen Recording permission is required for selection.", systemImage: "record.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 580, height: 310)
    }
}
