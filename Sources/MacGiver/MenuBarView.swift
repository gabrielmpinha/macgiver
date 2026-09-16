import AppKit
import SwiftUI

enum MacGiverPalette {
    static let accent = Color(red: 0.31, green: 0.36, blue: 0.95)
    static let success = Color(red: 0.16, green: 0.68, blue: 0.52)
    static let warm = Color(red: 0.93, green: 0.57, blue: 0.18)
    static let violet = Color(red: 0.56, green: 0.44, blue: 0.91)
}

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var expandedPanel: ExpandedPanel?

    private enum ExpandedPanel {
        case battery
        case storage
    }

    private var activeUtilities: Int {
        [
            appState.keepAwakeEnabled,
            appState.keyboardLockEnabled,
            appState.keyboardLightEnabled == true
        ].filter { $0 }.count
    }

    var body: some View {
        Group {
            if expandedPanel != nil {
                ScrollView {
                    expandedContent
                        .padding(14)
                }
            } else {
                ScrollView {
                    compactContent
                        .padding(14)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 380, height: expandedPanel == nil ? 570 : 700, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .tint(MacGiverPalette.accent)
        .task {
            // External keyboard brightness changes are relevant only while the
            // menu panel is visible.
            while !Task.isCancelled {
                appState.refreshKeyboardLight()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onDisappear {
            // Reopen at the glanceable summary instead of restoring a tall panel.
            expandedPanel = nil
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            BatteryCollapsedSummary(onExpand: { expandedPanel = .battery })
            StorageCollapsedSummary(onExpand: { expandedPanel = .storage })
            controls
            messages
            footer
        }
    }

    private var expandedContent: some View {
        Group {
            switch expandedPanel {
            case .battery:
                BatteryMenuPanel { expandedPanel = nil }
            case .storage:
                StorageMenuPanel { expandedPanel = nil }
            case nil:
                EmptyView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MacGiverPalette.accent, MacGiverPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .shadow(color: MacGiverPalette.accent.opacity(0.22), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacGiver")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Small utilities. Less friction.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            StatusBadge(activeUtilities: activeUtilities)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "QUICK CONTROLS", detail: "Click a row to change")

            utilityToggle(
                isOn: appState.keepAwakeEnabled,
                accent: MacGiverPalette.warm,
                binding: Binding(
                    get: { appState.keepAwakeEnabled },
                    set: { _ in appState.toggleKeepAwake() }
                )
            ) {
                UtilityRow(
                    symbol: "moon.zzz.fill",
                    title: "Keep Awake",
                    subtitle: "Prevent idle system sleep",
                    accent: MacGiverPalette.warm,
                    isActive: appState.keepAwakeEnabled
                )
            }

            utilityToggle(
                isOn: appState.keyboardLockEnabled,
                accent: MacGiverPalette.violet,
                binding: Binding(
                    get: { appState.keyboardLockEnabled },
                    set: { _ in appState.toggleKeyboardLock() }
                )
            ) {
                UtilityRow(
                    symbol: "keyboard.fill",
                    title: "Lock Keyboard",
                    subtitle: "Clean the keys without input",
                    accent: MacGiverPalette.violet,
                    isActive: appState.keyboardLockEnabled
                )
            }

            utilityToggle(
                isOn: appState.keyboardLightEnabled == true,
                accent: MacGiverPalette.accent,
                binding: Binding(
                    get: { appState.keyboardLightEnabled == true },
                    set: { enabled in Task { await appState.setKeyboardLightEnabled(enabled) } }
                )
            ) {
                UtilityRow(
                    symbol: "light.min",
                    title: "Keyboard Light",
                    subtitle: appState.keyboardLightEnabled == nil
                        ? "Unavailable on this Mac"
                        : "Toggle the built-in backlight",
                    accent: MacGiverPalette.accent,
                    isActive: appState.keyboardLightEnabled == true,
                    isAvailable: appState.keyboardLightEnabled != nil
                )
            }
            .disabled(appState.keyboardLightEnabled == nil || appState.keyboardLightChanging)
        }
    }

    private func utilityToggle<Label: View>(
        isOn: Bool,
        accent: Color,
        binding: Binding<Bool>,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Toggle(isOn: binding, label: label)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                isOn ? accent.opacity(0.12) : .primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isOn ? accent.opacity(0.24) : .primary.opacity(0.06), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.14), value: isOn)
    }

    @ViewBuilder
    private var messages: some View {
        if appState.keyboardLockMessage != nil || appState.keyboardLightMessage != nil {
            VStack(alignment: .leading, spacing: 7) {
                if let message = appState.keyboardLockMessage {
                    InlineMessage(message: message)
                }
                if let message = appState.keyboardLightMessage {
                    InlineMessage(message: message)
                    Button("Retry Keyboard Light") {
                        appState.retryKeyboardLight()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(MacGiverPalette.success)
                    .frame(width: 6, height: 6)
                Text("MacGiver \(AppMetadata.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit MacGiver")
            }
        }
    }
}

private struct StatusBadge: View {
    let activeUtilities: Int

    private var isActive: Bool { activeUtilities > 0 }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? MacGiverPalette.success : .secondary)
                .frame(width: 5, height: 5)
            Group {
                if isActive {
                    Text("\(activeUtilities) ON", comment: "Compact count of enabled utilities.")
                } else {
                    Text("READY")
                }
            }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(isActive ? MacGiverPalette.success : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.primary.opacity(0.045), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive
            ? Text("\(activeUtilities) utilities active", comment: "VoiceOver count of enabled utilities.")
            : Text("No utilities active"))
    }
}

private struct SectionLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.15)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
    }
}

private struct UtilityRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let accent: Color
    let isActive: Bool
    var isAvailable = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isAvailable ? accent : .secondary)
                .frame(width: 29, height: 29)
                .background(
                    (isActive ? accent : .primary).opacity(isAvailable ? 0.13 : 0.06),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct InlineMessage: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
