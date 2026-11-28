import Foundation

/// Plans sorted, deduplicated WidgetKit timeline dates from `now` through the end of tomorrow.
public enum WidgetTimelinePlanner {
    /// Minimum interval in seconds preserved between consecutive timeline entries.
    public static let minimumEntrySpacing: TimeInterval = 1.0

    /// Returns sorted timeline boundary timestamps spanning from `now` through `00:00` after tomorrow
    /// in `timeZone`, including visible prayer boundaries across yesterday/today/tomorrow and local midnights.
    public static func timelineDates(
        todaySchedule: DailyPrayerTimes?,
        tomorrowSchedule: DailyPrayerTimes?,
        yesterdaySchedule: DailyPrayerTimes? = nil,
        visiblePrayers: Set<Prayer>,
        timeZone: TimeZone,
        now: Date
    ) -> [Date] {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone

        let startOfToday = gregorian.startOfDay(for: now)
        let startOfTomorrow = gregorian.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(86_400)
        let endOfTomorrow = gregorian.date(byAdding: .day, value: 2, to: startOfToday)
            ?? now.addingTimeInterval(172_800)

        var candidates: [Date] = [now, startOfTomorrow, endOfTomorrow]
        for schedule in [yesterdaySchedule, todaySchedule, tomorrowSchedule].compactMap({ $0 }) {
            for entry in schedule.orderedEntries(filteredBy: visiblePrayers) {
                candidates.append(entry.date)
            }
        }

        let sortedInWindow = candidates
            .filter { $0 >= now && $0 <= endOfTomorrow }
            .sorted()

        var deduplicated: [Date] = []
        deduplicated.reserveCapacity(sortedInWindow.count)
        for date in sortedInWindow {
            if let previous = deduplicated.last, date.timeIntervalSince(previous) < minimumEntrySpacing {
                continue
            }
            deduplicated.append(date)
        }
        return deduplicated
    }
}
