import Foundation

/// Supported UI languages.
public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case persian = "fa"
    case english = "en"

    public var id: String { rawValue }

    public var isRTL: Bool {
        self == .persian
    }

    public var displayName: String {
        switch self {
        case .persian: return "فارسی"
        case .english: return "English"
        }
    }
}

/// Supported Islamic prayer and solar daily markers.
public enum Prayer: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case imsak
    case fajr
    case sunrise
    case dhuhr
    case sunset
    case maghrib
    case isha
    case midnight

    public var id: String { rawValue }

    public var englishName: String {
        switch self {
        case .imsak: return "Imsak"
        case .fajr: return "Fajr"
        case .sunrise: return "Sunrise"
        case .dhuhr: return "Dhuhr"
        case .sunset: return "Sunset"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        case .midnight: return "Midnight"
        }
    }

    public var persianName: String {
        switch self {
        case .imsak: return "امساک"
        case .fajr: return "اذان صبح"
        case .sunrise: return "طلوع آفتاب"
        case .dhuhr: return "اذان ظهر"
        case .sunset: return "غروب آفتاب"
        case .maghrib: return "اذان مغرب"
        case .isha: return "عشا"
        case .midnight: return "نیمه‌شب شرعی"
        }
    }

    public func localizedName(for language: AppLanguage) -> String {
        switch language {
        case .persian: return persianName
        case .english: return englishName
        }
    }

    public var symbolName: String {
        switch self {
        case .imsak: return "moon.zzz"
        case .fajr: return "sun.haze"
        case .sunrise: return "sunrise"
        case .dhuhr: return "sun.max"
        case .sunset: return "sunset"
        case .maghrib: return "moon.stars"
        case .isha: return "moon"
        case .midnight: return "sparkles"
        }
    }

    /// Whether this marker typically has an Adhan recitation.
    public var isAdhanPrayer: Bool {
        switch self {
        case .fajr, .dhuhr, .maghrib, .isha:
            return true
        case .imsak, .sunrise, .sunset, .midnight:
            return false
        }
    }

    /// Default visible set shown in the panel and widgets.
    public static let defaultVisible: Set<Prayer> = [
        .fajr, .sunrise, .dhuhr, .sunset, .maghrib, .midnight
    ]
}
