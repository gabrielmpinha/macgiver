import XCTest
@testable import MacGiver

final class StorageReadingTests: XCTestCase {
    func testDecodeCalculatesUsedSpaceAndPercentage() {
        let reading = StorageReading.decode(totalBytes: 1_000, freeBytes: 250)

        XCTAssertEqual(reading.availability, .available)
        XCTAssertEqual(reading.usedBytes, 750)
        XCTAssertEqual(reading.usedPercent ?? 0, 75, accuracy: 0.0001)
        XCTAssertEqual(reading.totalBytes, 1_000)
        XCTAssertEqual(reading.freeBytes, 250)
    }

    func testInvalidCapacityValuesRemainUnavailable() {
        for values in [(nil, 1_000), (0, 0), (-1, 0), (1_000, -1), (1_000, 1_001)] as [(Int64?, Int64?)] {
            let reading = StorageReading.decode(totalBytes: values.0, freeBytes: values.1)
            XCTAssertEqual(reading.availability, .unavailable)
            XCTAssertNil(reading.usedBytes)
            XCTAssertNil(reading.usedPercent)
        }
    }

    func testByteFormattingProducesAUnitAndPreservesZero() {
        let oneGigabyte = StorageReading.formatBytes(1_000_000_000)

        XCTAssertTrue(oneGigabyte.contains("GB"), oneGigabyte)
        XCTAssertFalse(StorageReading.formatBytes(0).isEmpty)
    }

    func testHistoryBreaksAcrossMissingMeasurementsAndKeepsRetentionBound() {
        var history = StorageHistory()
        let base = Date(timeIntervalSince1970: 100_000)
        for (offset, freeBytes) in [(0.0, 250), (5, 240), (10, nil), (15, 230), (100, 220)] as [(TimeInterval, Int64?)] {
            history.append(StorageReading.decode(totalBytes: 1_000, freeBytes: freeBytes,
                                                 date: base.addingTimeInterval(offset)))
        }

        let points = history.points(since: base)
        XCTAssertEqual(points.map(\.value), [75, 76, 77, 78])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2])

        history.append(StorageReading.decode(totalBytes: 1_000, freeBytes: 250,
                                             date: base.addingTimeInterval(StorageHistory.retention + 101)))
        XCTAssertEqual(history.samples.count, 1)
    }

    func testShortWakeExplicitlyStartsANewSegment() {
        var history = StorageHistory()
        let base = Date(timeIntervalSince1970: 100_000)
        history.append(StorageReading.decode(totalBytes: 1_000, freeBytes: 500, date: base))
        history.startNewSegment()
        history.append(StorageReading.decode(totalBytes: 1_000, freeBytes: 490, date: base.addingTimeInterval(5)))

        XCTAssertEqual(history.points(since: base).map(\.segment), [0, 1])
    }
}
