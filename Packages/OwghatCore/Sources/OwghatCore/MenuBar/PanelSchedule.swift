import Foundation

/// Temporal state of a prayer row relative to the current time.
public enum PrayerRowState: String, Sendable, Equatable, CaseIterable {
    case passed
    case next
    case upcoming
}

/// Display-ready row in the menu bar panel prayer list.
public struct PanelPrayerRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let prayer: Prayer
    public let title: String
    public let date: Date
    public let formattedTime: String
    public let state: PrayerRowState
    public let isTomorrow: Bool
    public let isOverridden: Bool
    public let appliedOffsetMinutes: Int
    public let accessibilityLabel: String

    public init(
        id: String,
        prayer: Prayer,
        title: String,
        date: Date,
        formattedTime: String,
        state: PrayerRowState,
        isTomorrow: Bool,
        isOverridden: Bool,
        appliedOffsetMinutes: Int,
        accessibilityLabel: String
    ) {
        self.id = id
        self.prayer = prayer
        self.title = title
        self.date = date
        self.formattedTime = formattedTime
        self.state = state
        self.isTomorrow = isTomorrow
        self.isOverridden = isOverridden
        self.appliedOffsetMinutes = appliedOffsetMinutes
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Pure, display-ready schedule and countdown ring state for the menu bar panel.
public struct PanelSchedule: Sendable, Equatable {
    public let rows: [PanelPrayerRow]
    public let nextRow: PanelPrayerRow?
    public let justReachedEntry: PrayerTimeEntry?
    public let previousBoundaryDate: Date?
    public let progress: Double
    public let nextBannerTitle: String?
    public let liveCountdownText: String

    public init(
        rows: [PanelPrayerRow],
        nextRow: PanelPrayerRow?,
        justReachedEntry: PrayerTimeEntry?,
        previousBoundaryDate: Date?,
        progress: Double,
        nextBannerTitle: String?,
        liveCountdownText: String
    ) {
        self.rows = rows
        self.nextRow = nextRow
        self.justReachedEntry = justReachedEntry
        self.previousBoundaryDate = previousBoundaryDate
        self.progress = progress
        self.nextBannerTitle = nextBannerTitle
        self.liveCountdownText = liveCountdownText
    }

    /// Computes ordered prayer rows, active highlight, countdown string, and circular ring progress at `now`.
    public static func build(
        todaySchedule: DailyPrayerTimes?,
        tomorrowSchedule: DailyPrayerTimes?,
        yesterdaySchedule: DailyPrayerTimes? = nil,
        visiblePrayers: Set<Prayer>,
        now: Date,
        timeZone: TimeZone,
        language: AppLanguage,
        usePersianDigits: Bool
    ) -> PanelSchedule {
        let yesterdayEntries = yesterdaySchedule?.orderedEntries(filteredBy: visiblePrayers) ?? []
        let todayEntries = todaySchedule?.orderedEntries(filteredBy: visiblePrayers) ?? []
        let tomorrowEntries = tomorrowSchedule?.orderedEntries(filteredBy: visiblePrayers) ?? []

        let taggedEntries: [(entry: PrayerTimeEntry, isTomorrow: Bool, idPrefix: String)] =
            yesterdayEntries.map { ($0, false, "yesterday") }
            + todayEntries.map { ($0, false, "today") }
            + tomorrowEntries.map { ($0, true, "tomorrow") }

        let nextCandidate = taggedEntries
            .filter { $0.entry.date > now }
            .min { $0.entry.date < $1.entry.date }

        let justReachedCandidate = taggedEntries
            .filter { item in
                let elapsed = now.timeIntervalSince(item.entry.date)
                return elapsed >= 0 && elapsed < MenuBarLabelFormatter.boundaryBannerDuration
            }
            .max { $0.entry.date < $1.entry.date }

        // Build rows: always include today's visible entries; if next is yesterday's post-midnight
        // or tomorrow's prayer, include that entry with its proper state and marker.
        var displayItems: [(entry: PrayerTimeEntry, isTomorrow: Bool, idPrefix: String)] = []

        if let nextCandidate, nextCandidate.idPrefix == "yesterday" {
            displayItems.append(nextCandidate)
        }
        displayItems.append(contentsOf: todayEntries.map { ($0, false, "today") })
        if let nextCandidate, nextCandidate.idPrefix == "tomorrow" {
            displayItems.append(nextCandidate)
        }

        let rows: [PanelPrayerRow] = displayItems.map { item in
            let isNext = isSameEntry(item.entry, nextCandidate?.entry)
            let state: PrayerRowState
            if isNext {
                state = .next
            } else if item.entry.date <= now {
                state = .passed
            } else {
                state = .upcoming
            }

            let title = item.entry.prayer.localizedName(for: language)
            let formattedTime = DigitFormatter.formatTime(
                item.entry.date,
                timeZone: timeZone,
                persianDigits: usePersianDigits
            )
            let a11y = makeAccessibilityLabel(
                title: title,
                formattedTime: formattedTime,
                state: state,
                isTomorrow: item.isTomorrow,
                isOverridden: item.entry.isOverridden,
                language: language
            )

            return PanelPrayerRow(
                id: "\(item.idPrefix)-\(item.entry.prayer.rawValue)",
                prayer: item.entry.prayer,
                title: title,
                date: item.entry.date,
                formattedTime: formattedTime,
                state: state,
                isTomorrow: item.isTomorrow,
                isOverridden: item.entry.isOverridden,
                appliedOffsetMinutes: item.entry.appliedOffsetMinutes,
                accessibilityLabel: a11y
            )
        }

        let nextRow = rows.first { $0.state == .next }

        let previousBoundary = taggedEntries
            .map(\.entry.date)
            .filter { $0 <= now }
            .max()
            ?? startOfDay(for: now, in: timeZone)

        let progress: Double
        if let nextRow {
            let total = nextRow.date.timeIntervalSince(previousBoundary)
            let elapsed = now.timeIntervalSince(previousBoundary)
            if total <= 0 {
                progress = 1.0
            } else {
                progress = min(1.0, max(0.0, elapsed / total))
            }
        } else {
            progress = 0.0
        }

        let nextBannerTitle: String?
        if let nextRow {
            if nextRow.isTomorrow {
                let tomorrowWord = language == .persian ? "فردا" : "Tomorrow"
                nextBannerTitle = "\(tomorrowWord) · \(nextRow.title)"
            } else {
                nextBannerTitle = nextRow.title
            }
        } else {
            nextBannerTitle = nil
        }

        let liveCountdownText: String
        if let nextRow {
            let resolution = NextPrayerResolution(
                entry: PrayerTimeEntry(
                    prayer: nextRow.prayer,
                    date: nextRow.date,
                    isOverridden: nextRow.isOverridden,
                    appliedOffsetMinutes: nextRow.appliedOffsetMinutes
                ),
                remainingInterval: nextRow.date.timeIntervalSince(now)
            )
            liveCountdownText = resolution.formattedCountdown(
                persianDigits: usePersianDigits,
                includeSeconds: true,
                includeMinusPrefix: false
            )
        } else {
            liveCountdownText = DigitFormatter.format("00:00:00", persianDigits: usePersianDigits)
        }

        return PanelSchedule(
            rows: rows,
            nextRow: nextRow,
            justReachedEntry: justReachedCandidate?.entry,
            previousBoundaryDate: previousBoundary,
            progress: progress,
            nextBannerTitle: nextBannerTitle,
            liveCountdownText: liveCountdownText
        )
    }

    private static func isSameEntry(_ lhs: PrayerTimeEntry, _ rhs: PrayerTimeEntry?) -> Bool {
        guard let rhs else { return false }
        return lhs.prayer == rhs.prayer && abs(lhs.date.timeIntervalSince(rhs.date)) < 1.0
    }

    private static func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    private static func makeAccessibilityLabel(
        title: String,
        formattedTime: String,
        state: PrayerRowState,
        isTomorrow: Bool,
        isOverridden: Bool,
        language: AppLanguage
    ) -> String {
        let stateText: String = switch (state, language) {
        case (.passed, .persian): "گذشته"
        case (.passed, .english): "passed"
        case (.next, .persian): "وقت بعدی"
        case (.next, .english): "next"
        case (.upcoming, .persian): "پیشِ رو"
        case (.upcoming, .english): "upcoming"
        }

        var parts: [String] = []
        if isTomorrow {
            parts.append(language == .persian ? "فردا" : "Tomorrow")
        }
        parts.append(title)
        parts.append(formattedTime)
        parts.append(stateText)
        if isOverridden {
            parts.append(language == .persian ? "تغییر دستی" : "manual override")
        }
        let separator = language == .persian ? "، " : ", "
        return parts.joined(separator: separator)
    }
}
