import Foundation
import Testing
@testable import OwghatCore

@Suite("Next Prayer and Countdown Edge Cases")
struct CountdownAndEdgeCaseTests {
    private let resolver = PrayerTimeResolver()
    private let calculator = AstronomicalPrayerCalculator()

    @Test("Next prayer rolls over to tomorrow's Fajr after midnight")
    func rolloverAfterIslamicMidnight() async throws {
        let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ

        // 23:45 on 2025-03-21 is after Tehran's Shia midnight (~23:29).
        let lateNight = cal.date(from: DateComponents(year: 2025, month: 3, day: 21, hour: 23, minute: 45))!
        var settings = AppSettings.default
        settings.visiblePrayers = [.fajr, .sunrise, .dhuhr, .maghrib, .midnight]

        let next = try await resolver.nextPrayer(
            at: lateNight,
            location: .tehran,
            timeZone: tehranTZ,
            settings: settings
        )

        #expect(next != nil)
        #expect(next?.entry.prayer == .fajr)

        let tomorrowFajr = cal.date(from: DateComponents(year: 2025, month: 3, day: 22, hour: 4, minute: 41))!
        #expect(abs(next!.entry.date.timeIntervalSince(tomorrowFajr)) <= 120)
        #expect(next!.remainingInterval > 4 * 3600)
        #expect(next!.remainingInterval < 6 * 3600)
    }

    @Test("Early morning before post-midnight Islamic midnight picks yesterday's midnight")
    func earlyMorningBeforeYesterdayStandardMidnight() async throws {
        let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ

        // With MWL standard midnight in summer (2025-06-22), sunset ~19:24 and next sunrise ~04:49 -> midnight ~00:07.
        // At 00:02 on 2025-06-23, yesterday's midnight (~00:07) is still upcoming before Fajr (~03:02).
        let afterCalendarMidnight = cal.date(from: DateComponents(year: 2025, month: 6, day: 23, hour: 0, minute: 2))!
        var settings = AppSettings.default
        settings.calculationMethod = .mwl
        settings.visiblePrayers = [.fajr, .sunrise, .dhuhr, .maghrib, .midnight]

        let next = try await resolver.nextPrayer(
            at: afterCalendarMidnight,
            location: .tehran,
            timeZone: tehranTZ,
            settings: settings
        )

        #expect(next?.entry.prayer == .midnight)
        #expect(next!.remainingInterval < 20 * 60)
    }

    @Test("DST spring-forward countdown accounts for the skipped hour")
    func dstSpringForwardCountdown() async throws {
        let nyTZ = TimeZone(identifier: "America/New_York")!
        let newYork = GeoLocation(
            id: "us-ny",
            name: "New York",
            persianName: "نیویورک",
            countryCode: "US",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York"
        )
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyTZ

        // 2025-03-09 in New York: clocks jump from 01:59 EST (-05) to 03:00 EDT (-04).
        let beforeJump = cal.date(from: DateComponents(year: 2025, month: 3, day: 9, hour: 1, minute: 30))!
        var settings = AppSettings.default
        settings.calculationMethod = .isna
        settings.visiblePrayers = [.fajr, .sunrise, .dhuhr, .maghrib, .isha]

        let next = try await resolver.nextPrayer(
            at: beforeJump,
            location: newYork,
            timeZone: nyTZ,
            settings: settings
        )

        #expect(next?.entry.prayer == .fajr)
        // Fajr around 06:00 EDT is only ~3.5 physical hours after 01:30 EST, not 4.5 hours.
        let fajrComponents = cal.dateComponents([.hour, .minute], from: next!.entry.date)
        let wallClockMinutes = fajrComponents.hour! * 60 + fajrComponents.minute!
        let naiveMinutesDiff = wallClockMinutes - (1 * 60 + 30)
        let actualMinutesDiff = Int((next!.remainingInterval / 60.0).rounded())
        #expect(naiveMinutesDiff - actualMinutesDiff == 60)
    }

    @Test("DST fall-back countdown accounts for the repeated hour")
    func dstFallBackCountdown() async throws {
        let nyTZ = TimeZone(identifier: "America/New_York")!
        let newYork = GeoLocation(
            id: "us-ny",
            name: "New York",
            persianName: "نیویورک",
            countryCode: "US",
            latitude: 40.7128,
            longitude: -74.0060,
            timeZoneIdentifier: "America/New_York"
        )
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nyTZ

        // 2025-11-02 in New York: clocks repeat 01:00..02:00 when EDT (-04) transitions to EST (-05).
        let beforeFallback = cal.date(from: DateComponents(year: 2025, month: 11, day: 2, hour: 0, minute: 30))!
        var settings = AppSettings.default
        settings.calculationMethod = .isna
        settings.visiblePrayers = [.fajr, .sunrise, .dhuhr, .maghrib, .isha]

        let next = try await resolver.nextPrayer(
            at: beforeFallback,
            location: newYork,
            timeZone: nyTZ,
            settings: settings
        )

        #expect(next?.entry.prayer == .fajr)
        let fajrComponents = cal.dateComponents([.hour, .minute], from: next!.entry.date)
        let wallClockMinutes = fajrComponents.hour! * 60 + fajrComponents.minute!
        let naiveMinutesDiff = wallClockMinutes - 30
        let actualMinutesDiff = Int((next!.remainingInterval / 60.0).rounded())
        #expect(actualMinutesDiff - naiveMinutesDiff == 60)
    }

    @Test("Countdown formatting produces expected minus-prefixed strings")
    func countdownFormatting() {
        let entry = PrayerTimeEntry(prayer: .maghrib, date: Date())
        let resolution = NextPrayerResolution(entry: entry, remainingInterval: 42 * 60)
        #expect(resolution.formattedCountdown(persianDigits: false) == "−00:42")
        #expect(resolution.formattedCountdown(persianDigits: true) == "−۰۰:۴۲")
    }

    @Test("Extreme eastern time zone (Pacific/Auckland) produces valid chronological schedule")
    func extremeEastTimeZone() throws {
        let aucklandTZ = TimeZone(identifier: "Pacific/Auckland")!
        let auckland = GeoLocation(
            id: "nz-auckland",
            name: "Auckland",
            persianName: "اوکلند",
            countryCode: "NZ",
            latitude: -36.8485,
            longitude: 174.7633,
            timeZoneIdentifier: "Pacific/Auckland"
        )
        let times = try calculator.calculate(
            for: DateComponents(year: 2025, month: 10, day: 10),
            location: auckland,
            timeZone: aucklandTZ,
            method: .tehran
        )
        let ordered = times.orderedEntries()
        #expect(ordered.count == Prayer.allCases.count)
        for pair in zip(ordered, ordered.dropFirst()) {
            #expect(pair.0.date <= pair.1.date)
        }
    }
}
