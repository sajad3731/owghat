import Foundation

/// Geographic location with coordinates, time zone, and bilingual names.
public struct GeoLocation: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let persianName: String
    public let countryCode: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String
    public let elevationMeters: Double

    public init(
        id: String,
        name: String,
        persianName: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        elevationMeters: Double = 0
    ) {
        self.id = id
        self.name = name
        self.persianName = persianName
        self.countryCode = countryCode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.elevationMeters = elevationMeters
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    public func localizedName(for language: AppLanguage) -> String {
        switch language {
        case .persian: return persianName
        case .english: return name
        }
    }

    /// Default Tehran location (`35.6892° N, 51.3890° E`, `Asia/Tehran`).
    public static let tehran = GeoLocation(
        id: "ir-tehran",
        name: "Tehran",
        persianName: "تهران",
        countryCode: "IR",
        latitude: 35.6892,
        longitude: 51.3890,
        timeZoneIdentifier: "Asia/Tehran",
        elevationMeters: 0
    )
}

/// Source used to determine the active location.
public enum LocationSelectionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case cityPreset
    case coreLocation
    case customCoordinates

    public var id: String { rawValue }
}
