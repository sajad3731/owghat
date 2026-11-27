import Foundation
import Testing
@testable import OwghatCore

@Suite("Tehran Geophysics Prayer Times")
struct TehranPrayerTimesTests {
    private let calculator = AstronomicalPrayerCalculator()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let tehran = GeoLocation.tehran

    private func makeReferenceDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: 0
        ))!
    }

    private func assertWithinOneMinute(
        _ actual: Date?,
        expectedHour: Int,
        expectedMinute: Int,
        year: Int,
        month: Int,
        day: Int,
        prayer: Prayer
    ) {
        #expect(actual != nil, "Missing time for \(prayer.rawValue)")
        guard let actual else { return }
        let expected = makeReferenceDate(
            year: year,
            month: month,
            day: day,
            hour: expectedHour,
            minute: expectedMinute
        )
        let diffSeconds = abs(actual.timeIntervalSince(expected))
        #expect(
            diffSeconds <= 60.0,
            "\(prayer.rawValue) on \(year)-\(month)-\(day) differed by \(diffSeconds)s (actual: \(DigitFormatter.formatTime(actual, timeZone: tehranTZ, persianDigits: false)), expected: \(String(format: "%02d:%02d", expectedHour, expectedMinute)))"
        )
    }

    @Test("Vernal equinox / 1 Farvardin (2025-03-21) matches Tehran Geophysics within ±1 min")
    func tehranSpringEquinox() throws {
        let date = DateComponents(year: 2025, month: 3, day: 21)
        let times = try calculator.calculate(for: date, location: tehran, timeZone: tehranTZ, method: .tehran)

        assertWithinOneMinute(times.time(for: .imsak), expectedHour: 4, expectedMinute: 33, year: 2025, month: 3, day: 21, prayer: .imsak)
        assertWithinOneMinute(times.time(for: .fajr), expectedHour: 4, expectedMinute: 43, year: 2025, month: 3, day: 21, prayer: .fajr)
        assertWithinOneMinute(times.time(for: .sunrise), expectedHour: 6, expectedMinute: 7, year: 2025, month: 3, day: 21, prayer: .sunrise)
        assertWithinOneMinute(times.time(for: .dhuhr), expectedHour: 12, expectedMinute: 12, year: 2025, month: 3, day: 21, prayer: .dhuhr)
        assertWithinOneMinute(times.time(for: .sunset), expectedHour: 18, expectedMinute: 17, year: 2025, month: 3, day: 21, prayer: .sunset)
        assertWithinOneMinute(times.time(for: .maghrib), expectedHour: 18, expectedMinute: 35, year: 2025, month: 3, day: 21, prayer: .maghrib)
        assertWithinOneMinute(times.time(for: .isha), expectedHour: 19, expectedMinute: 22, year: 2025, month: 3, day: 21, prayer: .isha)
        assertWithinOneMinute(times.time(for: .midnight), expectedHour: 23, expectedMinute: 30, year: 2025, month: 3, day: 21, prayer: .midnight)
    }

    @Test("Summer solstice / 1 Tir (2025-06-22) matches Tehran Geophysics within ±1 min")
    func tehranSummerSolstice() throws {
        let date = DateComponents(year: 2025, month: 6, day: 22)
        let times = try calculator.calculate(for: date, location: tehran, timeZone: tehranTZ, method: .tehran)

        assertWithinOneMinute(times.time(for: .imsak), expectedHour: 2, expectedMinute: 52, year: 2025, month: 6, day: 22, prayer: .imsak)
        assertWithinOneMinute(times.time(for: .fajr), expectedHour: 3, expectedMinute: 2, year: 2025, month: 6, day: 22, prayer: .fajr)
        assertWithinOneMinute(times.time(for: .sunrise), expectedHour: 4, expectedMinute: 49, year: 2025, month: 6, day: 22, prayer: .sunrise)
        assertWithinOneMinute(times.time(for: .dhuhr), expectedHour: 12, expectedMinute: 6, year: 2025, month: 6, day: 22, prayer: .dhuhr)
        assertWithinOneMinute(times.time(for: .sunset), expectedHour: 19, expectedMinute: 24, year: 2025, month: 6, day: 22, prayer: .sunset)
        assertWithinOneMinute(times.time(for: .maghrib), expectedHour: 19, expectedMinute: 45, year: 2025, month: 6, day: 22, prayer: .maghrib)
        assertWithinOneMinute(times.time(for: .isha), expectedHour: 20, expectedMinute: 44, year: 2025, month: 6, day: 22, prayer: .isha)
        assertWithinOneMinute(times.time(for: .midnight), expectedHour: 23, expectedMinute: 13, year: 2025, month: 6, day: 22, prayer: .midnight)
    }

    @Test("Winter solstice / 1 Dey (2025-12-22) matches Tehran Geophysics within ±1 min")
    func tehranWinterSolstice() throws {
        let date = DateComponents(year: 2025, month: 12, day: 22)
        let times = try calculator.calculate(for: date, location: tehran, timeZone: tehranTZ, method: .tehran)

        assertWithinOneMinute(times.time(for: .imsak), expectedHour: 5, expectedMinute: 31, year: 2025, month: 12, day: 22, prayer: .imsak)
        assertWithinOneMinute(times.time(for: .fajr), expectedHour: 5, expectedMinute: 41, year: 2025, month: 12, day: 22, prayer: .fajr)
        assertWithinOneMinute(times.time(for: .sunrise), expectedHour: 7, expectedMinute: 11, year: 2025, month: 12, day: 22, prayer: .sunrise)
        assertWithinOneMinute(times.time(for: .dhuhr), expectedHour: 12, expectedMinute: 3, year: 2025, month: 12, day: 22, prayer: .dhuhr)
        assertWithinOneMinute(times.time(for: .sunset), expectedHour: 16, expectedMinute: 55, year: 2025, month: 12, day: 22, prayer: .sunset)
        assertWithinOneMinute(times.time(for: .maghrib), expectedHour: 17, expectedMinute: 15, year: 2025, month: 12, day: 22, prayer: .maghrib)
        assertWithinOneMinute(times.time(for: .isha), expectedHour: 18, expectedMinute: 6, year: 2025, month: 12, day: 22, prayer: .isha)
        assertWithinOneMinute(times.time(for: .midnight), expectedHour: 23, expectedMinute: 18, year: 2025, month: 12, day: 22, prayer: .midnight)
    }

    @Test("Alternative calculation methods produce ordered times")
    func alternativeMethods() throws {
        let date = DateComponents(year: 2025, month: 5, day: 10)
        let custom = CalculationMethod.custom(
            CalculationParameters(
                fajrAngle: 17.0,
                maghribRule: .angle(4.0),
                ishaRule: .minutesAfterMaghrib(60),
                imsakMinutesBeforeFajr: 12,
                midnightMode: .shia
            )
        )

        for method in CalculationMethod.allPresets + [custom] {
            let result = try calculator.calculate(for: date, location: tehran, timeZone: tehranTZ, method: method)
            let ordered = result.orderedEntries()
            #expect(ordered.count == Prayer.allCases.count)
            for pair in zip(ordered, ordered.dropFirst()) {
                #expect(pair.0.date <= pair.1.date, "Out of order in method \(method.id): \(pair.0.prayer) > \(pair.1.prayer)")
            }
        }
    }
}
