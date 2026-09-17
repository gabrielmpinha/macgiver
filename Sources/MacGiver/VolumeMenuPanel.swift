import SwiftUI

private enum VolumeStyle {
    static let accent = MacGiverPalette.accent
}

struct VolumeCollapsedSummary: View {
    @EnvironmentObject private var mixer: AudioMixer
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VolumeStyle.accent)
                    .frame(width: 35, height: 35)
                    .background(
                        VolumeStyle.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("App volume")
                        .font(.headline)
                    Text(mixer.applicationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if mixer.activeApplicationCount > 0 {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(MacGiverPalette.success)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(SummaryButtonStyle())
        .help("Show app volume mixer")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("App volume mixer")
        .accessibilityValue(mixer.applicationSummary)
        .accessibilityHint("Show app volume mixer")
    }
}

struct VolumeMenuPanel: View {
    @EnvironmentObject private var mixer: AudioMixer
    private let onCollapse: () -> Void

    init(onCollapse: @escaping () -> Void = {}) {
        self.onCollapse = onCollapse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailHeader

            if mixer.applications.isEmpty {
                unavailable
            } else {
                applicationList
            }

            if let message = mixer.message {
                InlineVolumeMessage(message: message)
            }

            Text("Each slider controls one app independently. macOS may ask for System Audio Recording permission when the mixer starts.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            mixer.refresh()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to quick controls")
            .accessibilityLabel("Back to quick controls")

            VStack(alignment: .leading, spacing: 2) {
                Text("App volume mixer")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Adjust each app independently")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: mixer.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Refresh applications")
            .accessibilityLabel("Refresh applications")
        }
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 9) {
            VolumeSectionLabel(title: "APPLICATIONS", detail: "Independent levels")
            ForEach(mixer.applications) { application in
                VolumeApplicationRow(application: application)
            }
        }
    }

    private var unavailable: some View {
        VolumeMenuCard {
            Label {
                Text("No audio applications found")
            } icon: {
                Image(systemName: "waveform.slash")
            }
            .font(.subheadline.weight(.medium))
            Text("Open an app that can play audio, then refresh the mixer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
    }
}

private struct VolumeApplicationRow: View {
    @EnvironmentObject private var mixer: AudioMixer
    let application: AudioApplication

    var body: some View {
        VolumeMenuCard {
            HStack(spacing: 8) {
                Image(systemName: application.isMuted ? "speaker.slash.fill" : "app.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(application.isAudioActive ? VolumeStyle.accent : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(application.isAudioActive ? "PLAYING" : "AVAILABLE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(
                            application.isAudioActive
                                ? VolumeStyle.accent
                                : Color.secondary.opacity(0.65)
                        )
                }

                Spacer(minLength: 4)

                Text(application.isMuted ? "Muted" : "\(application.volumePercent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(application.isMuted ? .secondary : .primary)

                Button {
                    mixer.toggleMute(for: application.id)
                } label: {
                    Image(systemName: application.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 25, height: 25)
                        .background(
                            application.isMuted
                                ? VolumeStyle.accent.opacity(0.15)
                                : .primary.opacity(0.06),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help(application.isMuted ? "Unmute \(application.name)" : "Mute \(application.name)")
                .accessibilityLabel(application.isMuted ? "Unmute \(application.name)" : "Mute \(application.name)")
            }

            Slider(
                value: Binding(
                    get: {
                        mixer.applications.first(where: { $0.id == application.id }).map { Double($0.volume) }
                            ?? Double(application.volume)
                    },
                    set: { mixer.setVolume($0, for: application.id) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .tint(application.isAudioActive ? VolumeStyle.accent : .secondary)
            .padding(.leading, 32)
            .padding(.top, 4)
            .accessibilityLabel("Volume for \(application.name)")
            .accessibilityValue(application.isMuted ? "Muted" : "\(application.volumePercent) percent")
        }
        .accessibilityElement(children: .contain)
    }
}

private struct VolumeMenuCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07))
            }
    }
}

private struct VolumeSectionLabel: View {
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

private struct InlineVolumeMessage: View {
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
