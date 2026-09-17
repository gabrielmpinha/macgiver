import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    let id: UInt32
    let name: String
    let volume: Float?
    let isMuted: Bool?
    let isDefault: Bool
    let canSetVolume: Bool
    let canSetMute: Bool

    var volumePercent: Int? {
        guard let volume else { return nil }
        return Int((volume * 100).rounded())
    }
}

@MainActor
protocol AudioHardwareProviding {
    func outputDevices() -> [AudioOutputDevice]
    func setVolume(_ volume: Float, for deviceID: UInt32) -> Bool
    func setMuted(_ muted: Bool, for deviceID: UInt32) -> Bool
}

@MainActor
final class AudioMixer: ObservableObject {
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var message: String?

    private let hardware: any AudioHardwareProviding
    private var readbackTask: Task<Void, Never>?

    init(hardware: any AudioHardwareProviding = SystemAudioHardware()) {
        self.hardware = hardware
        refresh()
    }

    var defaultDevice: AudioOutputDevice? {
        devices.first(where: \.isDefault) ?? devices.first
    }

    var defaultVolume: Double? {
        defaultDevice?.volume.map(Double.init)
    }

    var defaultIsMuted: Bool {
        defaultDevice?.isMuted ?? false
    }

    var defaultDeviceName: String {
        defaultDevice?.name ?? String(localized: "No output device")
    }

    func refresh() {
        devices = hardware.outputDevices()
        if devices.isEmpty {
            message = String(localized: "No output devices found.")
        } else if message == String(localized: "No output devices found.") {
            message = nil
        }
    }

    func setDefaultVolume(_ volume: Double) {
        guard let device = defaultDevice else { return }
        setVolume(volume, for: device.id)
    }

    func toggleDefaultMute() {
        guard let device = defaultDevice, let isMuted = device.isMuted else { return }
        setMuted(!isMuted, for: device.id)
    }

    func setVolume(_ volume: Double, for deviceID: UInt32) {
        guard volume.isFinite else { return }
        let clamped = Float(min(max(volume, 0), 1))
        guard hardware.setVolume(clamped, for: deviceID) else {
            refresh()
            message = String(localized: "Could not change output volume. Try again.")
            return
        }
        updateLocalVolume(clamped, for: deviceID)
        scheduleReadback()
    }

    func setMuted(_ muted: Bool, for deviceID: UInt32) {
        guard hardware.setMuted(muted, for: deviceID) else {
            refresh()
            message = String(localized: "Could not change output mute. Try again.")
            return
        }
        updateLocalMute(muted, for: deviceID)
        scheduleReadback()
    }

    private func updateLocalVolume(_ volume: Float, for deviceID: UInt32) {
        devices = devices.map { device in
            guard device.id == deviceID else { return device }
            return AudioOutputDevice(id: device.id, name: device.name, volume: volume,
                                     isMuted: device.isMuted, isDefault: device.isDefault,
                                     canSetVolume: device.canSetVolume, canSetMute: device.canSetMute)
        }
    }

    private func updateLocalMute(_ muted: Bool, for deviceID: UInt32) {
        devices = devices.map { device in
            guard device.id == deviceID else { return device }
            return AudioOutputDevice(id: device.id, name: device.name, volume: device.volume,
                                     isMuted: muted, isDefault: device.isDefault,
                                     canSetVolume: device.canSetVolume, canSetMute: device.canSetMute)
        }
    }

    private func scheduleReadback() {
        readbackTask?.cancel()
        readbackTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

@MainActor
final class SystemAudioHardware: AudioHardwareProviding {
    func outputDevices() -> [AudioOutputDevice] {
        let devices = audioDeviceIDs()
        let defaultDeviceID = defaultOutputDeviceID()

        return devices.compactMap { deviceID in
            guard hasOutputChannels(for: deviceID) else { return nil }

            let volumeAddress = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput
            )
            let muteAddress = propertyAddress(
                selector: kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput
            )

            return AudioOutputDevice(
                id: deviceID,
                name: deviceName(for: deviceID) ?? String(localized: "Unknown output"),
                volume: scalarValue(for: deviceID, address: volumeAddress),
                isMuted: muteValue(for: deviceID, address: muteAddress),
                isDefault: deviceID == defaultDeviceID,
                canSetVolume: isPropertySettable(deviceID, address: volumeAddress),
                canSetMute: isPropertySettable(deviceID, address: muteAddress)
            )
        }
    }

    func setVolume(_ volume: Float, for deviceID: UInt32) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard isPropertySettable(deviceID, address: address) else { return false }
        var value = volume
        let size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    func setMuted(_ muted: Bool, for deviceID: UInt32) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard isPropertySettable(deviceID, address: address) else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value) == noErr
    }

    private func audioDeviceIDs() -> [UInt32] {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<UInt32>.size) else {
            return []
        }

        let count = Int(size) / MemoryLayout<UInt32>.size
        var devices = [UInt32](repeating: 0, count: count)
        let status = devices.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                bytes.baseAddress!
            )
        }
        return status == noErr ? devices : []
    }

    private func defaultOutputDeviceID() -> UInt32? {
        var address = propertyAddress(
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var deviceID: UInt32 = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    private func hasOutputChannels(for deviceID: UInt32) -> Bool {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return false
        }

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { pointer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer) == noErr else {
            return false
        }

        let bufferList = pointer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private func deviceName(for deviceID: UInt32) -> String? {
        var address = propertyAddress(
            selector: kAudioObjectPropertyName,
            scope: kAudioObjectPropertyScopeGlobal
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeUnretainedValue() as String
    }

    private func scalarValue(for deviceID: UInt32, address: AudioObjectPropertyAddress) -> Float? {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              value.isFinite else {
            return nil
        }
        return min(max(value, 0), 1)
    }

    private func muteValue(for deviceID: UInt32, address: AudioObjectPropertyAddress) -> Bool? {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    private func isPropertySettable(_ deviceID: UInt32, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
}
