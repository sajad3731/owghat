import Foundation
import Testing
@testable import OwghatCore

@Suite("PanelSchedule, PanelHeader, Occasions, and Backoff")
struct PanelScheduleAndHeaderTests {
    private let calculator = AstronomicalPrayerCalculator()
    private let converter = CalendarConverter()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    @Test("Marks passed, next, and upcoming states and flags tomorrow's Fajr after Isha/Midnight")
    func rowStatesAndTomorrowFlag() throws {
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran,
            manualOverrides: ["2025-03-21": [.maghrib: LocalTimeOfDay(hour: 18, minute: 40)]]
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let visible: Set<Prayer> = [.fajr, .sunrise, .dhuhr, .maghrib, .isha]

        // Mid-day before Dhuhr (11:00)
        let midDay = makeDate(year: 2025, month: 3, day: 21, hour: 11, minute: 0, timeZone: tehranTZ)
        let midPanel = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            visiblePrayers: visible,
            now: midDay,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(midPanel.rows.count == 5)
        #expect(midPanel.rows.first { $0.prayer == .fajr }?.state == .passed)
        #expect(midPanel.rows.first { $0.prayer == .sunrise }?.state == .passed)
        #expect(midPanel.rows.first { $0.prayer == .dhuhr }?.state == .next)
        #expect(midPanel.rows.first { $0.prayer == .maghrib }?.state == .upcoming)
        #expect(midPanel.rows.first { $0.prayer == .maghrib }?.isOverridden == true)
        #expect(midPanel.rows.first { $0.prayer == .maghrib }?.formattedTime == "18:40")
        #expect(midPanel.nextBannerTitle == "Dhuhr")

        // After Isha (21:00) -> today's Fajr is .passed (not tomorrow), tomorrow's Fajr is .next + isTomorrow
        let lateNight = makeDate(year: 2025, month: 3, day: 21, hour: 21, minute: 0, timeZone: tehranTZ)
        let latePanelEn = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            visiblePrayers: visible,
            now: lateNight,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        let todayFajr = latePanelEn.rows.first { $0.prayer == .fajr && !$0.isTomorrow }
        let tomorrowFajr = latePanelEn.rows.first { $0.prayer == .fajr && $0.isTomorrow }
        #expect(todayFajr?.state == .passed)
        #expect(tomorrowFajr?.state == .next)
        #expect(tomorrowFajr?.isTomorrow == true)
        #expect(latePanelEn.nextRow == tomorrowFajr)
        #expect(latePanelEn.nextBannerTitle == "Tomorrow · Fajr")

        let latePanelFa = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            visiblePrayers: visible,
            now: lateNight,
            timeZone: tehranTZ,
            language: .persian,
            usePersianDigits: true
        )
        #expect(latePanelFa.nextBannerTitle == "فردا · اذان صبح")
    }

    @Test("Filters rows strictly by visiblePrayers")
    func visiblePrayersFiltering() throws {
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let morning = makeDate(year: 2025, month: 3, day: 21, hour: 5, minute: 0, timeZone: tehranTZ)
        let panel = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: nil,
            visiblePrayers: [.fajr, .dhuhr, .maghrib],
            now: morning,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(panel.rows.map(\.prayer) == [.fajr, .dhuhr, .maghrib])
        #expect(panel.nextRow?.prayer == .dhuhr)
    }

    @Test("Computes progress at start, middle, end of interval and across midnight")
    func progressAcrossIntervalAndMidnight() throws {
        let yesterday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 20),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let visible: Set<Prayer> = [.fajr, .dhuhr, .maghrib, .midnight]
        let fajrDate = today.time(for: .fajr)!
        let dhuhrDate = today.time(for: .dhuhr)!
        let interval = dhuhrDate.timeIntervalSince(fajrDate)

        // Start of interval (right at Fajr -> Fajr is passed, Dhuhr is next, progress = 0)
        let atStart = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: nil,
            yesterdaySchedule: yesterday,
            visiblePrayers: visible,
            now: fajrDate,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(atStart.nextRow?.prayer == .dhuhr)
        #expect(abs(atStart.progress - 0.0) < 0.001)

        // Middle of interval
        let atMid = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: nil,
            yesterdaySchedule: yesterday,
            visiblePrayers: visible,
            now: fajrDate.addingTimeInterval(interval / 2.0),
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(abs(atMid.progress - 0.5) < 0.001)

        // Near end of interval (1 second before Dhuhr)
        let atEnd = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: nil,
            yesterdaySchedule: yesterday,
            visiblePrayers: visible,
            now: dhuhrDate.addingTimeInterval(-1.0),
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(atEnd.progress > 0.99 && atEnd.progress <= 1.0)

        // Across midnight using yesterday's midnight to today's Fajr
        let yMidnight = yesterday.time(for: .midnight)!
        let nightDuration = fajrDate.timeIntervalSince(yMidnight)
        let afterCalendarMidnight = yMidnight.addingTimeInterval(nightDuration * 0.5)
        let crossMidnight = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: nil,
            yesterdaySchedule: yesterday,
            visiblePrayers: visible,
            now: afterCalendarMidnight,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(crossMidnight.nextRow?.prayer == .fajr)
        #expect(crossMidnight.previousBoundaryDate == yMidnight)
        #expect(abs(crossMidnight.progress - 0.5) < 0.001)
    }

    @Test("Builds PanelSchedule accurately in Europe/Berlin across DST transition")
    func berlinDstPanelSchedule() throws {
        let berlin = GeoLocation(
            id: "de-berlin",
            name: "Berlin",
            persianName: "برلین",
            countryCode: "DE",
            latitude: 52.5200,
            longitude: 13.4050,
            timeZoneIdentifier: "Europe/Berlin"
        )
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 30),
            location: berlin,
            timeZone: berlinTZ,
            method: .mwl
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 31),
            location: berlin,
            timeZone: berlinTZ,
            method: .mwl
        )
        let checkTime = makeDate(year: 2025, month: 3, day: 30, hour: 13, minute: 30, timeZone: berlinTZ)
        let panel = PanelSchedule.build(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            visiblePrayers: [.fajr, .sunrise, .dhuhr, .maghrib, .isha],
            now: checkTime,
            timeZone: berlinTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(panel.rows.first { $0.prayer == .dhuhr }?.state == .passed)
        #expect(panel.nextRow?.prayer == .maghrib)
        #expect(panel.progress > 0 && panel.progress < 1)
    }

    @Test("Formats PanelHeader punctuation and digits per language")
    func panelHeaderPunctuation() {
        let nowruz = makeDate(year: 2025, month: 3, day: 21, hour: 12, minute: 0, timeZone: tehranTZ)

        let faDates = converter.allDates(for: nowruz, timeZone: tehranTZ, language: .persian)
        let faHeader = PanelHeader.build(
            location: .tehran,
            method: .tehran,
            dates: faDates,
            language: .persian,
            usePersianDigits: true
        )
        #expect(faHeader.jalaliLine.contains("، "))
        #expect(!faHeader.jalaliLine.contains(", "))
        #expect(faHeader.jalaliLine.contains("۱۴۰۴"))
        #expect(faHeader.secondaryDateLine.contains(" · "))
        #expect(faHeader.locationName == "تهران")

        let enDates = converter.allDates(for: nowruz, timeZone: tehranTZ, language: .english)
        let enHeader = PanelHeader.build(
            location: .tehran,
            method: .tehran,
            dates: enDates,
            language: .english,
            usePersianDigits: false
        )
        #expect(enHeader.jalaliLine.contains(", "))
        #expect(!enHeader.jalaliLine.contains("،"))
        #expect(enHeader.jalaliLine.contains("1404"))
        #expect(enHeader.secondaryDateLine.contains(" · "))
        #expect(enHeader.locationName == "Tehran")
    }

    @Test("Builds PanelOccasionsDisplay for today or nearest upcoming occasion")
    func occasionsFallback() {
        let now = makeDate(year: 2025, month: 3, day: 21, hour: 10, minute: 0, timeZone: tehranTZ)
        let later = makeDate(year: 2025, month: 3, day: 24, hour: 10, minute: 0, timeZone: tehranTZ)
        let sampleOccasion = Occasion(
            id: "test-1",
            titleEn: "Sample Event",
            titleFa: "رویداد نمونه",
            calendarKey: OccasionCalendarKey(calendar: .gregorian, month: 3, day: 24),
            isOfficialHoliday: true
        )

        let upcomingEn = PanelOccasionsDisplay.build(
            todayOccasions: [],
            upcomingOccasions: [DatedOccasion(date: later, dateKey: "2025-03-24", occasion: sampleOccasion)],
            now: now,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(upcomingEn?.isShowingUpcoming == true)
        #expect(upcomingEn?.items.first?.relativeDateText == "in 3 days")

        let upcomingFa = PanelOccasionsDisplay.build(
            todayOccasions: [],
            upcomingOccasions: [DatedOccasion(date: later, dateKey: "2025-03-24", occasion: sampleOccasion)],
            now: now,
            timeZone: tehranTZ,
            language: .persian,
            usePersianDigits: true
        )
        #expect(upcomingFa?.items.first?.relativeDateText == "۳ روز دیگر")

        let none = PanelOccasionsDisplay.build(
            todayOccasions: [],
            upcomingOccasions: [],
            now: now,
            timeZone: tehranTZ,
            language: .english,
            usePersianDigits: false
        )
        #expect(none == nil)
    }

    @Test("RefreshBackoff increases retry interval on consecutive failures and resets on success")
    func refreshBackoffBehavior() {
        var backoff = RefreshBackoff()
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        #expect(backoff.canRetry(at: t0))
        #expect(backoff.recordFailure(at: t0) == 30)
        #expect(!backoff.canRetry(at: t0.addingTimeInterval(29)))
        #expect(backoff.canRetry(at: t0.addingTimeInterval(30)))

        #expect(backoff.recordFailure(at: t0.addingTimeInterval(30)) == 120)
        #expect(backoff.recordFailure(at: t0.addingTimeInterval(150)) == 300)
        #expect(backoff.recordFailure(at: t0.addingTimeInterval(450)) == 300)

        backoff.recordSuccess()
        #expect(backoff.failureCount == 0)
        #expect(backoff.canRetry(at: t0))
    }
}
