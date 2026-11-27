import Foundation

/// Snapshot of a pending `UNNotificationRequest` mapped into a `Sendable` Core type.
public struct PendingNotificationSnapshot: Sendable, Equatable, Hashable {
    public let id: String
    public let fireDate: Date?
    public let hasSound: Bool
    public let willPlayAudio: Bool

    public init(id: String, fireDate: Date?, hasSound: Bool, willPlayAudio: Bool = false) {
        self.id = id
        self.fireDate = fireDate
        self.hasSound = hasSound
        self.willPlayAudio = willPlayAudio
    }
}

/// Desired system notification derived from an `AdhanEvent`.
public struct PlannedNotification: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let event: AdhanEvent
    public let fireDate: Date
    public let hasSound: Bool
    public let willPlayAudio: Bool

    public init(id: String, event: AdhanEvent) {
        self.id = id
        self.event = event
        self.fireDate = event.fireDate
        self.hasSound = event.notificationSound
        self.willPlayAudio = event.audio != nil
    }
}

/// Minimal diff between currently pending system notifications and desired `AdhanEvent` alerts.
public struct NotificationPlan: Sendable, Equatable {
    public static let defaultMaxPendingCount = 48
    public static let managedPrefix = "owghat-"
    public static let adhanRequestPrefix = "owghat-adhan-"
    public static let reminderRequestPrefix = "owghat-reminder-"
    public static let snoozeRequestPrefix = "owghat-snooze-"
    public static let missedRequestPrefix = "owghat-missed-"

    public let toKeep: [String]
    public let toAdd: [PlannedNotification]
    public let toRemove: [String]

    public init(toKeep: [String], toAdd: [PlannedNotification], toRemove: [String]) {
        self.toKeep = toKeep
        self.toAdd = toAdd
        self.toRemove = toRemove
    }

    /// Date components for a `UNCalendarNotificationTrigger` firing at the absolute instant `fireDate`.
    ///
    /// The trigger reads its components in the system calendar and time zone, not in the selected
    /// location's zone, so the components are built in the system zone (Gregorian) and carry that
    /// calendar and zone explicitly. A system time zone change re-arms all notifications.
    /// Known limit of calendar triggers: an instant inside the repeated hour of a DST fall-back
    /// in the system zone may resolve to the first occurrence (one hour early).
    public static func triggerComponents(
        for fireDate: Date,
        systemTimeZone: TimeZone = .autoupdatingCurrent
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = systemTimeZone
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        components.calendar = calendar
        components.timeZone = systemTimeZone
        return components
    }

    public static func requestIdentifier(for event: AdhanEvent) -> String {
        "\(managedPrefix)\(event.id)"
    }

    /// Returns true only for recurring planner-owned requests (never snoozes or missed-alert logs).
    public static func isManagedIdentifier(_ identifier: String) -> Bool {
        if identifier.hasPrefix(snoozeRequestPrefix) || identifier.hasPrefix(missedRequestPrefix) {
            return false
        }
        return identifier.hasPrefix(adhanRequestPrefix)
            || identifier.hasPrefix(reminderRequestPrefix)
            || isLegacyScheduledIdentifier(identifier)
    }

    private static func isLegacyScheduledIdentifier(_ identifier: String) -> Bool {
        guard identifier.hasPrefix(managedPrefix) else { return false }
        let remainder = identifier.dropFirst(managedPrefix.count)
        return remainder.first?.isNumber == true
    }

    /// Computes which pending notifications to keep, add, or remove while enforcing `maxPendingCount`
    /// and leaving `owghat-snooze-*` requests untouched.
    public static func build(
        events: [AdhanEvent],
        pendingRequests: [PendingNotificationSnapshot],
        maxPendingCount: Int = defaultMaxPendingCount
    ) -> NotificationPlan {
        let cap = max(0, maxPendingCount)
        let desired = events
            .filter(\.postsNotification)
            .prefix(cap)
            .map { PlannedNotification(id: requestIdentifier(for: $0), event: $0) }

        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
        let pendingByID = Dictionary(uniqueKeysWithValues: pendingRequests.map { ($0.id, $0) })

        var toKeep: [String] = []
        var toAdd: [PlannedNotification] = []
        var toRemove: [String] = []

        for pending in pendingRequests where isManagedIdentifier(pending.id) {
            guard let target = desiredByID[pending.id] else {
                toRemove.append(pending.id)
                continue
            }
            if matches(pending: pending, desired: target) {
                toKeep.append(pending.id)
            } else {
                toRemove.append(pending.id)
            }
        }

        let keptSet = Set(toKeep)
        for target in desired where !keptSet.contains(target.id) {
            if pendingByID[target.id] == nil || toRemove.contains(target.id) {
                toAdd.append(target)
            }
        }

        return NotificationPlan(
            toKeep: toKeep,
            toAdd: toAdd,
            toRemove: toRemove
        )
    }

    private static func matches(pending: PendingNotificationSnapshot, desired: PlannedNotification) -> Bool {
        guard let pendingDate = pending.fireDate else { return false }
        return abs(pendingDate.timeIntervalSince(desired.fireDate)) < 1.0
            && pending.hasSound == desired.hasSound
            && pending.willPlayAudio == desired.willPlayAudio
    }
}
