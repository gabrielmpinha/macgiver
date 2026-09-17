import AppKit
import Combine
import CoreAudio
import Foundation

struct AudioApplicationInfo: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleID: String?
    let isAudioActive: Bool
}

struct AudioApplication: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let bundleID: String?
    var volume: Float
    var isMuted: Bool
    let isAudioActive: Bool

    var volumePercent: Int {
        Int((volume * 100).rounded())
    }
}

@MainActor
protocol AudioApplicationProviding {
    func applications() -> [AudioApplicationInfo]
}

@MainActor
protocol AudioProcessMixingProviding {
    var isRunning: Bool { get }
    var message: String? { get }

    func start() throws
    func stop()
    func updateApplications(_ applications: [AudioApplication])
    func setVolume(_ volume: Float, for applicationID: pid_t)
    func setMuted(_ muted: Bool, for applicationID: pid_t)
}

@MainActor
final class AudioMixer: ObservableObject {
    @Published private(set) var applications: [AudioApplication] = []
    @Published private(set) var message: String?

    private let applicationProvider: any AudioApplicationProviding
    private let engine: any AudioProcessMixingProviding

    init(
        applicationProvider: any AudioApplicationProviding = SystemAudioApplicationProvider(),
        engine: any AudioProcessMixingProviding = CoreAudioProcessMixer(),
        startsAutomatically: Bool = true
    ) {
        self.applicationProvider = applicationProvider
        self.engine = engine

        if startsAutomatically {
            startEngine()
        }
        refresh()
    }

    var activeApplicationCount: Int {
        applications.filter(\.isAudioActive).count
    }

    var applicationSummary: String {
        applications.isEmpty ? String(localized: "No audio applications") : String(localized: "Adjust each app independently")
    }

