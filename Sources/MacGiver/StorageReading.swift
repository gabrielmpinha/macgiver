import Foundation

struct StorageReading: Sendable {
    enum Availability: Sendable, Equatable {
        case available
        case unavailable
    }

    var date = Date()
    var availability: Availability = .unavailable
    var totalBytes: Int64?
    var freeBytes: Int64?

    var usedBytes: Int64? {
        guard let totalBytes, let freeBytes, totalBytes >= freeBytes else { return nil }
        return totalBytes - freeBytes
    }

    var usedPercent: Double? {
        guard let totalBytes, totalBytes > 0, let usedBytes else { return nil }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    var usedPercentText: String { usedPercent.map { BatteryReading.formatPercent($0) } ?? "—" }
    var usedText: String { usedBytes.map { Self.formatBytes($0) } ?? "—" }
    var freeText: String { freeBytes.map { Self.formatBytes($0) } ?? "—" }
    var totalText: String { totalBytes.map { Self.formatBytes($0) } ?? "—" }

    static func decode(totalBytes: Int64?, freeBytes: Int64?, date: Date = Date()) -> Self {
        guard let totalBytes, totalBytes > 0,
              let freeBytes, freeBytes >= 0, freeBytes <= totalBytes else {
            return Self(date: date)
        }

        return Self(date: date, availability: .available, totalBytes: totalBytes, freeBytes: freeBytes)
    }

    static func formatBytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }
}

enum StorageHardware {
    static func read() -> StorageReading {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        let totalBytes = (attributes?[.systemSize] as? NSNumber)?.int64Value
        let freeBytes = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
        return .decode(totalBytes: totalBytes, freeBytes: freeBytes)
    }
}

struct StorageSample: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let usedPercent: Double?
    var startsSegment = false
}

struct StorageHistory {
    private(set) var samples: [StorageSample] = []
    private var breakBeforeNextSample = false
    static let retention: TimeInterval = 6 * 60 * 60

    mutating func startNewSegment() { breakBeforeNextSample = true }

    mutating func append(_ reading: StorageReading) {
        if let last = samples.last, reading.date <= last.date { samples.removeAll() }
        samples.append(.init(date: reading.date, usedPercent: reading.usedPercent,
                             startsSegment: breakBeforeNextSample))
        breakBeforeNextSample = false
        samples.removeAll { $0.date < reading.date.addingTimeInterval(-Self.retention) }
        if samples.count > 4_321 { samples.removeFirst(samples.count - 4_321) }
    }

    struct Point: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        let segment: Int
    }

    func points(since: Date) -> [Point] {
        var segment = 0
        var previous: StorageSample?
        return samples.filter { $0.date >= since }.compactMap { sample in
            defer { previous = sample }
            if sample.startsSegment { segment += 1 }
            if let previous, sample.date.timeIntervalSince(previous.date) > 20 { segment += 1 }
            guard let value = sample.usedPercent else { segment += 1; return nil }
            return Point(date: sample.date, value: value, segment: segment)
        }
    }
}
