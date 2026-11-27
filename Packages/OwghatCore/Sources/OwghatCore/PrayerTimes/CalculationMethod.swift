import Foundation

/// Rule for computing Islamic midnight.
public enum MidnightMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Midpoint between sunset and next day's Fajr (Iran / Jafari convention).
    case shia
    /// Midpoint between sunset and next day's sunrise.
    case standard

    public var id: String { rawValue }
}

/// High-latitude adjustment strategy when solar depression angles are not reached.
public enum HighLatitudeRule: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case middleOfNight
    case oneSeventh
    case angleBased

    public var id: String { rawValue }
}

/// Rule specifying how a twilight prayer (Maghrib or Isha) is computed.
public enum TwilightRule: Codable, Sendable, Equatable, Hashable {
    /// Solar depression angle in degrees below the horizon.
    case angle(Double)
    /// Fixed number of minutes after sunset.
    case minutesAfterSunset(Double)
    /// Fixed number of minutes after Maghrib (used by Umm al-Qura for Isha).
    case minutesAfterMaghrib(Double)
}

/// Numerical parameters driving astronomical prayer time calculation.
public struct CalculationParameters: Codable, Sendable, Equatable, Hashable {
    public var fajrAngle: Double
    public var maghribRule: TwilightRule
    public var ishaRule: TwilightRule
    public var imsakMinutesBeforeFajr: Int
    public var midnightMode: MidnightMode
    public var highLatitudeRule: HighLatitudeRule

    public init(
        fajrAngle: Double,
        maghribRule: TwilightRule,
        ishaRule: TwilightRule,
        imsakMinutesBeforeFajr: Int = 10,
        midnightMode: MidnightMode = .shia,
        highLatitudeRule: HighLatitudeRule = .angleBased
    ) {
        self.fajrAngle = fajrAngle
        self.maghribRule = maghribRule
        self.ishaRule = ishaRule
        self.imsakMinutesBeforeFajr = imsakMinutesBeforeFajr
        self.midnightMode = midnightMode
        self.highLatitudeRule = highLatitudeRule
    }
}

/// Standard prayer time calculation conventions plus user-defined custom angles.
public enum CalculationMethod: Codable, Sendable, Equatable, Hashable, Identifiable {
    case tehran
    case jafari
    case mwl
    case ummAlQura
    case egyptian
    case karachi
    case isna
    case custom(CalculationParameters)

    public static let allPresets: [CalculationMethod] = [
        .tehran, .jafari, .mwl, .ummAlQura, .egyptian, .karachi, .isna
    ]

    public var id: String {
        switch self {
        case .tehran: return "tehran"
        case .jafari: return "jafari"
        case .mwl: return "mwl"
        case .ummAlQura: return "ummAlQura"
        case .egyptian: return "egyptian"
        case .karachi: return "karachi"
        case .isna: return "isna"
        case .custom: return "custom"
        }
    }

    public var englishName: String {
        switch self {
        case .tehran: return "Tehran (Institute of Geophysics)"
        case .jafari: return "Jafari (Leva Research Institute, Qum)"
        case .mwl: return "Muslim World League (MWL)"
        case .ummAlQura: return "Umm al-Qura University, Makkah"
        case .egyptian: return "Egyptian General Authority of Survey"
        case .karachi: return "University of Islamic Sciences, Karachi"
        case .isna: return "Islamic Society of North America (ISNA)"
        case .custom: return "Custom Angles"
        }
    }

    public var persianName: String {
        switch self {
        case .tehran: return "تهران (مؤسسه ژئوفیزیک دانشگاه تهران)"
        case .jafari: return "جعفری (مؤسسه لواء قم)"
        case .mwl: return "رابطه عالم اسلامی"
        case .ummAlQura: return "ام‌القری (مکه)"
        case .egyptian: return "مرجع عمومی مساحی مصر"
        case .karachi: return "دانشگاه علوم اسلامی کراچی"
        case .isna: return "انجمن اسلامی آمریکای شمالی (ISNA)"
        case .custom: return "زاویه‌های سفارشی"
        }
    }

    public func localizedName(for language: AppLanguage) -> String {
        switch language {
        case .persian: return persianName
        case .english: return englishName
        }
    }

    /// Corresponding Aladhan API method identifier.
    public var aladhanMethodID: Int {
        switch self {
        case .tehran: return 7
        case .jafari: return 0
        case .mwl: return 3
        case .ummAlQura: return 4
        case .egyptian: return 5
        case .karachi: return 1
        case .isna: return 2
        case .custom: return 99
        }
    }

    public var parameters: CalculationParameters {
        switch self {
        case .tehran:
            return CalculationParameters(
                fajrAngle: 17.7,
                maghribRule: .angle(4.5),
                ishaRule: .angle(14.0),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .shia
            )
        case .jafari:
            return CalculationParameters(
                fajrAngle: 16.0,
                maghribRule: .angle(4.0),
                ishaRule: .angle(14.0),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .shia
            )
        case .mwl:
            return CalculationParameters(
                fajrAngle: 18.0,
                maghribRule: .minutesAfterSunset(0),
                ishaRule: .angle(17.0),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .standard
            )
        case .ummAlQura:
            return CalculationParameters(
                fajrAngle: 18.5,
                maghribRule: .minutesAfterSunset(0),
                ishaRule: .minutesAfterMaghrib(90),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .standard
            )
        case .egyptian:
            return CalculationParameters(
                fajrAngle: 19.5,
                maghribRule: .minutesAfterSunset(0),
                ishaRule: .angle(17.5),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .standard
            )
        case .karachi:
            return CalculationParameters(
                fajrAngle: 18.0,
                maghribRule: .minutesAfterSunset(0),
                ishaRule: .angle(18.0),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .standard
            )
        case .isna:
            return CalculationParameters(
                fajrAngle: 15.0,
                maghribRule: .minutesAfterSunset(0),
                ishaRule: .angle(15.0),
                imsakMinutesBeforeFajr: 10,
                midnightMode: .standard
            )
        case .custom(let params):
            return params
        }
    }
}