    func refresh() {
        if !engine.isRunning {
            startEngine()
        }

        let discovered = applicationProvider.applications()
        let previous = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        applications = discovered
            .map { info in
                let existing = previous[info.id]
                return AudioApplication(
                    id: info.id,
                    name: info.name,
                    bundleID: info.bundleID,
                    volume: existing?.volume ?? 1,
                    isMuted: existing?.isMuted ?? false,
                    isAudioActive: info.isAudioActive
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        engine.updateApplications(applications)

        if let engineMessage = engine.message {
            message = engineMessage
        } else if applications.isEmpty {
            message = String(localized: "No audio applications found.")
        } else if message == String(localized: "No audio applications found.") {
            message = nil
        }
    }

    func setVolume(_ volume: Double, for applicationID: pid_t) {
        guard volume.isFinite else { return }
        let clamped = Float(min(max(volume, 0), 1))
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        applications[index].volume = clamped
        engine.setVolume(clamped, for: applicationID)
    }

    func toggleMute(for applicationID: pid_t) {
        guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
        let muted = !applications[index].isMuted
        applications[index].isMuted = muted
        engine.setMuted(muted, for: applicationID)
    }

    private func startEngine() {
        do {
            try engine.start()
            if message == String(localized: "No audio output is available.") {
                message = nil
            }
        } catch {
            message = String(localized: "No audio output is available.")
        }
    }
}

@MainActor
final class SystemAudioApplicationProvider: AudioApplicationProviding {
    private let workspace: NSWorkspace
    private let excludedBundleID: String

    init(
        workspace: NSWorkspace = .shared,
        excludedBundleID: String = Bundle.main.bundleIdentifier ?? "com.macgiver.app"
    ) {
        self.workspace = workspace
        self.excludedBundleID = excludedBundleID
    }

    func applications() -> [AudioApplicationInfo] {
        let processes = CoreAudioProcessInspector.processes()

        return workspace.runningApplications.compactMap { application in
            guard application.activationPolicy == .regular,
                  application.processIdentifier > 0,
                  application.bundleIdentifier != excludedBundleID else {
                return nil
            }

            let isAudioActive = processes.contains { process in
                process.isRunningOutput && belongs(process, to: application)
            }

            return AudioApplicationInfo(
                id: application.processIdentifier,
                name: application.localizedName
                    ?? application.bundleIdentifier
                    ?? String(localized: "Unknown application"),
                bundleID: application.bundleIdentifier,
                isAudioActive: isAudioActive
            )
        }
    }

    private func belongs(_ process: CoreAudioProcessInfo, to application: NSRunningApplication) -> Bool {
        if process.pid == application.processIdentifier {
            return true
        }
        guard let processBundleID = process.bundleID,
              let applicationBundleID = application.bundleIdentifier else {
            return false
        }
        return processBundleID == applicationBundleID
            || processBundleID.hasPrefix(applicationBundleID + ".")
    }
}

@MainActor
final class CoreAudioProcessMixer: AudioProcessMixingProviding {
    private static let maxTaps = 96
    private static let aggregateUID = "com.macgiver.app-mixer.aggregate"

    // These buffers are the only state accessed by the realtime IO callback.
    // Main-thread mutations are single Float/Int32 writes and do not allocate.
    private let gains = UnsafeMutablePointer<Float>.allocate(capacity: 96)
    private let tapCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private let inputOffset = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    private var trackedApplications: [AudioApplication] = []
    private var gainsByApplication: [pid_t: Float] = [:]
    private var mutedApplications: Set<pid_t> = []
    private var slotOwners: [pid_t] = []
    private var tappedProcessObjects: [AudioObjectID] = []
    private var tapIDs: [AudioObjectID] = []
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var outputDeviceID = AudioObjectID(kAudioObjectUnknown)

    private(set) var isRunning = false
    private(set) var message: String?

    init() {
        gains.initialize(repeating: 1, count: Self.maxTaps)
        tapCount.pointee = 0
        inputOffset.pointee = 0
    }

    isolated deinit {
        teardownAggregate()
        gains.deallocate()
        tapCount.deallocate()
        inputOffset.deallocate()
    }

    func start() throws {
        guard !isRunning else { return }
        let output = CoreAudioProcessInspector.defaultOutputDevice()
        guard output != AudioObjectID(kAudioObjectUnknown) else {
            throw EngineError.noOutputDevice
        }
        outputDeviceID = output
        isRunning = true
        message = nil
    }

    func stop() {
        isRunning = false
        teardownAggregate()
        outputDeviceID = AudioObjectID(kAudioObjectUnknown)
    }

    func updateApplications(_ applications: [AudioApplication]) {
        trackedApplications = applications
        for application in applications {
            gainsByApplication[application.id] = application.volume
            if application.isMuted {
                mutedApplications.insert(application.id)
            } else {
                mutedApplications.remove(application.id)
            }
        }

        guard isRunning else { return }
        refreshOutputAndTargets()
    }

    func setVolume(_ volume: Float, for applicationID: pid_t) {
        gainsByApplication[applicationID] = min(max(volume, 0), 1)
        updateRealtimeGain(for: applicationID)
    }

    func setMuted(_ muted: Bool, for applicationID: pid_t) {
        if muted {
            mutedApplications.insert(applicationID)
        } else {
            mutedApplications.remove(applicationID)
        }
        updateRealtimeGain(for: applicationID)
    }

    private func refreshOutputAndTargets() {
        let currentOutput = CoreAudioProcessInspector.defaultOutputDevice()
        guard currentOutput != AudioObjectID(kAudioObjectUnknown) else {
            message = String(localized: "No audio output is available.")
            return
        }

        let outputChanged = outputDeviceID != currentOutput
        if outputChanged {
            outputDeviceID = currentOutput
        }

        let targets = computeTapTargets()
        let targetIDs = targets.map(\.processObject)
        guard outputChanged || Set(targetIDs) != Set(tappedProcessObjects) else {
            updateAllRealtimeGains()
            return
        }

        rebuildAggregate(targets: targets)
    }

    private func computeTapTargets() -> [TapTarget] {
        let processes = CoreAudioProcessInspector.processes()
        return processes.compactMap { process in
            guard process.isRunningOutput,
                  let owner = ownerApplicationID(for: process) else {
                return nil
            }
            return TapTarget(processObject: process.objectID, owner: owner)
        }
    }

    private func ownerApplicationID(for process: CoreAudioProcessInfo) -> pid_t? {
        if let application = trackedApplications.first(where: { $0.id == process.pid }) {
            return application.id
        }
        guard let processBundleID = process.bundleID, !processBundleID.isEmpty else {
            return nil
        }
        if let application = trackedApplications.first(where: { $0.bundleID == processBundleID }) {
            return application.id
        }
        return trackedApplications
            .filter { application in
                guard let bundleID = application.bundleID else { return false }
                return processBundleID.hasPrefix(bundleID + ".")
            }
            .max(by: { ($0.bundleID?.count ?? 0) < ($1.bundleID?.count ?? 0) })?
            .id
    }

    private func rebuildAggregate(targets: [TapTarget]) {
        teardownAggregate()
        tappedProcessObjects = []
        guard isRunning,
              outputDeviceID != AudioObjectID(kAudioObjectUnknown),
              let outputUID = CoreAudioProcessInspector.deviceUID(outputDeviceID) else {
            return
        }

        var newTapIDs: [AudioObjectID] = []
        var tapUIDs: [String] = []
        var owners: [pid_t] = []
        var tappedObjects: [AudioObjectID] = []

        for target in targets.prefix(Self.maxTaps) {
            let description = CATapDescription()
            description.name = "MacGiver-\(target.owner)-\(target.processObject)"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            description.isMono = false
            description.isMixdown = true
            description.isExclusive = false
            description.setValue([NSNumber(value: target.processObject)], forKey: "processes")

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            guard status == noErr,
                  tapID != AudioObjectID(kAudioObjectUnknown),
                  let tapUID = CoreAudioProcessInspector.tapUID(tapID) else {
                message = String(localized: "Allow System Audio Recording for MacGiver, then refresh the mixer.")
                NSLog("[MacGiver] Could not create audio process tap: %d", status)
                continue
            }

            newTapIDs.append(tapID)
            tapUIDs.append(tapUID)
            owners.append(target.owner)
            tappedObjects.append(target.processObject)
        }

        tapIDs = newTapIDs
        slotOwners = owners
        tapCount.pointee = Int32(newTapIDs.count)
        updateAllRealtimeGains()

        guard !newTapIDs.isEmpty else {
            tappedProcessObjects = tappedObjects
            message = nil
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacGiver App Mixer",
            kAudioAggregateDeviceUIDKey: Self.aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: tapUIDs.map {
                [kAudioSubTapUIDKey: $0, kAudioSubTapDriftCompensationKey: true]
            }
        ]

        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary,
            &newAggregateID
        )
        guard aggregateStatus == noErr,
              newAggregateID != AudioObjectID(kAudioObjectUnknown) else {
            message = String(localized: "Could not start the app volume mixer. Check System Audio Recording permission.")
            NSLog("[MacGiver] Could not create app mixer aggregate: %d", aggregateStatus)
            teardownTaps()
            return
        }
        aggregateID = newAggregateID

        let inputAddress = CoreAudioProcessInspector.propertyAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeInput
        )
        let inputBufferCount = CoreAudioProcessInspector.bufferCount(aggregateID, address: inputAddress)
        inputOffset.pointee = Int32(max(0, inputBufferCount - newTapIDs.count))

        var processID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &processID,
            aggregateID,
            nil,
            makeIOBlock()
        )
        guard createStatus == noErr, let processID else {
            message = String(localized: "Could not start the app volume mixer. Check System Audio Recording permission.")
            NSLog("[MacGiver] Could not create app mixer IO proc: %d", createStatus)
            teardownAggregate()
            return
        }
        ioProcID = processID

