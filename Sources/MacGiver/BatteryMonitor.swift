import AppKit
import Combine
import Foundation

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var reading = BatteryReading()
    @Published private(set) var history = BatteryHistory()
    @Published private(set) var deviceScan: DeviceScan?
    @Published private(set) var refreshingDevices = false
    private let deviceReader = DeviceBatteryReader()
    private var samplingTask: Task<Void, Never>?
    private var deviceTask: Task<Void, Never>?
    private var wakeObserver: AnyCancellable?

    init(startAutomatically: Bool = true) {
        guard startAutomatically else { return }
        refreshBattery()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                self?.refreshBattery()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.history.startNewSegment()
                    self?.refreshBattery()
                }
            }
    }

    func refreshBattery() {
        reading = BatteryHardware.read()
        history.append(reading)
    }

    func refreshDevices() {
        guard !refreshingDevices else { return }
        refreshingDevices = true
        let reader = deviceReader
        deviceTask = Task { [weak self] in
            let scan = await reader.read()
            guard !Task.isCancelled else { return }
            self?.deviceScan = scan
            self?.refreshingDevices = false
        }
    }

    deinit {
        samplingTask?.cancel()
        deviceTask?.cancel()
    }
}
