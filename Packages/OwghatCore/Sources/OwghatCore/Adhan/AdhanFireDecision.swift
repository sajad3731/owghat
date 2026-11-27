import Foundation

/// Execution decision when a scheduled Adhan or reminder timer fires at wall-clock `now`.
public enum AdhanFireDecision: Sendable, Equatable {
    case play
    case notifyMissed
    case skip

    public static let defaultGraceWindow: TimeInterval = 90

    /// Evaluates whether an event firing at `now` is within the grace window or stale after sleep.
    public static func evaluate(
        event: AdhanEvent,
        now: Date,
        graceWindow: TimeInterval = defaultGraceWindow,
        notificationsEnabled: Bool = true
    ) -> AdhanFireDecision {
        let lateness = now.timeIntervalSince(event.fireDate)
        if lateness <= graceWindow {
            switch event.kind {
            case .adhan:
                if event.audio != nil || (event.postsNotification && notificationsEnabled) {
                    return .play
                }
                return .skip
            case .reminder:
                return (event.postsNotification && notificationsEnabled) ? .play : .skip
            }
        }

        switch event.kind {
        case .adhan:
            return notificationsEnabled ? .notifyMissed : .skip
        case .reminder:
            return .skip
        }
    }
}
