import AppKit
import Combine
import Foundation

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var reading = BatteryReading()
    @Published private(set) var history = BatteryHistory()
    private var samplingTask: Task<Void, Never>?
    private var wakeObserver: AnyCancellable?
    private let readBattery: () -> BatteryReading

    init(startAutomatically: Bool = true, readBattery: @escaping () -> BatteryReading = BatteryHardware.read) {
        self.readBattery = readBattery
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
        reading = readBattery()
        history.append(reading)
    }

    deinit {
        samplingTask?.cancel()
    }
}
