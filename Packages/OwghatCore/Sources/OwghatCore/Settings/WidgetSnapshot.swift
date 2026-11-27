import Foundation

/// Precomputed schedule bundle shared with the WidgetKit extension through the App Group.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let location: GeoLocation
    public let timeZoneIdentifier: String
    public let todaySchedule: DailyPrayerTimes
    public let tomorrowSchedule: DailyPrayerTimes
    public let upcomingOccasions: [Occasion]

    public init(
        generatedAt: Date = Date(),
        location: GeoLocation,
        timeZoneIdentifier: String,
        todaySchedule: DailyPrayerTimes,
        tomorrowSchedule: DailyPrayerTimes,
        upcomingOccasions: [Occasion]
    ) {
        self.generatedAt = generatedAt
        self.location = location
        self.timeZoneIdentifier = timeZoneIdentifier
        self.todaySchedule = todaySchedule
        self.tomorrowSchedule = tomorrowSchedule
        self.upcomingOccasions = upcomingOccasions
    }
}
