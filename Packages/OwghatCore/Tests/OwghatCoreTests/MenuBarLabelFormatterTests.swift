import Foundation
import Testing
@testable import OwghatCore

@Suite("MenuBarLabelFormatter")
struct MenuBarLabelFormatterTests {
    private let formatter = MenuBarLabelFormatter()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int = 0, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    @Test("Formats all label styles across languages and digit systems")
    func labelStylesMatrix() {
        let maghribDate = makeDate(year: 2025, month: 3, day: 21, hour: 18, minute: 35, timeZone: tehranTZ)
        let now = maghribDate.addingTimeInterval(-42 * 60)
        let entry = PrayerTimeEntry(prayer: .maghrib, date: maghribDate)

        // iconOnly
        let iconFa = formatter.format(
            nextEntry: entry, now: now, style: .iconOnly,
            language: .persian, usePersianDigits: true, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(iconFa == MenuBarLabelContent(symbolName: "moon.stars", text: nil))

        // nextPrayerAndTime (en / Latin)
        let timeEn = formatter.format(
            nextEntry: entry, now: now, style: .nextPrayerAndTime,
            language: .english, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(timeEn.text == "Maghrib 18:35")

        // nextPrayerAndTime (fa / Persian)
        let timeFa = formatter.format(
            nextEntry: entry, now: now, style: .nextPrayerAndTime,
            language: .persian, usePersianDigits: true, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(timeFa.text == "اذان مغرب ۱۸:۳۵")

        // countdown (en / Latin)
        let countdownEn = formatter.format(
            nextEntry: entry, now: now, style: .countdown,
            language: .english, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(countdownEn.text == "−00:42")

        // countdown (fa / Persian)
        let countdownFa = formatter.format(
            nextEntry: entry, now: now, style: .countdown,
            language: .persian, usePersianDigits: true, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(countdownFa.text == "−۰۰:۴۲")

        // nextPrayerAndCountdown (en / Latin & fa / Latin digits)
        let bothEn = formatter.format(
            nextEntry: entry, now: now, style: .nextPrayerAndCountdown,
            language: .english, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(bothEn.text == "Maghrib −00:42")

        let bothFaLatin = formatter.format(
            nextEntry: entry, now: now, style: .nextPrayerAndCountdown,
            language: .persian, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        #expect(bothFaLatin.text == "اذان مغرب −00:42")
    }

    @Test("Rounds up under-minute intervals to -00:01 and shows prayer name for 60s at boundary")
    func roundingAndBoundaryWindow() {
        let maghribDate = makeDate(year: 2025, month: 3, day: 21, hour: 18, minute: 35, timeZone: tehranTZ)
        let maghribEntry = PrayerTimeEntry(prayer: .maghrib, date: maghribDate)
        let ishaDate = makeDate(year: 2025, month: 3, day: 21, hour: 19, minute: 22, timeZone: tehranTZ)
        let ishaEntry = PrayerTimeEntry(prayer: .isha, date: ishaDate)

        // 60.1s left -> -00:02
        let overMinute = formatter.format(
            nextEntry: maghribEntry,
            now: maghribDate.addingTimeInterval(-60.1),
            style: .countdown,
            language: .english,
            usePersianDigits: false,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(overMinute.text == "−00:02")

        // 59.9s left -> -00:01 (never -00:00)
        let almostMinute = formatter.format(
            nextEntry: maghribEntry,
            now: maghribDate.addingTimeInterval(-59.9),
            style: .countdown,
            language: .english,
            usePersianDigits: false,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(almostMinute.text == "−00:01")

        // 0.2s left -> -00:01 (never -00:00)
        let subSecond = formatter.format(
            nextEntry: maghribEntry,
            now: maghribDate.addingTimeInterval(-0.2),
            style: .nextPrayerAndCountdown,
            language: .persian,
            usePersianDigits: true,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(subSecond.text == "اذان مغرب −۰۰:۰۱")

        // Exactly 0s at boundary (direct nextEntry) -> shows prayer name
        let exactZeroEn = formatter.format(
            nextEntry: maghribEntry,
            now: maghribDate,
            style: .nextPrayerAndCountdown,
            language: .english,
            usePersianDigits: false,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(exactZeroEn.text == "Maghrib")

        // Within 60s after boundary when nextEntry already advanced to Isha -> shows Maghrib name
        let withinBannerFa = formatter.format(
            nextEntry: ishaEntry,
            justReachedEntry: maghribEntry,
            now: maghribDate.addingTimeInterval(35),
            style: .countdown,
            language: .persian,
            usePersianDigits: true,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(withinBannerFa.text == "اذان مغرب")

        // At +60s after boundary -> switches to next prayer countdown
        let afterBanner = formatter.format(
            nextEntry: ishaEntry,
            justReachedEntry: maghribEntry,
            now: maghribDate.addingTimeInterval(60),
            style: .nextPrayerAndCountdown,
            language: .english,
            usePersianDigits: false,
            timeZone: tehranTZ,
            isMutedToday: false,
            isPlayingAdhan: false
        )
        #expect(afterBanner.text == "Isha −00:46")
    }

    @Test("Selects distinct symbols for muted and playing states and preserves HH:MM padding")
    func symbolsAndPadding() {
        let fajrDate = makeDate(year: 2025, month: 3, day: 21, hour: 4, minute: 43, timeZone: tehranTZ)
        let entry = PrayerTimeEntry(prayer: .fajr, date: fajrDate)
        let now = fajrDate.addingTimeInterval(-(4 * 3600 + 5 * 60))

        let muted = formatter.format(
            nextEntry: entry, now: now, style: .countdown,
            language: .english, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: true, isPlayingAdhan: false
        )
        #expect(muted.symbolName == "bell.slash")
        #expect(muted.text == "−04:05")

        // Playing takes visual precedence over muted state
        let playing = formatter.format(
            nextEntry: entry, now: now, style: .nextPrayerAndTime,
            language: .english, usePersianDigits: false, timeZone: tehranTZ,
            isMutedToday: true, isPlayingAdhan: true
        )
        #expect(playing.symbolName == "speaker.wave.2.fill")
        #expect(playing.text == "Fajr 04:43")
    }

    @Test("Accounts for Europe/Berlin spring-forward DST in countdown width and value")
    func berlinDstCountdown() {
        // 2025-03-30 Europe/Berlin springs forward at 02:00 CET -> 03:00 CEST.
        let fajrDate = makeDate(year: 2025, month: 3, day: 30, hour: 5, minute: 0, timeZone: berlinTZ)
        let beforeDst = makeDate(year: 2025, month: 3, day: 30, hour: 1, minute: 30, timeZone: berlinTZ)
        let entry = PrayerTimeEntry(prayer: .fajr, date: fajrDate)

        let label = formatter.format(
            nextEntry: entry, now: beforeDst, style: .nextPrayerAndCountdown,
            language: .english, usePersianDigits: false, timeZone: berlinTZ,
            isMutedToday: false, isPlayingAdhan: false
        )
        // Physical elapsed time from 01:30 CET to 05:00 CEST is 2h 30m (not 3h 30m).
        #expect(label.text == "Fajr −02:30")
    }
}
