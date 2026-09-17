import SwiftUI

private enum VolumeStyle {
    static let accent = MacGiverPalette.accent
}

struct VolumeCollapsedSummary: View {
    @EnvironmentObject private var mixer: AudioMixer
    let onExpand: () -> Void

    var body: some View {
        VolumeMenuCard {
            HStack(spacing: 9) {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VolumeStyle.accent)
                    .frame(width: 35, height: 35)
                    .background(VolumeStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Volume").font(.headline)
                    Text(mixer.defaultDeviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if mixer.defaultVolume != nil,
                   let percent = mixer.defaultDevice?.volumePercent {
                    Text("\(percent)%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Button(action: mixer.toggleDefaultMute) {
                        Image(systemName: mixer.defaultIsMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 25, height: 25)
                            .background(.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(mixer.defaultDevice?.canSetMute != true)
                    .help(mixer.defaultIsMuted ? "Unmute output" : "Mute output")
                    .accessibilityLabel(mixer.defaultIsMuted ? "Unmute output" : "Mute output")
                    .accessibilityHint("Changes the selected output device.")
                }

                Button(action: onExpand) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 25, height: 25)
                        .background(.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Show volume mixer")
                .accessibilityLabel("Show volume mixer")
            }

            if let volume = mixer.defaultVolume {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { mixer.defaultVolume ?? volume },
                            set: { mixer.setDefaultVolume($0) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.small)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .disabled(mixer.defaultDevice?.canSetVolume != true)
            } else {
                Text(mixer.message ?? "Output volume is unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume, \(mixer.defaultDeviceName)")
    }

    private var volumeSymbol: String {
        if mixer.defaultIsMuted { return "speaker.slash.fill" }
        guard let volume = mixer.defaultVolume else { return "speaker.fill" }
        if volume == 0 { return "speaker.fill" }
        if volume < 0.5 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
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

            if mixer.devices.isEmpty {
                unavailable
            } else {
                deviceList
            }

            if let message = mixer.message {
                InlineVolumeMessage(message: message)
            }

            Text("Controls the output volume exposed by macOS. App-by-app volume requires a third-party audio driver.")
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
                Text("Volume mixer")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Output devices available to macOS")
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
            .help("Refresh output devices")
            .accessibilityLabel("Refresh output devices")
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 9) {
            VolumeSectionLabel(title: "OUTPUT DEVICES", detail: "Adjust independently")
            ForEach(mixer.devices) { device in
                VolumeDeviceRow(device: device)
            }
        }
    }

    private var unavailable: some View {
        VolumeMenuCard {
            Label {
                Text("No output devices found")
            } icon: {
                Image(systemName: "speaker.slash")
            }
            .font(.subheadline.weight(.medium))
            Text("Connect an audio output and refresh the mixer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
    }
}

private struct VolumeDeviceRow: View {
    @EnvironmentObject private var mixer: AudioMixer
    let device: AudioOutputDevice

    var body: some View {
        VolumeMenuCard {
            HStack(spacing: 8) {
                Image(systemName: device.isDefault ? "checkmark.circle.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(device.isDefault ? VolumeStyle.accent : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if device.isDefault {
                        Text("DEFAULT OUTPUT")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.7)
                            .foregroundStyle(VolumeStyle.accent)
                    }
                }

                Spacer(minLength: 4)

                if let volumePercent = device.volumePercent {
                    Text("\(volumePercent)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let isMuted = device.isMuted {
                        mixer.setMuted(!isMuted, for: device.id)
                    }
                } label: {
                    Image(systemName: device.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 25, height: 25)
                        .background(device.isMuted == true ? VolumeStyle.accent.opacity(0.15) : .primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(device.isMuted == nil || !device.canSetMute)
                .help(device.isMuted == true ? "Unmute output" : "Mute output")
                .accessibilityLabel(device.isMuted == true ? "Unmute \(device.name)" : "Mute \(device.name)")
            }

            if let volume = device.volume {
                Slider(
                    value: Binding(
                        get: {
                            mixer.devices.first(where: { $0.id == device.id })?.volume.map(Double.init)
                                ?? Double(volume)
                        },
                        set: { mixer.setVolume($0, for: device.id) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)
                .tint(device.isDefault ? VolumeStyle.accent : .secondary)
                .disabled(!device.canSetVolume)
                .padding(.leading, 32)
                .padding(.top, 4)
                .accessibilityLabel("Volume for \(device.name)")
            }
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
