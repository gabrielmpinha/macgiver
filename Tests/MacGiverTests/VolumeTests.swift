import XCTest
@testable import MacGiver

@MainActor
final class VolumeMixerTests: XCTestCase {
    func testDefaultOutputIsSelectedAndFormatted() {
        let stub = AudioMixerStub(devices: [
            .init(id: 1, name: "MacBook Pro Speakers", volume: 0.42, isMuted: false,
                  isDefault: true, canSetVolume: true, canSetMute: true),
            .init(id: 2, name: "Headphones", volume: 0.80, isMuted: false,
                  isDefault: false, canSetVolume: true, canSetMute: true)
        ])
        let mixer = AudioMixer(hardware: stub)

        XCTAssertEqual(mixer.defaultDeviceName, "MacBook Pro Speakers")
        XCTAssertEqual(mixer.defaultVolume ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(mixer.defaultDevice?.volumePercent, 42)
        XCTAssertFalse(mixer.defaultIsMuted)
    }

    func testVolumeIsClampedAndRefreshedAfterWrite() {
        let stub = AudioMixerStub(devices: [
            .init(id: 1, name: "Speakers", volume: 0.42, isMuted: false,
                  isDefault: true, canSetVolume: true, canSetMute: true)
        ])
        let mixer = AudioMixer(hardware: stub)

        mixer.setDefaultVolume(1.5)

        XCTAssertEqual(stub.volumeWrites.count, 1)
        XCTAssertEqual(stub.volumeWrites.first?.0, 1)
        XCTAssertEqual(stub.volumeWrites.first?.1 ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(mixer.defaultVolume ?? 0, 1, accuracy: 0.0001)
        XCTAssertNil(mixer.message)
    }

    func testMuteToggleWritesAndRefreshes() {
        let stub = AudioMixerStub(devices: [
            .init(id: 1, name: "Speakers", volume: 0.42, isMuted: false,
                  isDefault: true, canSetVolume: true, canSetMute: true)
        ])
        let mixer = AudioMixer(hardware: stub)

        mixer.toggleDefaultMute()

        XCTAssertEqual(stub.muteWrites.count, 1)
        XCTAssertEqual(stub.muteWrites.first?.0, 1)
        XCTAssertEqual(stub.muteWrites.first?.1, true)
        XCTAssertTrue(mixer.defaultIsMuted)
    }

    func testUnavailableOutputDoesNotPretendToBeZero() {
        let mixer = AudioMixer(hardware: AudioMixerStub(devices: []))

        XCTAssertNil(mixer.defaultVolume)
        XCTAssertEqual(mixer.defaultDeviceName, String(localized: "No output device"))
        XCTAssertEqual(mixer.message, String(localized: "No output devices found."))
    }

    func testFailedWriteKeepsActionableMessage() {
        let stub = AudioMixerStub(devices: [
            .init(id: 1, name: "Speakers", volume: 0.42, isMuted: false,
                  isDefault: true, canSetVolume: false, canSetMute: true)
        ])
        let mixer = AudioMixer(hardware: stub)

        mixer.setDefaultVolume(0.2)

        XCTAssertEqual(mixer.defaultVolume ?? 0, 0.42, accuracy: 0.0001)
        XCTAssertEqual(mixer.message, String(localized: "Could not change output volume. Try again."))
    }
}

@MainActor
private final class AudioMixerStub: AudioHardwareProviding {
    var devices: [AudioOutputDevice]
    var volumeWrites: [(UInt32, Float)] = []
    var muteWrites: [(UInt32, Bool)] = []

    init(devices: [AudioOutputDevice]) {
        self.devices = devices
    }

    func outputDevices() -> [AudioOutputDevice] {
        devices
    }

    func setVolume(_ volume: Float, for deviceID: UInt32) -> Bool {
        volumeWrites.append((deviceID, volume))
        guard let index = devices.firstIndex(where: { $0.id == deviceID }), devices[index].canSetVolume else {
            return false
        }
        let device = devices[index]
        devices[index] = AudioOutputDevice(id: device.id, name: device.name, volume: volume,
                                           isMuted: device.isMuted, isDefault: device.isDefault,
                                           canSetVolume: device.canSetVolume, canSetMute: device.canSetMute)
        return true
    }

    func setMuted(_ muted: Bool, for deviceID: UInt32) -> Bool {
        muteWrites.append((deviceID, muted))
        guard let index = devices.firstIndex(where: { $0.id == deviceID }), devices[index].canSetMute else {
            return false
        }
        let device = devices[index]
        devices[index] = AudioOutputDevice(id: device.id, name: device.name, volume: device.volume,
                                           isMuted: muted, isDefault: device.isDefault,
                                           canSetVolume: device.canSetVolume, canSetMute: device.canSetMute)
        return true
    }
}
