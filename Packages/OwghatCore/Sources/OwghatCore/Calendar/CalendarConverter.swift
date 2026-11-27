import Foundation

/// Supported calendar systems across the app and custom occasions.
public enum OwghatCalendarType: String, Codable, Sendable, CaseIterable, Identifiable {
    case jalali
    case hijri
    case gregorian

    public var id: String { rawValue }
}

/// Supported Islamic Hijri calendar calculation bases.
public enum HijriCalendarVariant: String, Codable, Sendable, CaseIterable, Identifiable {
    case ummAlQura
    case islamicCivil

    public var id: String { rawValue }

    public var calendarIdentifier: Calendar.Identifier {
        switch self {
        case .ummAlQura: return .islamicUmmAlQura
        case .islamicCivil: return .islamicCivil
        }
    }
}

/// Converted date fields for a single calendar system.
public struct ConvertedDate: Sendable, Equatable, Hashable {
    public let calendarType: OwghatCalendarType
    public let year: Int
    public let month: Int
    public let day: Int
    public let weekday: Int
    public let monthName: String
    public let weekdayName: String

    public init(
        calendarType: OwghatCalendarType,
        year: Int,
        month: Int,
        day: Int,
        weekday: Int,
        monthName: String,
        weekdayName: String
    ) {
        self.calendarType = calendarType
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
        self.monthName = monthName
        self.weekdayName = weekdayName
    }

    /// Formats as e.g. `۱ فروردین ۱۴۰۴` or `21 March 2025`.
    public func formattedLong(persianDigits: Bool) -> String {
        let raw = "\(day) \(monthName) \(year)"
        return DigitFormatter.format(raw, persianDigits: persianDigits)
    }

    /// Formats as `YYYY/MM/DD`.
    public func formattedNumeric(persianDigits: Bool) -> String {
        let raw = String(format: "%04d/%02d/%02d", year, month, day)
        return DigitFormatter.format(raw, persianDigits: persianDigits)
    }
}

/// Bundle of Jalali, Hijri, and Gregorian representations for a single day.
public struct TripleCalendarDate: Sendable, Equatable {
    public let jalali: ConvertedDate
    public let hijri: ConvertedDate
    public let gregorian: ConvertedDate

    public init(jalali: ConvertedDate, hijri: ConvertedDate, gregorian: ConvertedDate) {
        self.jalali = jalali
        self.hijri = hijri
        self.gregorian = gregorian
    }
}

/// Converts instants to Jalali (Persian), Hijri (with moon-sighting offset), and Gregorian dates.
public struct CalendarConverter: Sendable {
    public init() {}

    public func convertedDate(
        for date: Date,
        calendarType: OwghatCalendarType,
        timeZone: TimeZone,
        hijriVariant: HijriCalendarVariant = .ummAlQura,
        hijriDayOffset: Int = 0,
        language: AppLanguage = .persian
    ) -> ConvertedDate {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone

        let baseComponents = gregorian.dateComponents([.year, .month, .day], from: date)
        let localNoon = gregorian.date(from: DateComponents(
            year: baseComponents.year,
            month: baseComponents.month,
            day: baseComponents.day,
            hour: 12
        )) ?? date

        let targetDate: Date
        if calendarType == .hijri && hijriDayOffset != 0 {
            targetDate = gregorian.date(byAdding: .day, value: hijriDayOffset, to: localNoon) ?? localNoon
        } else {
            targetDate = localNoon
        }

        let identifier: Calendar.Identifier = switch calendarType {
        case .jalali: .persian
        case .hijri: hijriVariant.calendarIdentifier
        case .gregorian: .gregorian
        }

        var targetCalendar = Calendar(identifier: identifier)
        targetCalendar.timeZone = timeZone
        let locale = Locale(identifier: language == .persian ? "fa_IR" : "en_US_POSIX")
        targetCalendar.locale = locale

        let parts = targetCalendar.dateComponents([.year, .month, .day], from: targetDate)
        let actualWeekday = gregorian.component(.weekday, from: localNoon)

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = targetCalendar
        monthFormatter.locale = locale
        monthFormatter.timeZone = timeZone
        monthFormatter.dateFormat = "MMMM"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = targetCalendar
        weekdayFormatter.locale = locale
        weekdayFormatter.timeZone = timeZone
        weekdayFormatter.dateFormat = "EEEE"

        return ConvertedDate(
            calendarType: calendarType,
            year: parts.year ?? 0,
            month: parts.month ?? 0,
            day: parts.day ?? 0,
            weekday: actualWeekday,
            monthName: monthFormatter.string(from: targetDate),
            weekdayName: weekdayFormatter.string(from: localNoon)
        )
    }

    public func allDates(
        for date: Date,
        timeZone: TimeZone,
        hijriVariant: HijriCalendarVariant = .ummAlQura,
        hijriDayOffset: Int = 0,
        language: AppLanguage = .persian
    ) -> TripleCalendarDate {
        TripleCalendarDate(
            jalali: convertedDate(
                for: date,
                calendarType: .jalali,
                timeZone: timeZone,
                hijriVariant: hijriVariant,
                hijriDayOffset: hijriDayOffset,
                language: language
            ),
            hijri: convertedDate(
                for: date,
                calendarType: .hijri,
                timeZone: timeZone,
                hijriVariant: hijriVariant,
                hijriDayOffset: hijriDayOffset,
                language: language
            ),
            gregorian: convertedDate(
                for: date,
                calendarType: .gregorian,
                timeZone: timeZone,
                hijriVariant: hijriVariant,
                hijriDayOffset: hijriDayOffset,
                language: language
            )
        )
    }
}
