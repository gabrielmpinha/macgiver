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
    @EnvironmentObject private var audioMixer: AudioMixer
    @Environment(\.openSettings) private var openSettings
    @State private var expandedPanel: ExpandedPanel?
    @State private var availableHeight: CGFloat = 700
    @State private var openingScreenID: NSNumber?

    private enum ExpandedPanel {
        case battery
        case storage
        case volume
    }

    private var activeUtilities: Int {
        [
            appState.keepAwakeEnabled,
            appState.keyboardLockEnabled,
            appState.keyboardLightEnabled == true
        ].filter { $0 }.count
    }

    var body: some View {
        ContentSizedScrollView(maxHeight: availableHeight) {
            Group {
                if expandedPanel != nil {
                    expandedContent
                } else {
                    compactContent
                }
            }
            .padding(14)
        }
        .id(expandedPanel)
        .frame(width: 380, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
        .tint(MacGiverPalette.accent)
        .onAppear { updateAvailableHeight(isOpening: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updateAvailableHeight()
        }
        .task {
            // External keyboard brightness changes are relevant only while the
            // menu panel is visible.
            while !Task.isCancelled {
                appState.refreshKeyboardLight()
                audioMixer.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        .onDisappear {
            // Reopen at the glanceable summary instead of restoring a tall panel.
            expandedPanel = nil
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 12) {
                BatteryCollapsedSummary(onExpand: { expandedPanel = .battery })
                StorageCollapsedSummary(onExpand: { expandedPanel = .storage })
            }
            VolumeCollapsedSummary(onExpand: { expandedPanel = .volume })
            controls
            messages
            footer
        }
    }

    private func updateAvailableHeight(isOpening: Bool = false) {
        let screenIDKey = NSDeviceDescriptionKey("NSScreenNumber")
        let openingScreen = NSScreen.screens.first {
            openingScreenID != nil && $0.deviceDescription[screenIDKey] as? NSNumber == openingScreenID
        }
        let pointerScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let screen = isOpening ? (pointerScreen ?? NSScreen.main) : (openingScreen ?? NSScreen.main)
        openingScreenID = screen?.deviceDescription[screenIDKey] as? NSNumber
        availableHeight = min(700, max(1, (screen?.visibleFrame.height ?? 724) - 24))
    }

    private var expandedContent: some View {
        Group {
            switch expandedPanel {
            case .battery:
                BatteryMenuPanel { expandedPanel = nil }
            case .storage:
                StorageMenuPanel { expandedPanel = nil }
            case .volume:
                VolumeMenuPanel { expandedPanel = nil }
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
            HStack(alignment: .firstTextBaseline) {
                Text("QUICK CONTROLS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.15)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    appState.beginTextExtraction()
                } label: {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacGiverPalette.accent)
                        .padding(4)
                        .background(MacGiverPalette.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Text Extractor")
                .accessibilityLabel(Text("Text Extractor"))
                .accessibilityHint(Text("Select text from anywhere"))
            }

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
                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .help("Settings")
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

/// Measure the unconstrained content, then scroll only when it exceeds the screen budget.
/// A fixed initial height keeps MenuBarExtra from proposing zero to a bare ScrollView.
struct ContentSizedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
                    }
                }
        }
        .frame(height: min(contentHeight ?? maxHeight, maxHeight))
        .onPreferenceChange(PanelContentHeight.self) { height in
            if height > 0 { contentHeight = height }
        }
    }
}

private struct PanelContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SummaryTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String
    let status: String
    let detail: String
    let progress: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 20)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let progress {
                ProgressView(value: progress, total: 100)
                    .tint(tint)
                    .accessibilityHidden(true)
            }

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(12)
        .frame(width: 170, height: 170, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SummaryButtonStyle: ButtonStyle {
    var tint: Color = MacGiverPalette.accent

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, tint: tint)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    tint.opacity(configuration.isPressed ? 0.14 : isHovered ? 0.09 : 0.045),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(isHovered ? 0.30 : 0.12))
                }
                .onHover { isHovered = $0 }
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
