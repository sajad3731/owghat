import Foundation

/// Resolved next prayer event and remaining duration from a reference instant.
public struct NextPrayerResolution: Sendable, Equatable {
    public let entry: PrayerTimeEntry
    public let remainingInterval: TimeInterval

    public init(entry: PrayerTimeEntry, remainingInterval: TimeInterval) {
        self.entry = entry
        self.remainingInterval = max(0, remainingInterval)
    }

    /// Formats the countdown as `−HH:mm` (or `−HH:mm:ss` when `includeSeconds` is true).
    public func formattedCountdown(
        persianDigits: Bool,
        includeSeconds: Bool = false,
        includeMinusPrefix: Bool = true
    ) -> String {
        let totalSeconds = max(0, Int(remainingInterval.rounded(.up)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        let raw: String
        if includeSeconds {
            raw = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            let roundedMinutesTotal = max(0, Int(ceil(remainingInterval / 60.0)))
            let displayHours = roundedMinutesTotal / 60
            let displayMinutes = roundedMinutesTotal % 60
            raw = String(format: "%02d:%02d", displayHours, displayMinutes)
        }

        let prefixed = includeMinusPrefix ? "−\(raw)" : raw
        return persianDigits ? DigitFormatter.toPersian(prefixed) : prefixed
    }
}

/// Computes upcoming prayers across midnight boundaries and DST transitions.
public struct PrayerTimeResolver: Sendable {
    public init() {}

    /// Finds the earliest visible prayer strictly after `referenceDate` from pre-fetched daily schedules.
    public func nextPrayer(
        at referenceDate: Date,
        schedules: [DailyPrayerTimes],
        visiblePrayers: Set<Prayer>
    ) -> NextPrayerResolution? {
        let upcomingEntries = schedules.flatMap { schedule in
            schedule.orderedEntries(filteredBy: visiblePrayers).filter { $0.date > referenceDate }
        }
        guard let next = upcomingEntries.min(by: { $0.date < $1.date }) else {
            return nil
        }
        return NextPrayerResolution(
            entry: next,
            remainingInterval: next.date.timeIntervalSince(referenceDate)
        )
    }

    /// Finds the earliest visible prayer strictly after `referenceDate` across yesterday, today, and tomorrow.
    public func nextPrayer(
        at referenceDate: Date,
        location: GeoLocation,
        timeZone: TimeZone,
        settings: AppSettings,
        provider: any PrayerTimesProvider = OfflinePrayerTimesProvider()
    ) async throws -> NextPrayerResolution? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone

        let todayComponents = gregorian.dateComponents([.year, .month, .day], from: referenceDate)
        guard let anchorNoon = gregorian.date(from: DateComponents(
            year: todayComponents.year,
            month: todayComponents.month,
            day: todayComponents.day,
            hour: 12
        )) else {
            return nil
        }

        let candidateDays = [-1, 0, 1].compactMap { offset -> DateComponents? in
            guard let shifted = gregorian.date(byAdding: .day, value: offset, to: anchorNoon) else {
                return nil
            }
            return gregorian.dateComponents([.year, .month, .day], from: shifted)
        }

        var schedules: [DailyPrayerTimes] = []
        for dayComponents in candidateDays {
            let schedule = try await provider.prayerTimes(
                for: dayComponents,
                location: location,
                timeZone: timeZone,
                settings: settings
            )
            schedules.append(schedule)
        }

        return nextPrayer(at: referenceDate, schedules: schedules, visiblePrayers: settings.visiblePrayers)
    }
}
