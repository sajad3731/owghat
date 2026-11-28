import Foundation
import Testing
@testable import OwghatCore

@Suite("WidgetTimelinePlanner, WidgetEntryModel, and WidgetReloadPolicy")
struct WidgetCoreTests {
    private let calculator = AstronomicalPrayerCalculator()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    private let berlinLocation = GeoLocation(
        id: "de-berlin",
        name: "Berlin",
        persianName: "برلین",
        countryCode: "DE",
        latitude: 52.5200,
        longitude: 13.4050,
        timeZoneIdentifier: "Europe/Berlin"
    )

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

    @Test("After Isha, next prayer is tomorrow's Fajr with passed state on today's Fajr")
    func afterIshaSelectsTomorrowsFajr() throws {
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let lateEvening = makeDate(year: 2025, month: 3, day: 21, hour: 21, minute: 15, timeZone: tehranTZ)

        var settings = WidgetDisplaySettings(appSettings: .default)
        settings.language = .english
        settings.usePersianDigits = false

        let visible: Set<Prayer> = [.fajr, .sunrise, .dhuhr, .maghrib, .isha]
        let modelEn = WidgetEntryModel.build(
            location: .tehran,
            method: .tehran,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            snapshotOccasions: [],
            settings: settings,
            visiblePrayers: visible,
            date: lateEvening,
            timeZone: tehranTZ,
            snapshotAge: 60
        )

        #expect(modelEn.isNextTomorrow == true)
        #expect(modelEn.nextRow?.prayer == .fajr)
        #expect(modelEn.nextRow?.isTomorrow == true)
        #expect(modelEn.nextRow?.state == .next)
        #expect(modelEn.nextBannerTitle == "Tomorrow · Fajr")
        #expect(modelEn.countdownRange == lateEvening...(modelEn.nextRow!.date))

        let todaysFajr = modelEn.rows.first { $0.prayer == .fajr && !$0.isTomorrow }
        #expect(todaysFajr?.state == .passed)

        settings.language = .persian
        settings.usePersianDigits = true
        let modelFa = WidgetEntryModel.build(
            location: .tehran,
            method: .tehran,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            snapshotOccasions: [],
            settings: settings,
            visiblePrayers: visible,
            date: lateEvening,
            timeZone: tehranTZ,
            snapshotAge: 60
        )
        #expect(modelFa.isNextTomorrow == true)
        #expect(modelFa.nextBannerTitle == "فردا · اذان صبح")
        #expect(modelFa.localeIdentifier == "fa_IR")
    }

