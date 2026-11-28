import Foundation

/// Comparable fingerprint capturing all snapshot and settings fields that affect widget rendering.
/// Volatile timestamps (`generatedAt`, comparison fetch times) and non-widget settings (Adhan audio,
/// volume, mute state, menu bar style, theme) are excluded so boundary refreshes and audio tweaks do
/// not consume WidgetKit reload budget.
public struct WidgetFingerprint: Sendable, Equatable, Hashable {
    public struct ScheduleSignature: Sendable, Equatable, Hashable {
        public let dateKey: String
        public let timeZoneIdentifier: String
        public let location: GeoLocation
        public let method: CalculationMethod
        public let entries: [Prayer: PrayerTimeEntry]
        public let source: PrayerTimeSourceKind
        public let minuteDifferences: [Prayer: Int]?

        public init(schedule: DailyPrayerTimes) {
            self.dateKey = schedule.dateKey
            self.timeZoneIdentifier = schedule.timeZoneIdentifier
            self.location = schedule.location
            self.method = schedule.method
            self.entries = schedule.entries
            self.source = schedule.source
            self.minuteDifferences = schedule.comparison?.minuteDifferences
        }
    }

    public let snapshotLocation: GeoLocation
    public let snapshotTimeZoneIdentifier: String
    public let todaySchedule: ScheduleSignature
    public let tomorrowSchedule: ScheduleSignature
    public let upcomingOccasions: [Occasion]

    public let language: AppLanguage
    public let usePersianDigits: Bool
    public let accentColorHex: String
    public let widgetDefaultPrayers: Set<Prayer>
    public let hijriVariant: HijriCalendarVariant
    public let hijriDayOffset: Int
    public let selectedLocation: GeoLocation
    public let calculationMethod: CalculationMethod
    public let prayerOffsets: [Prayer: Int]
    public let manualOverrides: [String: [Prayer: LocalTimeOfDay]]

    public init(snapshot: WidgetSnapshot, settings: AppSettings) {
        self.snapshotLocation = snapshot.location
        self.snapshotTimeZoneIdentifier = snapshot.timeZoneIdentifier
        self.todaySchedule = ScheduleSignature(schedule: snapshot.todaySchedule)
        self.tomorrowSchedule = ScheduleSignature(schedule: snapshot.tomorrowSchedule)
        self.upcomingOccasions = snapshot.upcomingOccasions

        self.language = settings.language
        self.usePersianDigits = settings.usePersianDigits
        self.accentColorHex = settings.accentColorHex
        self.widgetDefaultPrayers = settings.widgetDefaultPrayers
        self.hijriVariant = settings.hijriVariant
        self.hijriDayOffset = settings.hijriDayOffset
        self.selectedLocation = settings.selectedLocation
        self.calculationMethod = settings.calculationMethod
        self.prayerOffsets = settings.prayerOffsets
        self.manualOverrides = settings.manualOverrides
    }
}

/// Decides whether a WidgetKit timeline reload is justified after a schedule or settings update.
public enum WidgetReloadPolicy {
    public static func shouldReload(previous: WidgetFingerprint?, next: WidgetFingerprint) -> Bool {
        guard let previous else { return true }
        return previous != next
    }
}
