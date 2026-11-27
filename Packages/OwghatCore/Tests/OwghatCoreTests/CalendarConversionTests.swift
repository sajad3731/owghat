import Foundation
import Testing
@testable import OwghatCore

@Suite("Jalali and Hijri Calendar Conversion")
struct CalendarConversionTests {
    private let converter = CalendarConverter()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!

    private func gregorianDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Nowruz 2025-03-21 converts to Jalali 1404/01/01")
    func jalaliNowruzConversion() {
        let nowruz = gregorianDate(2025, 3, 21)
        let jalali = converter.convertedDate(
            for: nowruz,
            calendarType: .jalali,
            timeZone: tehranTZ,
            language: .persian
        )
        #expect(jalali.year == 1404)
        #expect(jalali.month == 1)
        #expect(jalali.day == 1)
        #expect(jalali.formattedNumeric(persianDigits: true) == "۱۴۰۴/۰۱/۰۱")

        // Previous day is 1403/12/30 (1403 is a Persian leap year)
        let leapDay = gregorianDate(2025, 3, 20)
        let jalaliLeap = converter.convertedDate(
            for: leapDay,
            calendarType: .jalali,
            timeZone: tehranTZ,
            language: .english
        )
        #expect(jalaliLeap.year == 1403)
        #expect(jalaliLeap.month == 12)
        #expect(jalaliLeap.day == 30)
    }

    @Test("Hijri day offset shifts Hijri date across month boundaries while keeping weekday invariant")
    func hijriOffsetAndWeekday() {
        let sample = gregorianDate(2025, 3, 1) // Ramadan 1, 1446 in Umm al-Qura
        let baseHijri = converter.convertedDate(
            for: sample,
            calendarType: .hijri,
            timeZone: tehranTZ,
            hijriVariant: .ummAlQura,
            hijriDayOffset: 0,
            language: .english
        )
        let minusOne = converter.convertedDate(
            for: sample,
            calendarType: .hijri,
            timeZone: tehranTZ,
            hijriVariant: .ummAlQura,
            hijriDayOffset: -1,
            language: .english
        )
        let plusOne = converter.convertedDate(
            for: sample,
            calendarType: .hijri,
            timeZone: tehranTZ,
            hijriVariant: .ummAlQura,
            hijriDayOffset: 1,
            language: .english
        )

        #expect(baseHijri.year == 1446)
        #expect(baseHijri.month == 9)
        #expect(baseHijri.day == 1)

        // -1 day rolls back into Sha'ban 1446
        #expect(minusOne.year == 1446)
        #expect(minusOne.month == 8)
        #expect(minusOne.day >= 29)

        // +1 day advances to Ramadan 2
        #expect(plusOne.month == 9)
        #expect(plusOne.day == 2)

        // Weekday must remain Saturday across moon-sighting adjustments
        #expect(minusOne.weekday == baseHijri.weekday)
        #expect(plusOne.weekday == baseHijri.weekday)
        #expect(minusOne.weekdayName == baseHijri.weekdayName)
    }

    @Test("DigitFormatter converts between Persian and Latin numerals")
    func digitConversion() {
        #expect(DigitFormatter.toPersian("Maghrib −00:42") == "Maghrib −۰۰:۴۲")
        #expect(DigitFormatter.toLatin("۱۲:۳۴") == "12:34")
    }
}
