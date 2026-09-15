import Foundation
import IOKit
import IOKit.ps

struct BatteryReading: Sendable {
    enum Availability: Sendable { case available, noBattery, unavailable }
    enum State: String, Sendable {
        case discharging = "On battery"
        case charging = "Charging"
        case charged = "Fully charged"
        case pluggedIn = "Plugged in · not charging"
        case unknown = "Status unavailable"
    }

    var date = Date()
    var availability: Availability = .unavailable
    var percent: Double?
    var state: State = .unknown
    var externalPower: Bool?
    /// Positive = draining the battery, negative = charging it. Not total system power.
    var watts: Double?
    var minutesRemaining: Int?
    var healthPercent: Double?
    var condition: String?
    var cycles: Int?
    var designCapacity: Double?
    var fullChargeCapacity: Double?

    var percentText: String { percent.map { "\(Int($0.rounded()))%" } ?? "—" }
    var powerText: String { watts.map { String(format: "%.1f W", abs($0)) } ?? "—" }
    var flowText: String {
        guard let watts else { return "Reading unavailable" }
        if watts > 0.05 { return "Leaving the battery" }
        if watts < -0.05 { return "Entering the battery" }
        return "No battery power flow"
    }
    var timeTitle: String { state == .charging ? "Until full" : "Time remaining" }
    var timeText: String {
        if state == .charged { return "Fully charged" }
        if state == .pluggedIn { return "On external power" }
        guard let minutesRemaining else { return "Estimating…" }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func decode(source: [String: Any]?, registry: [String: Any], date: Date = Date(),
                       sourcesAvailable: Bool = true) -> Self {
        var reading = Self(date: date)
        let installed = registry["BatteryInstalled"] as? Bool
        guard source != nil || installed == true else {
            reading.availability = sourcesAvailable && registry.isEmpty ? .noBattery : .unavailable
            if installed == false { reading.availability = .noBattery }
            return reading
        }
        reading.availability = .available
        let source = source ?? [:]
        let data = registry["BatteryData"] as? [String: Any] ?? [:]
        reading.percent = percentage(current: number(source[kIOPSCurrentCapacityKey]),
                                     maximum: number(source[kIOPSMaxCapacityKey]))
            ?? percentage(current: number(registry["CurrentCapacity"]),
                          maximum: number(registry["MaxCapacity"]))
        let sourceState = source[kIOPSPowerSourceStateKey] as? String
        reading.externalPower = sourceState == kIOPSACPowerValue ? true
            : sourceState == kIOPSBatteryPowerValue ? false : registry["ExternalConnected"] as? Bool
        let charging = source[kIOPSIsChargingKey] as? Bool ?? registry["IsCharging"] as? Bool
        let full = source[kIOPSIsChargedKey] as? Bool ?? registry["FullyCharged"] as? Bool
        if charging == true {
            reading.state = .charging
        } else if reading.externalPower == true {
            reading.state = full == true ? .charged : .pluggedIn
        } else if reading.externalPower == false {
            reading.state = .discharging
        }
        if reading.state == .charging {
            reading.minutesRemaining = minutes(source[kIOPSTimeToFullChargeKey])
        } else if reading.state == .discharging {
            reading.minutesRemaining = minutes(source[kIOPSTimeToEmptyKey])
        }

        // Apple publishes signed milliamps, sometimes wrapped in an unsigned NSNumber.
        // Decode only these current properties as signed; capacities remain unsigned.
        if let current = amperage(registry["InstantAmperage"]) ?? amperage(registry["Amperage"]),
           let voltage = positive(registry["Voltage"]), voltage < 100_000 {
            reading.watts = -current * voltage / 1_000_000
        }
        let design = positive(registry["DesignCapacity"]) ?? positive(data["DesignCapacity"])
        let nominal = positive(registry["NominalChargeCapacity"]) ?? positive(data["NominalChargeCapacity"])
        let rawFull = positive(registry["AppleRawMaxCapacity"]) ?? positive(data["FullChargeCapacity"])
        // Legacy Intel MaxCapacity is mAh; Apple Silicon's normalized 100 is not.
        let legacyFull = positive(registry["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        reading.designCapacity = design
        reading.fullChargeCapacity = rawFull ?? legacyFull
        if let design, let capacity = nominal ?? rawFull ?? legacyFull {
            let ratio = capacity / design * 100
            if (1...150).contains(ratio) { reading.healthPercent = min(100, ratio) }
        }
        reading.cycles = number(registry["CycleCount"] ?? data["CycleCount"])
            .flatMap { (0...100_000).contains($0) ? Int($0) : nil }
        let condition = source[kIOPSBatteryHealthConditionKey] as? String
        let health = source[kIOPSBatteryHealthKey] as? String
        reading.condition = condition ?? (health == kIOPSGoodValue ? "Normal" : health)
        return reading
    }

    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func positive(_ value: Any?) -> Double? { number(value).flatMap { $0 > 0 ? $0 : nil } }
    static func percentage(current: Double?, maximum: Double?) -> Double? {
        guard let current, let maximum, current.isFinite, maximum.isFinite,
              maximum > 0, current >= 0, current <= maximum else { return nil }
        return current / maximum * 100
    }
    static func minutes(_ value: Any?) -> Int? {
        guard let value = number(value), value > 0, value < 65_535 else { return nil }
        return Int(value)
    }
    static func amperage(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        var signed = value.int64Value
        // Some older drivers use a 32-bit unsigned container for negative current.
        if signed > Int64(Int32.max), signed <= Int64(UInt32.max) {
            signed = Int64(Int32(bitPattern: UInt32(signed)))
        }
        guard abs(Double(signed)) <= 100_000 else { return nil }
        return Double(signed)
    }
}

enum BatteryHardware {
    static func read() -> BatteryReading {
        let registry = properties(className: "AppleSmartBattery").first ?? [:]
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .decode(source: nil, registry: registry, sourcesAvailable: false)
        }
        let internalSource = sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }.first { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }
        return .decode(source: internalSource, registry: registry)
    }

    static func properties(className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator)
                == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let values = properties?.takeRetainedValue() as? [String: Any] {
                result.append(values)
            }
        }
        return result
    }
}

struct BatterySample: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let percent: Double?
    let watts: Double?
    var startsSegment = false
}

struct BatteryHistory {
    private(set) var samples: [BatterySample] = []
    private var breakBeforeNextSample = false
    static let retention: TimeInterval = 6 * 60 * 60

    mutating func startNewSegment() { breakBeforeNextSample = true }

    mutating func append(_ reading: BatteryReading) {
        if let last = samples.last, reading.date <= last.date { samples.removeAll() }
        samples.append(.init(date: reading.date, percent: reading.percent, watts: reading.watts,
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

    func points(since: Date, power: Bool) -> [Point] {
        var segment = 0
        var previous: BatterySample?
        return samples.filter { $0.date >= since }.compactMap { sample in
            defer { previous = sample }
            let value = power ? sample.watts : sample.percent
            if sample.startsSegment { segment += 1 }
            if let previous, sample.date.timeIntervalSince(previous.date) > 20 { segment += 1 }
            guard let value else { segment += 1; return nil }
            return Point(date: sample.date, value: value, segment: segment)
        }
    }
}
