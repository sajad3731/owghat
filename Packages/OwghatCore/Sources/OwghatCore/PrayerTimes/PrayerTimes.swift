import Foundation

/// Hour and minute on a local calendar date, used for manual prayer time overrides.
public struct LocalTimeOfDay: Codable, Sendable, Equatable, Hashable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    /// Resolves this wall-clock time on the given Gregorian date components in the given time zone.
    public func date(on dateComponents: DateComponents, in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = hour
        merged.minute = minute
        merged.second = 0
        return calendar.date(from: merged)
    }
}

/// A resolved timestamp for a single prayer on a given day.
public struct PrayerTimeEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: Prayer { prayer }
    public let prayer: Prayer
    public let date: Date
    public let isOverridden: Bool
    public let appliedOffsetMinutes: Int

    public init(
        prayer: Prayer,
        date: Date,
        isOverridden: Bool = false,
        appliedOffsetMinutes: Int = 0
    ) {
        self.prayer = prayer
        self.date = date
        self.isOverridden = isOverridden
        self.appliedOffsetMinutes = appliedOffsetMinutes
    }
}

/// Origin of a computed daily prayer schedule.
public enum PrayerTimeSourceKind: String, Codable, Sendable, CaseIterable {
    case offline
    case online
    case hybrid
}

/// Minute difference (`online - offline`) when comparing offline calculation with online times.
public struct PrayerTimeComparison: Codable, Sendable, Equatable {
    public let minuteDifferences: [Prayer: Int]
    public let fetchedAt: Date

    public init(minuteDifferences: [Prayer: Int], fetchedAt: Date = Date()) {
        self.minuteDifferences = minuteDifferences
        self.fetchedAt = fetchedAt
    }
}

/// Canonical `YYYY-MM-DD` key helpers for Gregorian calendar dates.
public enum DateKeyFormatter {
    public static func key(for components: DateComponents) -> String {
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func key(for date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return key(for: components)
    }

    public static func components(from date: Date, in timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
}

/// Complete prayer schedule for a single local calendar day.
public struct DailyPrayerTimes: Codable, Sendable, Equatable {
    public let dateKey: String
    public let timeZoneIdentifier: String
    public let location: GeoLocation
    public let method: CalculationMethod
    public let entries: [Prayer: PrayerTimeEntry]
    public let source: PrayerTimeSourceKind
    public let comparison: PrayerTimeComparison?

    public init(
        dateKey: String,
        timeZoneIdentifier: String,
        location: GeoLocation,
        method: CalculationMethod,
        entries: [Prayer: PrayerTimeEntry],
        source: PrayerTimeSourceKind,
        comparison: PrayerTimeComparison? = nil
    ) {
        self.dateKey = dateKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.location = location
        self.method = method
        self.entries = entries
        self.source = source
        self.comparison = comparison
    }

    public func entry(for prayer: Prayer) -> PrayerTimeEntry? {
        entries[prayer]
    }

    public func time(for prayer: Prayer) -> Date? {
        entries[prayer]?.date
    }

    /// Returns entries in chronological prayer order, optionally filtered to a visible subset.
    public func orderedEntries(filteredBy visible: Set<Prayer>? = nil) -> [PrayerTimeEntry] {
        Prayer.allCases.compactMap { prayer in
            if let visible, !visible.contains(prayer) {
                return nil
            }
            return entries[prayer]
        }
    }
}
