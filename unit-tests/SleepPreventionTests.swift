import XCTest

final class SleepPreventionTests: XCTestCase {
    func testBatteryStopsOnBattery() throws {
        XCTAssertTrue(SleepPreventionTestable.batteryStops(10, 10, true))
        XCTAssertTrue(SleepPreventionTestable.batteryStops(10, 3, true))
        XCTAssertFalse(SleepPreventionTestable.batteryStops(10, 11, true))
        XCTAssertFalse(SleepPreventionTestable.batteryStops(10, 100, true))
    }

    func testBatteryNeverStopsWithoutABatteryToDrain() throws {
        XCTAssertFalse(SleepPreventionTestable.batteryStops(10, 5, false))
        XCTAssertFalse(SleepPreventionTestable.batteryStops(10, nil, true))
    }

    func testCutoffOffDisablesTheGuard() throws {
        XCTAssertFalse(SleepPreventionTestable.batteryStops(SleepPreventionTestable.cutoffOff, 1, true))
        XCTAssertFalse(SleepPreventionTestable.batteryStops(SleepPreventionTestable.cutoffOff, 0, true))
    }

    func testClamping() throws {
        XCTAssertEqual(SleepPreventionTestable.clampMinutes(0), SleepPreventionTestable.minMinutes)
        XCTAssertEqual(SleepPreventionTestable.clampMinutes(-5), SleepPreventionTestable.minMinutes)
        XCTAssertEqual(SleepPreventionTestable.clampMinutes(90), 90)
        XCTAssertEqual(SleepPreventionTestable.clampMinutes(99999), SleepPreventionTestable.maxMinutes)
        XCTAssertEqual(SleepPreventionTestable.clampCutoff(-1), SleepPreventionTestable.cutoffOff)
        XCTAssertEqual(SleepPreventionTestable.clampCutoff(0), SleepPreventionTestable.cutoffOff)
        XCTAssertEqual(SleepPreventionTestable.clampCutoff(3), SleepPreventionTestable.minCutoff)
        XCTAssertEqual(SleepPreventionTestable.clampCutoff(7), 7)
        XCTAssertEqual(SleepPreventionTestable.clampCutoff(80), SleepPreventionTestable.maxCutoff)
    }

    func testParseDuration() throws {
        XCTAssertEqual(SleepPreventionTestable.parseDuration("90"), 90)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("45m"), 45)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("2h"), 120)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("1h30"), 90)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("1h 30m"), 90)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("1H30M"), 90)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("24h"), 24 * 60)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("36h"), 36 * 60)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("3d"), 3 * 24 * 60)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("2d 6h"), 2 * 24 * 60 + 360)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("1d2h30m"), 24 * 60 + 150)
    }

    func testFormatDurationBeyondADay() throws {
        XCTAssertEqual(SleepPreventionTestable.formatDuration(24 * 60), "1d")
        XCTAssertEqual(SleepPreventionTestable.formatDuration(36 * 60), "1d 12h")
        XCTAssertEqual(SleepPreventionTestable.formatDuration(24 * 60 + 150), "1d 2h 30m")
        XCTAssertEqual(SleepPreventionTestable.formatDuration(SleepPreventionTestable.maxMinutes), "30d")
    }

    func testParseDurationClampsAndRejects() throws {
        XCTAssertEqual(SleepPreventionTestable.parseDuration("0"), SleepPreventionTestable.minMinutes)
        XCTAssertEqual(SleepPreventionTestable.parseDuration("1000d"), SleepPreventionTestable.maxMinutes)
        XCTAssertNil(SleepPreventionTestable.parseDuration("2h1d"))
        XCTAssertNil(SleepPreventionTestable.parseDuration(""))
        XCTAssertNil(SleepPreventionTestable.parseDuration("   "))
        XCTAssertNil(SleepPreventionTestable.parseDuration("soon"))
        XCTAssertNil(SleepPreventionTestable.parseDuration("h30"))
        XCTAssertNil(SleepPreventionTestable.parseDuration("1h30x"))
        XCTAssertNil(SleepPreventionTestable.parseDuration("-5"))
    }

    func testFormatDurationRoundTripsThroughParsing() throws {
        for minutes in [1, 5, 45, 60, 90, 120, 359, 720, 1440] {
            let text = SleepPreventionTestable.formatDuration(minutes)
            XCTAssertEqual(SleepPreventionTestable.parseDuration(text), minutes, "\(minutes) formatted as \(text)")
        }
    }

    /// fixed calendar and zone, so the boundaries don't depend on where the tests run
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.date(from: text)!
    }

    func testDaysAhead() throws {
        let now = date("2026-07-31 15:00")
        XCTAssertEqual(SleepPreventionTestable.daysAhead(date("2026-07-31 15:30"), now, calendar), 0)
        XCTAssertEqual(SleepPreventionTestable.daysAhead(date("2026-07-31 23:59"), now, calendar), 0)
        XCTAssertEqual(SleepPreventionTestable.daysAhead(date("2026-08-01 00:01"), now, calendar), 1)
        XCTAssertEqual(SleepPreventionTestable.daysAhead(date("2026-08-03 15:00"), now, calendar), 3)
        XCTAssertEqual(SleepPreventionTestable.daysAhead(date("2026-08-30 15:00"), now, calendar), 30)
    }

    /// a 3 day session lands well past tomorrow: the label has to name the day, not just the time
    func testDaysAheadForEveryDurationTheFieldAccepts() throws {
        let now = date("2026-07-31 15:00")
        for (text, expected) in [("90", 0), ("8h", 0), ("12h", 1), ("36h", 2), ("3d", 3), ("30d", 30)] {
            let minutes = SleepPreventionTestable.parseDuration(text)!
            let end = calendar.date(byAdding: .minute, value: minutes, to: now)!
            XCTAssertEqual(SleepPreventionTestable.daysAhead(end, now, calendar), expected, "\(text) ended up on the wrong day")
        }
    }

    func testRemaining() throws {
        XCTAssertEqual(SleepPreventionTestable.remaining(1800), "30m")
        XCTAssertEqual(SleepPreventionTestable.remaining(1799), "30m")
        XCTAssertEqual(SleepPreventionTestable.remaining(3600), "1h")
        XCTAssertEqual(SleepPreventionTestable.remaining(5400), "1h 30m")
        XCTAssertEqual(SleepPreventionTestable.remaining(3660), "1h 1m")
    }

    func testRemainingNeverCountsDownToZero() throws {
        XCTAssertEqual(SleepPreventionTestable.remaining(1), "1m")
        XCTAssertEqual(SleepPreventionTestable.remaining(0), "1m")
        XCTAssertEqual(SleepPreventionTestable.remaining(-30), "1m")
    }
}