    @Test("Post-midnight Islamic midnight is present in timeline and entry model")
    func postMidnightIslamicMidnightPresent() throws {
        // Override yesterday's midnight to 00:35 today so post-midnight midnight sits after 00:00.
        let yesterday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 6, day: 20),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran,
            manualOverrides: [:]
        )
        let customYesterdayMidnight = makeDate(year: 2025, month: 6, day: 21, hour: 0, minute: 35, timeZone: tehranTZ)
        var modifiedEntries = yesterday.entries
        modifiedEntries[.midnight] = PrayerTimeEntry(
            prayer: .midnight,
            date: customYesterdayMidnight,
            isOverridden: true,
            appliedOffsetMinutes: 0
        )
        let shiftedYesterday = DailyPrayerTimes(
            dateKey: yesterday.dateKey,
            timeZoneIdentifier: yesterday.timeZoneIdentifier,
            location: yesterday.location,
            method: yesterday.method,
            entries: modifiedEntries,
            source: yesterday.source
        )
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 6, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 6, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )

        let justAfterMidnight = makeDate(year: 2025, month: 6, day: 21, hour: 0, minute: 10, timeZone: tehranTZ)
        let visible: Set<Prayer> = [.fajr, .dhuhr, .maghrib, .midnight]

        let dates = WidgetTimelinePlanner.timelineDates(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            yesterdaySchedule: shiftedYesterday,
            visiblePrayers: visible,
            timeZone: tehranTZ,
            now: justAfterMidnight
        )
        #expect(dates.contains(customYesterdayMidnight))

        let model = WidgetEntryModel.build(
            location: .tehran,
            method: .tehran,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            yesterdaySchedule: shiftedYesterday,
            snapshotOccasions: [],
            settings: WidgetDisplaySettings(appSettings: .default),
            visiblePrayers: visible,
            date: justAfterMidnight,
            timeZone: tehranTZ,
            snapshotAge: 30
        )
        #expect(model.nextRow?.prayer == .midnight)
        #expect(model.nextRow?.date == customYesterdayMidnight)
        #expect(model.nextRow?.state == .next)
        #expect(model.isNextTomorrow == false)
    }

    @Test("Timeline entries span through the end of tomorrow and dedupe within 1 second")
    func timelineSpansToEndOfTomorrowAndDedupesWithinOneSecond() throws {
        let baseDay = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )

        let now = makeDate(year: 2025, month: 3, day: 21, hour: 10, minute: 0, timeZone: tehranTZ)
        let startOfTomorrow = makeDate(year: 2025, month: 3, day: 22, hour: 0, minute: 0, timeZone: tehranTZ)
        let endOfTomorrow = makeDate(year: 2025, month: 3, day: 23, hour: 0, minute: 0, timeZone: tehranTZ)

        // Introduce two entries 0.4 seconds apart at 15:00 in today's schedule.
        var entries = baseDay.entries
        let dhuhrSub = makeDate(year: 2025, month: 3, day: 21, hour: 15, minute: 0, timeZone: tehranTZ)
        entries[.sunset] = PrayerTimeEntry(prayer: .sunset, date: dhuhrSub)
        entries[.maghrib] = PrayerTimeEntry(prayer: .maghrib, date: dhuhrSub.addingTimeInterval(0.4))
        let today = DailyPrayerTimes(
            dateKey: baseDay.dateKey,
            timeZoneIdentifier: baseDay.timeZoneIdentifier,
            location: baseDay.location,
            method: baseDay.method,
            entries: entries,
            source: baseDay.source
        )

        let visible: Set<Prayer> = [.fajr, .dhuhr, .sunset, .maghrib, .isha]
        let dates = WidgetTimelinePlanner.timelineDates(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            yesterdaySchedule: nil,
            visiblePrayers: visible,
            timeZone: tehranTZ,
            now: now
        )

        #expect(dates.first == now)
        #expect(dates.last == endOfTomorrow)
        #expect(dates.contains(startOfTomorrow))
        #expect(dates.contains(tomorrow.time(for: .isha)!))

        // Verify strict monotonic sorting and >= 1.0 s spacing between all adjacent entries.
        for index in 1..<dates.count {
            #expect(dates[index].timeIntervalSince(dates[index - 1]) >= 1.0)
        }
        // Only one entry remains near 15:00.
        let near1500 = dates.filter { abs($0.timeIntervalSince(dhuhrSub)) < 2.0 }
        #expect(near1500.count == 1)
    }

    @Test("Timeline handles Europe/Berlin DST transition and Asia/Tehran midnights")
    func berlinDSTAndTehranTimeline() throws {
        // Spring-forward DST day in Europe/Berlin: 2025-03-30 (23-hour day)
        let berlinYesterday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 29),
            location: berlinLocation,
            timeZone: berlinTZ,
            method: .mwl
        )
        let berlinToday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 30),
            location: berlinLocation,
            timeZone: berlinTZ,
            method: .mwl
        )
        let berlinTomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 31),
            location: berlinLocation,
            timeZone: berlinTZ,
            method: .mwl
        )

        let dstMorning = makeDate(year: 2025, month: 3, day: 30, hour: 1, minute: 30, timeZone: berlinTZ)
        let berlinStartTomorrow = makeDate(year: 2025, month: 3, day: 31, hour: 0, minute: 0, timeZone: berlinTZ)
        let berlinEndTomorrow = makeDate(year: 2025, month: 4, day: 1, hour: 0, minute: 0, timeZone: berlinTZ)

        let berlinDates = WidgetTimelinePlanner.timelineDates(
            todaySchedule: berlinToday,
            tomorrowSchedule: berlinTomorrow,
            yesterdaySchedule: berlinYesterday,
            visiblePrayers: Prayer.defaultVisible,
            timeZone: berlinTZ,
            now: dstMorning
        )
        #expect(berlinDates.first == dstMorning)
        #expect(berlinDates.contains(berlinStartTomorrow))
        #expect(berlinDates.last == berlinEndTomorrow)
        #expect(berlinEndTomorrow.timeIntervalSince(berlinStartTomorrow) == 24 * 3600)
        #expect(berlinStartTomorrow.timeIntervalSince(makeDate(year: 2025, month: 3, day: 30, hour: 0, minute: 0, timeZone: berlinTZ)) == 23 * 3600)

        let tehranToday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 30),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tehranTomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 31),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tehranNow = makeDate(year: 2025, month: 3, day: 30, hour: 14, minute: 0, timeZone: tehranTZ)
        let tehranEndTomorrow = makeDate(year: 2025, month: 4, day: 1, hour: 0, minute: 0, timeZone: tehranTZ)

        let tehranDates = WidgetTimelinePlanner.timelineDates(
            todaySchedule: tehranToday,
            tomorrowSchedule: tehranTomorrow,
            yesterdaySchedule: nil,
            visiblePrayers: Prayer.defaultVisible,
            timeZone: tehranTZ,
            now: tehranNow
        )
        #expect(tehranDates.last == tehranEndTomorrow)
        #expect(tehranDates.contains(tehranTomorrow.time(for: .fajr)!))
    }

    @Test("Prayer selection resolves Follow app settings vs custom vs empty selection")
    func followAppSettingsVsCustomVsEmpty() {
        let appDefaults: Set<Prayer> = [.fajr, .dhuhr, .maghrib]
        let custom: Set<Prayer> = [.fajr, .isha]

        #expect(
            WidgetPrayerSelection.resolveVisiblePrayers(
                followAppSettings: true,
                customSelection: custom,
                appDefaultPrayers: appDefaults
            ) == appDefaults
        )
        #expect(
            WidgetPrayerSelection.resolveVisiblePrayers(
                followAppSettings: false,
                customSelection: custom,
                appDefaultPrayers: appDefaults
            ) == custom
        )
        #expect(
            WidgetPrayerSelection.resolveVisiblePrayers(
                followAppSettings: false,
                customSelection: [],
                appDefaultPrayers: appDefaults
            ) == appDefaults
        )
    }

    @Test("Stale snapshot hint triggers past 48h (47h fresh vs 49h stale) and when nil")
    func staleHintThresholdAt47hAnd49h() {
        #expect(WidgetEntryModel.isSnapshotStale(snapshotAge: 47 * 3600) == false)
        #expect(WidgetEntryModel.isSnapshotStale(snapshotAge: 48 * 3600) == false)
        #expect(WidgetEntryModel.isSnapshotStale(snapshotAge: 49 * 3600) == true)
        #expect(WidgetEntryModel.isSnapshotStale(snapshotAge: nil) == true)
    }

    @Test("WidgetReloadPolicy reloads only when widget-relevant data changes")
    func reloadPolicySensitivity() throws {
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )

        let t0 = makeDate(year: 2025, month: 3, day: 21, hour: 5, minute: 0, timeZone: tehranTZ)
        let baseSnapshot = WidgetSnapshot(
            generatedAt: t0,
            location: .tehran,
            timeZoneIdentifier: tehranTZ.identifier,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            upcomingOccasions: []
        )
        let baseSettings = AppSettings.default
        let baseFingerprint = WidgetFingerprint(snapshot: baseSnapshot, settings: baseSettings)

        // Initial nil previous -> should reload.
        #expect(WidgetReloadPolicy.shouldReload(previous: nil, next: baseFingerprint) == true)

        // Pure generatedAt change & boundary-only refresh on same day -> false.
        let boundarySnapshot = WidgetSnapshot(
            generatedAt: t0.addingTimeInterval(7 * 3600),
            location: .tehran,
            timeZoneIdentifier: tehranTZ.identifier,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            upcomingOccasions: []
        )
        let boundaryFingerprint = WidgetFingerprint(snapshot: boundarySnapshot, settings: baseSettings)
        #expect(WidgetReloadPolicy.shouldReload(previous: baseFingerprint, next: boundaryFingerprint) == false)

        // Adhan volume / mute / menu bar style change -> false.
        var nonWidgetSettings = baseSettings
        nonWidgetSettings.adhan.volume = 0.25
        nonWidgetSettings.adhan.mutedDateKey = "2025-03-21"
        nonWidgetSettings.menuBarLabelStyle = .iconOnly
        nonWidgetSettings.themeMode = .dark
        let nonWidgetFingerprint = WidgetFingerprint(snapshot: baseSnapshot, settings: nonWidgetSettings)
        #expect(WidgetReloadPolicy.shouldReload(previous: baseFingerprint, next: nonWidgetFingerprint) == false)

        // Language change -> true.
        var langSettings = baseSettings
        langSettings.language = .english
        #expect(WidgetReloadPolicy.shouldReload(
            previous: baseFingerprint,
            next: WidgetFingerprint(snapshot: baseSnapshot, settings: langSettings)
        ) == true)

        // Accent color change -> true.
        var accentSettings = baseSettings
        accentSettings.accentColorHex = "#FF6B00"
        #expect(WidgetReloadPolicy.shouldReload(
            previous: baseFingerprint,
            next: WidgetFingerprint(snapshot: baseSnapshot, settings: accentSettings)
        ) == true)

        // Location change -> true.
        var locationSettings = baseSettings
        locationSettings.selectedLocation = berlinLocation
        #expect(WidgetReloadPolicy.shouldReload(
            previous: baseFingerprint,
            next: WidgetFingerprint(snapshot: baseSnapshot, settings: locationSettings)
        ) == true)

        // Prayer offset change -> true.
        var offsetSettings = baseSettings
        offsetSettings.prayerOffsets[.maghrib] = 3
        let shiftedToday = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran,
            offsets: offsetSettings.prayerOffsets
        )
        let offsetSnapshot = WidgetSnapshot(
            generatedAt: t0,
            location: .tehran,
            timeZoneIdentifier: tehranTZ.identifier,
            todaySchedule: shiftedToday,
            tomorrowSchedule: tomorrow,
            upcomingOccasions: []
        )
        #expect(WidgetReloadPolicy.shouldReload(
            previous: baseFingerprint,
            next: WidgetFingerprint(snapshot: offsetSnapshot, settings: offsetSettings)
        ) == true)
    }

    @Test("WidgetEntryModel exposes upcoming occasions, locale identifier, and deep links")
    func occasionsLocaleAndDeepLink() throws {
        let today = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 20),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let tomorrow = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let beforeNowruz = makeDate(year: 2025, month: 3, day: 20, hour: 12, minute: 0, timeZone: tehranTZ)

        let nowruz = Occasion(
            id: "jalali-nowruz-1",
            titleEn: "Nowruz",
            titleFa: "نوروز",
            calendarKey: OccasionCalendarKey(calendar: .jalali, month: 1, day: 1),
            isOfficialHoliday: true,
            isBundled: true
        )

        var settings = WidgetDisplaySettings(appSettings: .default)
        settings.language = .persian
        settings.usePersianDigits = false

        let model = WidgetEntryModel.build(
            location: .tehran,
            method: .tehran,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            snapshotOccasions: [nowruz],
            settings: settings,
            visiblePrayers: Prayer.defaultVisible,
            date: beforeNowruz,
            timeZone: tehranTZ,
            snapshotAge: 100
        )

        #expect(model.occasions?.isShowingUpcoming == true)
        #expect(model.occasions?.items.first?.title == "نوروز")
        #expect(model.occasions?.items.first?.relativeDateText == "فردا")
        #expect(model.localeIdentifier == "fa_IR@numbers=latn")

        #expect(WidgetDeepLink(url: WidgetDeepLink.panel.url) == .panel)
        #expect(WidgetDeepLink(url: WidgetDeepLink.prayer(.maghrib).url) == .prayer(.maghrib))
        #expect(WidgetDeepLink(url: URL(string: "https://example.com")!) == nil)
    }
}
