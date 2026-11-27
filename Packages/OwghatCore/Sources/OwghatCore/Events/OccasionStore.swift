import Foundation

/// Combines bundled occasions with user edits, hidden flags, and custom events.
public struct OccasionStore: Sendable {
    public let bundledOccasions: [Occasion]
    private let converter: CalendarConverter

    public init(
        bundledOccasions: [Occasion]? = nil,
        converter: CalendarConverter = CalendarConverter()
    ) {
        self.bundledOccasions = bundledOccasions ?? Self.loadBundledOccasions()
        self.converter = converter
    }

    /// Merges bundled occasions with user overrides (`editedBundledOccasions`) and custom events.
    public func effectiveOccasions(settings: AppSettings, includeHidden: Bool = false) -> [Occasion] {
        let overrideMap = Dictionary(uniqueKeysWithValues: settings.editedBundledOccasions.map { ($0.id, $0) })
        let mergedBundled = bundledOccasions.map { overrideMap[$0.id] ?? $0 }
        let all = mergedBundled + settings.customOccasions
        return includeHidden ? all : all.filter { !$0.isHidden }
    }

    /// Returns occasions occurring on the specified date.
    public func occasions(
        on date: Date,
        timeZone: TimeZone,
        settings: AppSettings
    ) -> [Occasion] {
        let dates = converter.allDates(
            for: date,
            timeZone: timeZone,
            hijriVariant: settings.hijriVariant,
            hijriDayOffset: settings.hijriDayOffset,
            language: settings.language
        )

        return effectiveOccasions(settings: settings).filter { occasion in
            switch occasion.calendarKey.calendar {
            case .jalali:
                return occasion.calendarKey.matches(dates.jalali)
            case .hijri:
                return occasion.calendarKey.matches(dates.hijri)
            case .gregorian:
                return occasion.calendarKey.matches(dates.gregorian)
            }
        }
    }

    /// Returns occasions within the next `days` days starting from `startDate`.
    public func upcomingOccasions(
        from startDate: Date,
        days: Int,
        timeZone: TimeZone,
        settings: AppSettings
    ) -> [DatedOccasion] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone

        var results: [DatedOccasion] = []
        for offset in 0..<max(0, days) {
            guard let dayDate = gregorian.date(byAdding: .day, value: offset, to: startDate) else {
                continue
            }
            let key = DateKeyFormatter.key(for: dayDate, in: timeZone)
            for occasion in occasions(on: dayDate, timeZone: timeZone, settings: settings) {
                results.append(DatedOccasion(date: dayDate, dateKey: key, occasion: occasion))
            }
        }
        return results
    }

    private static func loadBundledOccasions() -> [Occasion] {
        guard let url = Bundle.module.url(forResource: "occasions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Occasion].self, from: data) else {
            return []
        }
        return decoded
    }
}
