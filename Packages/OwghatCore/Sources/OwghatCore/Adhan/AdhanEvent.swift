import Foundation

/// Kind of scheduled Adhan-related alert.
public enum AdhanEventKind: Sendable, Equatable, Hashable {
    case adhan
    case reminder(minutesBefore: Int)
}

/// Pure, scheduled Adhan or pre-Adhan reminder event derived from prayer schedules and settings.
public struct AdhanEvent: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let kind: AdhanEventKind
    public let prayer: Prayer
    public let dateKey: String
    public let fireDate: Date
    /// Audio clip to play in-app; `nil` indicates notification-only.
    public let audio: PrayerAudioChoice?
    public let playsDoa: Bool
    public let postsNotification: Bool
    public let notificationSound: Bool

    public init(
        id: String,
        kind: AdhanEventKind,
        prayer: Prayer,
        dateKey: String,
        fireDate: Date,
        audio: PrayerAudioChoice?,
        playsDoa: Bool,
        postsNotification: Bool,
        notificationSound: Bool
    ) {
        self.id = id
        self.kind = kind
        self.prayer = prayer
        self.dateKey = dateKey
        self.fireDate = fireDate
        self.audio = audio
        self.playsDoa = playsDoa
        self.postsNotification = postsNotification
        self.notificationSound = notificationSound
    }

    public static func stableID(kind: AdhanEventKind, dateKey: String, prayer: Prayer) -> String {
        switch kind {
        case .adhan:
            return "adhan-\(dateKey)-\(prayer.rawValue)"
        case .reminder(let minutesBefore):
            return "reminder-\(dateKey)-\(prayer.rawValue)-\(minutesBefore)"
        }
    }
}
