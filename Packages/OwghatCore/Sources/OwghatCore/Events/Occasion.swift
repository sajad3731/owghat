import Foundation

/// Date key matching either a yearly recurring day or a specific one-off date in a calendar.
public struct OccasionCalendarKey: Codable, Sendable, Equatable, Hashable {
    public var calendar: OwghatCalendarType
    public var month: Int
    public var day: Int
    /// Non-nil for one-off events; `nil` for yearly recurring occasions.
    public var year: Int?

    public init(calendar: OwghatCalendarType, month: Int, day: Int, year: Int? = nil) {
        self.calendar = calendar
        self.month = month
        self.day = day
        self.year = year
    }

    public func matches(_ converted: ConvertedDate) -> Bool {
        guard converted.calendarType == calendar,
              converted.month == month,
              converted.day == day else {
            return false
        }
        if let year {
            return converted.year == year
        }
        return true
    }
}

/// Religious occasion, official holiday, or user-created event.
public struct Occasion: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public var titleEn: String
    public var titleFa: String
    public var calendarKey: OccasionCalendarKey
    public var isOfficialHoliday: Bool
    public let isBundled: Bool
    public var isHidden: Bool
    public var hasReminder: Bool
    public var reminderMinutesBefore: Int?

    public init(
        id: String,
        titleEn: String,
        titleFa: String,
        calendarKey: OccasionCalendarKey,
        isOfficialHoliday: Bool = false,
        isBundled: Bool = false,
        isHidden: Bool = false,
        hasReminder: Bool = false,
        reminderMinutesBefore: Int? = nil
    ) {
        self.id = id
        self.titleEn = titleEn
        self.titleFa = titleFa
        self.calendarKey = calendarKey
        self.isOfficialHoliday = isOfficialHoliday
        self.isBundled = isBundled
        self.isHidden = isHidden
        self.hasReminder = hasReminder
        self.reminderMinutesBefore = reminderMinutesBefore
    }

    public func localizedTitle(for language: AppLanguage) -> String {
        switch language {
        case .persian: return titleFa.isEmpty ? titleEn : titleFa
        case .english: return titleEn.isEmpty ? titleFa : titleEn
        }
    }
}

/// Resolved occasion instance paired with its Gregorian date.
public struct DatedOccasion: Sendable, Equatable, Identifiable {
    public var id: String { "\(occasion.id)-\(dateKey)" }
    public let date: Date
    public let dateKey: String
    public let occasion: Occasion

    public init(date: Date, dateKey: String, occasion: Occasion) {
        self.date = date
        self.dateKey = dateKey
        self.occasion = occasion
    }
}
