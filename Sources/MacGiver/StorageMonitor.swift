import AppKit
import Combine
import Foundation

@MainActor
final class StorageMonitor: ObservableObject {
    @Published private(set) var reading = StorageReading()
    @Published private(set) var history = StorageHistory()

    private var samplingTask: Task<Void, Never>?
    private var wakeObserver: AnyCancellable?
    private let readStorage: () -> StorageReading

    init(startAutomatically: Bool = true, readStorage: @escaping () -> StorageReading = StorageHardware.read) {
        self.readStorage = readStorage
        guard startAutomatically else { return }
        refreshStorage()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                self?.refreshStorage()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.history.startNewSegment()
                    self?.refreshStorage()
                }
            }
    }

    func refreshStorage() {
        reading = readStorage()
        history.append(reading)
    }

    deinit {
        samplingTask?.cancel()
    }
}
