import XCTest
import IOKit.ps
@testable import MacGiver

final class BatteryReadingTests: XCTestCase {
    private let source: [String: Any] = [
        kIOPSCurrentCapacityKey: 23, kIOPSMaxCapacityKey: 100,
        kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        kIOPSIsChargingKey: false, kIOPSTimeToEmptyKey: 131,
        kIOPSBatteryHealthKey: kIOPSGoodValue
    ]

    func testAppleSiliconUsesRawCapacitiesAndSignedCurrent() {
        let reading = BatteryReading.decode(source: source, registry: [
            "BatteryInstalled": true, "CurrentCapacity": 23, "MaxCapacity": 100,
            "Voltage": 11_197, "InstantAmperage": NSNumber(value: UInt64.max - 618), "CycleCount": 43,
            "BatteryData": ["DesignCapacity": 4_629, "FullChargeCapacity": 4_432, "NominalChargeCapacity": 4_559]
        ])
        XCTAssertEqual(reading.percent, 23)
        XCTAssertEqual(reading.watts ?? 0, 6.930943, accuracy: 0.000001)
        XCTAssertEqual(reading.healthPercent ?? 0, 98.487794, accuracy: 0.00001)
        XCTAssertEqual(reading.cycles, 43)
        XCTAssertEqual(reading.minutesRemaining, 131)
        XCTAssertEqual(reading.timeText, "2h 11m")
        XCTAssertEqual(reading.condition, "Normal")
    }

    func testIntelCapacityAndUnsigned32BitCurrent() {
        let reading = BatteryReading.decode(source: source, registry: [
            "DesignCapacity": 5_000, "MaxCapacity": 4_200, "Amperage": UInt32.max - 999, "Voltage": 12_000
        ])
        XCTAssertEqual(reading.healthPercent, 84)
        XCTAssertEqual(reading.watts, 12)
    }

    func testACConnectedDischargeAndPausedChargeAreIndependent() {
        var source = source
        source[kIOPSPowerSourceStateKey] = kIOPSACPowerValue
        source[kIOPSIsChargedKey] = false
        let reading = BatteryReading.decode(source: source, registry: ["Amperage": -500, "Voltage": 12_000])
        XCTAssertEqual(reading.state, .pluggedIn)
        XCTAssertEqual(reading.externalPower, true)
        XCTAssertEqual(reading.watts, 6)
        XCTAssertNil(reading.minutesRemaining)
        XCTAssertEqual(reading.flowText, "Leaving the battery")
        let unknown = BatteryReading.decode(source: source, registry: [:])
        XCTAssertNil(unknown.watts)
        XCTAssertEqual(unknown.flowText, "Reading unavailable")
    }

    func testChargingAndFullyChargedUseDifferentTimeSemantics() {
        var source = source
        source[kIOPSPowerSourceStateKey] = kIOPSACPowerValue
        source[kIOPSIsChargingKey] = true
        source[kIOPSTimeToFullChargeKey] = 42
        let charging = BatteryReading.decode(source: source, registry: ["Amperage": 1_000, "Voltage": 12_000])
        XCTAssertEqual(charging.watts, -12)
        XCTAssertEqual(charging.state, .charging)
        XCTAssertEqual(charging.minutesRemaining, 42)
        XCTAssertEqual(charging.timeTitle, "Until full")
        source[kIOPSIsChargingKey] = false
        source[kIOPSIsChargedKey] = true
        let full = BatteryReading.decode(source: source, registry: [:])
        XCTAssertEqual(full.state, .charged)
        XCTAssertNil(full.minutesRemaining)
        XCTAssertEqual(full.timeText, "Fully charged")
    }

    func testUnknownValuesDoNotBecomeZeroOrFalseHealth() {
        for sentinel in [-1, 0, 65_535, Int.max] {
            var source = source
            source[kIOPSTimeToEmptyKey] = sentinel
            XCTAssertNil(BatteryReading.decode(source: source, registry: [:]).minutesRemaining)
        }
        let reading = BatteryReading.decode(source: source, registry: ["DesignCapacity": 5_000, "MaxCapacity": 100])
        XCTAssertNil(reading.healthPercent)
        XCTAssertNil(reading.cycles)
        XCTAssertNil(reading.watts)
        XCTAssertNil(BatteryReading.number(true))
        XCTAssertNil(BatteryReading.percentage(current: 101, maximum: 100))
        XCTAssertNil(BatteryReading.percentage(current: 10, maximum: 0))
        XCTAssertNil(BatteryReading.amperage(Double.infinity))
        XCTAssertEqual(BatteryReading.percentage(current: 0, maximum: 100), 0)
        let zero = BatteryReading.decode(source: source, registry: ["CycleCount": 0, "Amperage": 0, "Voltage": 12_000])
        XCTAssertEqual(zero.cycles, 0)
        XCTAssertEqual(zero.watts, 0)
    }

