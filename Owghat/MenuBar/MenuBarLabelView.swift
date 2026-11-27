import OwghatCore
import SwiftUI

/// Timeline schedule aligned to top-of-minute boundaries and exact prayer transition instants.
struct MenuBarTimelineSchedule: TimelineSchedule, Sendable {
    let alignToMinutes: Bool
    let boundaryDates: [Date]

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(
            currentDate: startDate,
            alignToMinutes: alignToMinutes,
            boundaryDates: boundaryDates.sorted()
        )
    }

    struct Entries: Sequence, IteratorProtocol, Sendable {
        var currentDate: Date
        let alignToMinutes: Bool
        let boundaryDates: [Date]
        private var yieldedInitial = false

        init(currentDate: Date, alignToMinutes: Bool, boundaryDates: [Date]) {
            self.currentDate = currentDate
            self.alignToMinutes = alignToMinutes
            self.boundaryDates = boundaryDates
        }

        mutating func next() -> Date? {
            if !yieldedInitial {
                yieldedInitial = true
                return currentDate
            }

            let nextBoundary = boundaryDates.first { $0 > currentDate }
            let nextCandidate: Date?
            if alignToMinutes {
                let nextMinuteEpoch = (floor(currentDate.timeIntervalSince1970 / 60.0) + 1.0) * 60.0
                let nextMinute = Date(timeIntervalSince1970: nextMinuteEpoch)
                if let nextBoundary, nextBoundary < nextMinute {
                    nextCandidate = nextBoundary
                } else {
                    nextCandidate = nextMinute
                }
            } else {
                nextCandidate = nextBoundary
            }

            guard let nextDate = nextCandidate else {
                return nil
            }
            currentDate = nextDate
            return nextDate
        }
    }
}

/// Thin SwiftUI view rendering `MenuBarLabelFormatter` output as a single `Image` and `Text`.
struct MenuBarLabelView: View {
    let appState: AppState
    private let formatter = MenuBarLabelFormatter()

    var body: some View {
        TimelineView(timelineSchedule) { context in
            let content = labelContent(at: context.date)
            HStack(spacing: 4) {
                Image(systemName: content.symbolName)
                if let text = content.text {
                    Text(text)
                        .monospacedDigit()
                }
            }
        }
    }

    private var timelineSchedule: MenuBarTimelineSchedule {
        let style = appState.settings.menuBarLabelStyle
        let needsMinuteTicks = (style == .countdown || style == .nextPrayerAndCountdown)

        var boundaries: [Date] = []
        if let nextDate = appState.nextPrayer?.entry.date {
            boundaries.append(nextDate)
            boundaries.append(nextDate.addingTimeInterval(MenuBarLabelFormatter.boundaryBannerDuration))
        }
        if let reached = appState.justReachedEntry(at: Date()) {
            boundaries.append(reached.date.addingTimeInterval(MenuBarLabelFormatter.boundaryBannerDuration))
        }

        return MenuBarTimelineSchedule(
            alignToMinutes: needsMinuteTicks,
            boundaryDates: boundaries
        )
    }

    private func labelContent(at now: Date) -> MenuBarLabelContent {
        formatter.format(
            nextEntry: appState.nextPrayer?.entry,
            justReachedEntry: appState.justReachedEntry(at: now),
            now: now,
            style: appState.settings.menuBarLabelStyle,
            language: appState.settings.language,
            usePersianDigits: appState.settings.usePersianDigits,
            timeZone: appState.activeTimeZone,
            isMutedToday: appState.isMutedToday,
            isPlayingAdhan: appState.isPlayingAdhan
        )
    }
}
