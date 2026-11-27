import Foundation

/// Pure planner producing sorted Adhan and pre-Adhan reminder events across a multi-day horizon.
public struct AdhanPlanner: Sendable {
    public static let defaultHorizon: TimeInterval = 48 * 3600

    public init() {}

    /// Builds a chronological list of upcoming Adhan and reminder events within `horizon`.
    /// Ignores `visiblePrayers` so hidden prayers still schedule Adhan and alerts as configured.
    public func plan(
        schedules: [DailyPrayerTimes],
        settings: AdhanSettings,
        timeZone: TimeZone,
        now: Date,
        horizon: TimeInterval = AdhanPlanner.defaultHorizon
    ) -> [AdhanEvent] {
        let horizonEnd = now.addingTimeInterval(max(0, horizon))
        var events: [AdhanEvent] = []
        var seenIDs = Set<String>()

        let sortedSchedules = schedules.sorted { $0.dateKey < $1.dateKey }
        for schedule in sortedSchedules {
            let entries = schedule.orderedEntries(filteredBy: nil).filter { $0.prayer.isAdhanPrayer }
            for entry in entries {
                let adhanFireDate = entry.date
                let adhanMuted = settings.isMuted(on: adhanFireDate, timeZone: timeZone)

                let configuredAudio = settings.audioPerPrayer[entry.prayer] ?? .none
                let resolvedAudio: PrayerAudioChoice? = (!adhanMuted && configuredAudio != .none)
                    ? configuredAudio
                    : nil

                let adhanPostsNotification: Bool
                let adhanNotificationSound: Bool
                if adhanMuted {
                    adhanPostsNotification = settings.notificationsEnabled && settings.silentNotificationsOnMutedDays
                    adhanNotificationSound = false
                } else {
                    adhanPostsNotification = settings.notificationsEnabled
                    adhanNotificationSound = settings.notificationsEnabled
                }

                let adhanActive = (resolvedAudio != nil) || adhanPostsNotification
                guard adhanActive else { continue }

                if adhanFireDate > now && adhanFireDate <= horizonEnd {
                    let adhanID = AdhanEvent.stableID(
                        kind: .adhan,
                        dateKey: schedule.dateKey,
                        prayer: entry.prayer
                    )
                    if seenIDs.insert(adhanID).inserted {
                        events.append(
                            AdhanEvent(
                                id: adhanID,
                                kind: .adhan,
                                prayer: entry.prayer,
                                dateKey: schedule.dateKey,
                                fireDate: adhanFireDate,
                                audio: resolvedAudio,
                                playsDoa: (resolvedAudio != nil) && (settings.postAdhanDoaClip != .none),
                                postsNotification: adhanPostsNotification,
                                notificationSound: adhanNotificationSound
                            )
                        )
                    }
                }

                if let reminderMinutes = settings.preAdhanReminderMinutes, reminderMinutes > 0 {
                    let reminderDate = adhanFireDate.addingTimeInterval(TimeInterval(-reminderMinutes * 60))
                    if reminderDate > now && reminderDate <= horizonEnd {
                        let reminderMuted = settings.isMuted(on: reminderDate, timeZone: timeZone)
                        let reminderPostsNotification = settings.notificationsEnabled
                            && (!reminderMuted || settings.silentNotificationsOnMutedDays)
                        if reminderPostsNotification {
                            let reminderKind = AdhanEventKind.reminder(minutesBefore: reminderMinutes)
                            let reminderID = AdhanEvent.stableID(
                                kind: reminderKind,
                                dateKey: schedule.dateKey,
                                prayer: entry.prayer
                            )
                            if seenIDs.insert(reminderID).inserted {
                                events.append(
                                    AdhanEvent(
                                        id: reminderID,
                                        kind: reminderKind,
                                        prayer: entry.prayer,
                                        dateKey: schedule.dateKey,
                                        fireDate: reminderDate,
                                        audio: nil,
                                        playsDoa: false,
                                        postsNotification: true,
                                        notificationSound: !reminderMuted
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }

        return events.sorted { lhs, rhs in
            if lhs.fireDate != rhs.fireDate {
                return lhs.fireDate < rhs.fireDate
            }
            if lhs.kind != rhs.kind {
                if case .reminder = lhs.kind { return true }
                return false
            }
            return lhs.id < rhs.id
        }
    }
}
