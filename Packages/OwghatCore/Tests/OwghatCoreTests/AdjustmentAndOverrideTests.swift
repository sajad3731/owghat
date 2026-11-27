import Foundation
import Testing
@testable import OwghatCore

@Suite("Offsets and Manual Overrides")
struct AdjustmentAndOverrideTests {
    private let calculator = AstronomicalPrayerCalculator()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let tehran = GeoLocation.tehran

    @Test("Per-prayer minute offsets shift calculated times accurately")
    func perPrayerOffsets() throws {
        let date = DateComponents(year: 2025, month: 3, day: 21)
        let baseline = try calculator.calculate(for: date, location: tehran, timeZone: tehranTZ, method: .tehran)

        let offsets: [Prayer: Int] = [
            .fajr: -3,
            .dhuhr: 2,
            .maghrib: 5
        ]
        let adjusted = try calculator.calculate(
            for: date,
            location: tehran,
            timeZone: tehranTZ,
            method: .tehran,
            offsets: offsets
        )

        #expect(adjusted.time(for: .fajr)?.timeIntervalSince(baseline.time(for: .fajr)!) == -180)
        #expect(adjusted.time(for: .dhuhr)?.timeIntervalSince(baseline.time(for: .dhuhr)!) == 120)
        #expect(adjusted.time(for: .maghrib)?.timeIntervalSince(baseline.time(for: .maghrib)!) == 300)
        #expect(adjusted.time(for: .sunrise) == baseline.time(for: .sunrise))
        #expect(adjusted.entry(for: .maghrib)?.appliedOffsetMinutes == 5)
        #expect(adjusted.entry(for: .maghrib)?.isOverridden == false)
    }

    @Test("Manual overrides apply only to the specified date and take precedence over offsets")
    func manualDateOverrides() throws {
        let targetDate = DateComponents(year: 2025, month: 3, day: 21)
        let nextDate = DateComponents(year: 2025, month: 3, day: 22)

        let overrides: [String: [Prayer: LocalTimeOfDay]] = [
            "2025-03-21": [
                .maghrib: LocalTimeOfDay(hour: 18, minute: 52),
                .fajr: LocalTimeOfDay(hour: 4, minute: 39)
            ]
        ]
        let offsets: [Prayer: Int] = [.maghrib: 10, .dhuhr: 3]

        let dayOne = try calculator.calculate(
            for: targetDate,
            location: tehran,
            timeZone: tehranTZ,
            method: .tehran,
            offsets: offsets,
            manualOverrides: overrides
        )
        let dayTwo = try calculator.calculate(
            for: nextDate,
            location: tehran,
            timeZone: tehranTZ,
            method: .tehran,
            offsets: offsets,
            manualOverrides: overrides
        )

        let maghribEntry = dayOne.entry(for: .maghrib)
        #expect(maghribEntry?.isOverridden == true)
        #expect(maghribEntry?.appliedOffsetMinutes == 0)
        #expect(DigitFormatter.formatTime(maghribEntry!.date, timeZone: tehranTZ, persianDigits: false) == "18:52")

        let fajrEntry = dayOne.entry(for: .fajr)
        #expect(fajrEntry?.isOverridden == true)
        #expect(DigitFormatter.formatTime(fajrEntry!.date, timeZone: tehranTZ, persianDigits: false) == "04:39")

        // Dhuhr is not overridden, so offset still applies.
        #expect(dayOne.entry(for: .dhuhr)?.isOverridden == false)
        #expect(dayOne.entry(for: .dhuhr)?.appliedOffsetMinutes == 3)

        // Next day is unaffected by 2025-03-21 overrides.
        #expect(dayTwo.entry(for: .maghrib)?.isOverridden == false)
        #expect(dayTwo.entry(for: .maghrib)?.appliedOffsetMinutes == 10)
    }
}