        let startStatus = AudioDeviceStart(aggregateID, processID)
        guard startStatus == noErr else {
            message = String(localized: "Could not start the app volume mixer. Check System Audio Recording permission.")
            NSLog("[MacGiver] Could not start app mixer IO: %d", startStatus)
            teardownAggregate()
            return
        }

        tappedProcessObjects = tappedObjects
        message = nil
    }

    private func teardownAggregate() {
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let processID = ioProcID {
                AudioDeviceStop(aggregateID, processID)
                AudioDeviceDestroyIOProcID(aggregateID, processID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        teardownTaps()
        tapCount.pointee = 0
        slotOwners = []
    }

    private func teardownTaps() {
        for tapID in tapIDs {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapIDs = []
    }

    private func updateAllRealtimeGains() {
        for applicationID in Set(slotOwners) {
            updateRealtimeGain(for: applicationID)
        }
    }

    private func updateRealtimeGain(for applicationID: pid_t) {
        let gain = mutedApplications.contains(applicationID)
            ? 0
            : gainsByApplication[applicationID, default: 1]
        for (slot, owner) in slotOwners.enumerated() where owner == applicationID {
            guard slot < Self.maxTaps else { continue }
            gains[slot] = gain
        }
    }

    private func makeIOBlock() -> AudioDeviceIOBlock {
        let gains = self.gains
        let tapCount = self.tapCount
        let inputOffset = self.inputOffset

        return { _, inputData, _, outputData, _ in
            let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)
            guard !outputBuffers.isEmpty else { return }

            for buffer in outputBuffers {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }

            let inputBuffers = UnsafeMutableAudioBufferListPointer(
                UnsafeMutablePointer(mutating: inputData)
            )
            let count = Int(tapCount.pointee)
            let offset = Int(inputOffset.pointee)
            guard count > 0, let outputData = outputBuffers[0].mData else { return }

            let outputSamples = outputData.assumingMemoryBound(to: Float.self)
            let outputSampleCount = Int(outputBuffers[0].mDataByteSize) / MemoryLayout<Float>.size

            for tapIndex in 0..<count {
                let inputIndex = offset + tapIndex
                guard inputIndex < inputBuffers.count,
                      let inputData = inputBuffers[inputIndex].mData else {
                    continue
                }

                let gain = gains[tapIndex]
                guard gain != 0 else { continue }
                let inputSamples = inputData.assumingMemoryBound(to: Float.self)
                let sampleCount = min(
                    outputSampleCount,
                    Int(inputBuffers[inputIndex].mDataByteSize) / MemoryLayout<Float>.size
                )

                if gain == 1 {
                    for sample in 0..<sampleCount {
                        outputSamples[sample] += inputSamples[sample]
                    }
                } else {
                    for sample in 0..<sampleCount {
                        outputSamples[sample] += inputSamples[sample] * gain
                    }
                }
            }
        }
    }

    private struct TapTarget {
        let processObject: AudioObjectID
        let owner: pid_t
    }

    private enum EngineError: LocalizedError {
        case noOutputDevice

        var errorDescription: String? {
            String(localized: "No audio output is available.")
        }
    }
}

private struct CoreAudioProcessInfo {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    let isRunningOutput: Bool
}

private enum CoreAudioProcessInspector {
    static func processes() -> [CoreAudioProcessInfo] {
        propertyArray(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(selector: kAudioHardwarePropertyProcessObjectList),
            type: AudioObjectID.self
        ).compactMap { objectID in
            let pid = scalar(
                objectID: objectID,
                address: propertyAddress(selector: kAudioProcessPropertyPID),
                fallback: pid_t(-1)
            )
            guard pid > 0 else { return nil }
            return CoreAudioProcessInfo(
                objectID: objectID,
                pid: pid,
                bundleID: string(objectID: objectID, address: propertyAddress(selector: kAudioProcessPropertyBundleID)),
                isRunningOutput: scalar(
                    objectID: objectID,
                    address: propertyAddress(selector: kAudioProcessPropertyIsRunningOutput),
                    fallback: UInt32(0)
                ) != 0
            )
        }
    }

    static func defaultOutputDevice() -> AudioObjectID {
        scalar(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: propertyAddress(selector: kAudioHardwarePropertyDefaultOutputDevice),
            fallback: AudioObjectID(kAudioObjectUnknown)
        )
    }

    static func deviceUID(_ objectID: AudioObjectID) -> String? {
        string(
            objectID: objectID,
            address: propertyAddress(selector: kAudioDevicePropertyDeviceUID)
        )
    }

    static func tapUID(_ objectID: AudioObjectID) -> String? {
        string(objectID: objectID, address: propertyAddress(selector: kAudioTapPropertyUID))
    }

    static func propertyAddress(
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func bufferCount(_ objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> Int {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return 0
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        return Int(raw.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers)
    }

    private static func scalar<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        fallback: T
    ) -> T {
        var address = address
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value : fallback
    }

    private static func propertyArray<T>(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        type: T.Type
    ) -> [T] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<T>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw) == noErr else {
            return []
        }
        return Array(
            UnsafeBufferPointer(
                start: raw.bindMemory(to: T.self, capacity: count),
                count: count
            )
        )
    }

    private static func string(objectID: AudioObjectID, address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeUnretainedValue() as String
    }
}
