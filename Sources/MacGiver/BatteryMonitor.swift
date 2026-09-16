import AppKit
import Combine
import Foundation

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var reading = BatteryReading()
    @Published private(set) var history = BatteryHistory()
    private var samplingTask: Task<Void, Never>?
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

    deinit {
        samplingTask?.cancel()
    }
}