    func testNoBatteryAndFailedReadAreDistinct() {
        XCTAssertEqual(BatteryReading.decode(source: nil, registry: [:]).availability, .noBattery)
        XCTAssertEqual(BatteryReading.decode(source: nil, registry: [:], sourcesAvailable: false).availability, .unavailable)
        let fallback = BatteryReading.decode(source: nil, registry: [
            "BatteryInstalled": true, "CurrentCapacity": 50, "MaxCapacity": 100,
            "ExternalConnected": false
        ], sourcesAvailable: false)
        XCTAssertEqual(fallback.availability, .available)
        XCTAssertEqual(fallback.percent, 50)
    }

    func testHistoryBreaksAcrossSleepAndMissingMeasurements() {
        var history = BatteryHistory()
        let base = Date(timeIntervalSince1970: 100_000)
        for (offset, watts) in [(0.0, 8.0), (5, 9), (10, Double.nan), (15, 10), (100, 5)] {
            history.append(BatteryReading(date: base.addingTimeInterval(offset), percent: 50,
                                          watts: watts.isNaN ? nil : watts))
        }
        let points = history.points(since: base, power: true)
        XCTAssertEqual(points.map(\.value), [8, 9, 10, 5])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2])
        XCTAssertEqual(history.points(since: base, power: false).count, 5)
        history.append(BatteryReading(date: base.addingTimeInterval(BatteryHistory.retention + 101), percent: 45))
        XCTAssertEqual(history.samples.count, 1)
        history.append(BatteryReading(date: base, percent: 50))
        XCTAssertEqual(history.samples.count, 1, "A wall-clock rollback must not disorder history")
    }

    func testShortWakeExplicitlyStartsANewSegment() {
        var history = BatteryHistory()
        let base = Date(timeIntervalSince1970: 100_000)
        history.append(BatteryReading(date: base, percent: 50, watts: 5))
        history.startNewSegment()
        history.append(BatteryReading(date: base.addingTimeInterval(5), percent: 50, watts: 6))
        XCTAssertEqual(history.points(since: base, power: true).map(\.segment), [0, 1])
    }
}

final class DeviceBatteryTests: XCTestCase {
    func testBluetoothIncludesOnlyConnectedAndPreservesComponents() throws {
        let json: [String: Any] = ["SPBluetoothDataType": [[
            "device_connected": [
                ["AirPods": ["device_address": "AA:BB", "device_batteryLevelLeft": "80%",
                             "device_batteryLevelRight": "0%", "device_batteryLevelCase": "45%"]],
                ["Mouse": ["device_address": "CC:DD", "device_batteryLevelMain": 32]],
                ["Other Mouse": ["device_address": "EE:FF"]]
            ],
            "device_not_connected": [["Watch": ["device_batteryLevelMain": "90%"]]]
        ]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let devices = try XCTUnwrap(DeviceBatteryReader.decodeBluetooth(data))
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices.first { $0.name == "AirPods" }?.levels.map(\.percent), [80, 0, 45])
        XCTAssertTrue(devices.first { $0.name == "Other Mouse" }?.levels.isEmpty == true)
        XCTAssertNil(DeviceBatteryReader.decodeBluetooth(Data("invalid".utf8)))
    }

    func testDeviceLevelsRejectSentinelsAndPreserveEmptyBattery() {
        for invalid: Any in ["unknown", "-1%", "101%", true, Double.nan] {
            XCTAssertNil(DeviceBatteryReader.percent(invalid))
        }
        XCTAssertEqual(DeviceBatteryReader.phoneLevels(["BatteryCurrentCapacity": 0]).first?.percent, 0)
        XCTAssertTrue(DeviceBatteryReader.phoneLevels([:]).isEmpty)
    }

    func testCommandsBoundRuntimeAndOutputAndHandleFailure() async {
        let clock = ContinuousClock()
        let start = clock.now
        let timeout = await BatteryCommand.run("/bin/sleep", arguments: ["10"], timeout: 0.1)
        XCTAssertNil(timeout)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        let oversized = await BatteryCommand.run("/usr/bin/yes", arguments: [], timeout: 3)
        XCTAssertNil(oversized)
        let failed = await BatteryCommand.run("/usr/bin/false", arguments: [], timeout: 1)
        XCTAssertNil(failed)
        let output = await BatteryCommand.run("/bin/echo", arguments: ["battery"], timeout: 1)
        XCTAssertEqual(output.flatMap { String(data: $0, encoding: .utf8) }, "battery\n")
    }

    func testCommandCancellationTerminatesChild() async throws {
        let task = Task { await BatteryCommand.run("/bin/sleep", arguments: ["10"], timeout: 20) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let output = await task.value
        XCTAssertNil(output)
    }

    func testDeadlineStillAppliesWhenDescendantHoldsStdout() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await BatteryCommand.run("/bin/sh", arguments: ["-c", "sleep 2 & exit 0"], timeout: 0.1)
        XCTAssertNil(result)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }
}
