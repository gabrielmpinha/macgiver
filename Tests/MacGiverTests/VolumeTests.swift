import XCTest
@testable import MacGiver

@MainActor
final class VolumeMixerTests: XCTestCase {
    func testApplicationsAreDiscoveredAndSorted() {
        let provider = AudioApplicationProviderStub(applications: [
            .init(id: 2, name: "Safari", bundleID: "com.apple.Safari", isAudioActive: true),
            .init(id: 1, name: "Music", bundleID: "com.apple.Music", isAudioActive: false)
        ])
        let mixer = AudioMixer(
            applicationProvider: provider,
            engine: AudioProcessMixerStub(),
            startsAutomatically: false
        )

        XCTAssertEqual(mixer.applications.map(\.name), ["Music", "Safari"])
        XCTAssertEqual(mixer.applications.first?.volumePercent, 100)
        XCTAssertEqual(mixer.activeApplicationCount, 1)
        XCTAssertEqual(mixer.applicationSummary, String(localized: "Adjust each app independently"))
    }

    func testVolumeIsClampedAndForwardedToTheApplicationEngine() {
        let engine = AudioProcessMixerStub()
        let mixer = AudioMixer(
            applicationProvider: AudioApplicationProviderStub(applications: [
                .init(id: 1, name: "Safari", bundleID: "com.apple.Safari", isAudioActive: true)
            ]),
            engine: engine,
            startsAutomatically: false
        )

        mixer.setVolume(1.5, for: 1)

        XCTAssertEqual(engine.volumeWrites.count, 1)
        XCTAssertEqual(engine.volumeWrites.first?.0, 1)
        XCTAssertEqual(engine.volumeWrites.first?.1 ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(mixer.applications.first?.volume ?? 0, 1, accuracy: 0.0001)
    }

    func testMuteToggleIsForwardedAndReflectedLocally() {
        let engine = AudioProcessMixerStub()
        let mixer = AudioMixer(
            applicationProvider: AudioApplicationProviderStub(applications: [
                .init(id: 1, name: "Music", bundleID: "com.apple.Music", isAudioActive: true)
            ]),
            engine: engine,
            startsAutomatically: false
        )

        mixer.toggleMute(for: 1)

        XCTAssertEqual(engine.muteWrites.count, 1)
        XCTAssertEqual(engine.muteWrites.first?.0, 1)
        XCTAssertEqual(engine.muteWrites.first?.1, true)
        XCTAssertTrue(mixer.applications.first?.isMuted == true)
    }

    func testNoApplicationsShowsActionableEmptyState() {
        let mixer = AudioMixer(
            applicationProvider: AudioApplicationProviderStub(applications: []),
            engine: AudioProcessMixerStub(),
            startsAutomatically: false
        )

        XCTAssertTrue(mixer.applications.isEmpty)
        XCTAssertEqual(mixer.message, String(localized: "No audio applications found."))
        XCTAssertEqual(mixer.applicationSummary, String(localized: "No audio applications"))
    }

    func testExistingVolumeIsPreservedAcrossRefresh() {
        let provider = AudioApplicationProviderStub(applications: [
            .init(id: 1, name: "Safari", bundleID: "com.apple.Safari", isAudioActive: true)
        ])
        let mixer = AudioMixer(
            applicationProvider: provider,
            engine: AudioProcessMixerStub(),
            startsAutomatically: false
        )

        mixer.setVolume(0.35, for: 1)
        provider.items = [
            .init(id: 1, name: "Safari", bundleID: "com.apple.Safari", isAudioActive: false)
        ]
        mixer.refresh()

        XCTAssertEqual(mixer.applications.first?.volume ?? 0, 0.35, accuracy: 0.0001)
        XCTAssertFalse(mixer.applications.first?.isAudioActive == true)
    }
}

@MainActor
private final class AudioApplicationProviderStub: AudioApplicationProviding {
    var items: [AudioApplicationInfo]

    init(applications: [AudioApplicationInfo]) {
        self.items = applications
    }

    func applications() -> [AudioApplicationInfo] {
        items
    }
}

@MainActor
private final class AudioProcessMixerStub: AudioProcessMixingProviding {
    var isRunning = false
    var message: String?
    var volumeWrites: [(pid_t, Float)] = []
    var muteWrites: [(pid_t, Bool)] = []

    func start() throws {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func updateApplications(_ applications: [AudioApplication]) {}

    func setVolume(_ volume: Float, for applicationID: pid_t) {
        volumeWrites.append((applicationID, volume))
    }

    func setMuted(_ muted: Bool, for applicationID: pid_t) {
        muteWrites.append((applicationID, muted))
    }
}
