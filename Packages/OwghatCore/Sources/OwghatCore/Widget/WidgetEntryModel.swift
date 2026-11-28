import Foundation

/// Resolves which prayers a widget should display given its configuration and app defaults.
public enum WidgetPrayerSelection {
    public static func resolveVisiblePrayers(
        followAppSettings: Bool,
        customSelection: Set<Prayer>,
        appDefaultPrayers: Set<Prayer>
    ) -> Set<Prayer> {
        if followAppSettings || customSelection.isEmpty {
            return appDefaultPrayers
        }
        return customSelection
    }
}

/// Subset of `AppSettings` that affects widget presentation.
public struct WidgetDisplaySettings: Codable, Sendable, Equatable, Hashable {
    public var language: AppLanguage
    public var usePersianDigits: Bool
    public var accentColorHex: String
    public var hijriVariant: HijriCalendarVariant
    public var hijriDayOffset: Int
    public var widgetDefaultPrayers: Set<Prayer>

    public init(
        language: AppLanguage = .persian,
        usePersianDigits: Bool = true,
        accentColorHex: String = AppSettings.default.accentColorHex,
        hijriVariant: HijriCalendarVariant = .ummAlQura,
        hijriDayOffset: Int = 0,
        widgetDefaultPrayers: Set<Prayer> = Prayer.defaultVisible
    ) {
        self.language = language
        self.usePersianDigits = usePersianDigits
        self.accentColorHex = accentColorHex
        self.hijriVariant = hijriVariant
        self.hijriDayOffset = hijriDayOffset
        self.widgetDefaultPrayers = widgetDefaultPrayers
    }

    public init(appSettings: AppSettings) {
        self.init(
            language: appSettings.language,
            usePersianDigits: appSettings.usePersianDigits,
            accentColorHex: appSettings.accentColorHex,
            hijriVariant: appSettings.hijriVariant,
            hijriDayOffset: appSettings.hijriDayOffset,
            widgetDefaultPrayers: appSettings.widgetDefaultPrayers
        )
    }
}

/// Deep-link URL targets opened when tapping Owghat widgets.
public enum WidgetDeepLink: Sendable, Equatable {
    case panel
    case prayer(Prayer)

    public static var panelURL: URL {
        URL(string: "\(AppConfig.urlScheme)://panel")!
    }

    public var url: URL {
        switch self {
        case .panel:
            return Self.panelURL
        case .prayer(let prayer):
            return URL(string: "\(AppConfig.urlScheme)://prayer/\(prayer.rawValue)")!
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == AppConfig.urlScheme else {
            return nil
        }
        let host = url.host?.lowercased()
        switch host {
        case "panel":
            self = .panel
        case "prayer":
            let rawID = url.pathComponents.dropFirst().first ?? ""
            guard let prayer = Prayer(rawValue: rawID) else {
                return nil
            }
            self = .prayer(prayer)
        default:
            return nil
        }
    }
}

/// Pure, view-ready state for a single WidgetKit timeline entry across all families.
public struct WidgetEntryModel: Sendable, Equatable {
    /// Age threshold (48 hours) beyond which an unrefreshed snapshot surfaces a stale hint.
    public static let staleSnapshotAgeThreshold: TimeInterval = 48 * 3600

    public let date: Date
    public let location: GeoLocation
    public let timeZone: TimeZone
    public let header: PanelHeader
    public let rows: [PanelPrayerRow]
    public let nextRow: PanelPrayerRow?
    public let nextBannerTitle: String?
    public let isNextTomorrow: Bool
    public let countdownRange: ClosedRange<Date>?
    public let occasions: PanelOccasionsDisplay?
    public let isSnapshotStale: Bool
    public let accentColorHex: String
    public let localeIdentifier: String
    public let language: AppLanguage
    public let usePersianDigits: Bool

    public init(
        date: Date,
        location: GeoLocation,
        timeZone: TimeZone,
        header: PanelHeader,
        rows: [PanelPrayerRow],
        nextRow: PanelPrayerRow?,
        nextBannerTitle: String?,
        isNextTomorrow: Bool,
        countdownRange: ClosedRange<Date>?,
        occasions: PanelOccasionsDisplay?,
        isSnapshotStale: Bool,
        accentColorHex: String,
        localeIdentifier: String,
        language: AppLanguage,
        usePersianDigits: Bool
    ) {
        self.date = date
        self.location = location
        self.timeZone = timeZone
        self.header = header
        self.rows = rows
        self.nextRow = nextRow
        self.nextBannerTitle = nextBannerTitle
        self.isNextTomorrow = isNextTomorrow
        self.countdownRange = countdownRange
        self.occasions = occasions
        self.isSnapshotStale = isSnapshotStale
        self.accentColorHex = accentColorHex
        self.localeIdentifier = localeIdentifier
        self.language = language
        self.usePersianDigits = usePersianDigits
    }

    public static func isSnapshotStale(snapshotAge: TimeInterval?) -> Bool {
        guard let snapshotAge else { return true }
        return snapshotAge > staleSnapshotAgeThreshold
    }

    public static func localeIdentifier(language: AppLanguage, usePersianDigits: Bool) -> String {
        switch language {
        case .persian:
            return usePersianDigits ? "fa_IR" : "fa_IR@numbers=latn"
        case .english:
            return "en_US"
        }
    }

    /// Builds complete display state for `date` by reusing `PanelHeader`, `PanelSchedule`, and `PanelOccasionsDisplay`.
    public static func build(
        location: GeoLocation,
        method: CalculationMethod,
        todaySchedule: DailyPrayerTimes?,
        tomorrowSchedule: DailyPrayerTimes?,
        yesterdaySchedule: DailyPrayerTimes? = nil,
        snapshotOccasions: [Occasion],
        settings: WidgetDisplaySettings,
        visiblePrayers: Set<Prayer>,
        date: Date,
        timeZone: TimeZone,
        snapshotAge: TimeInterval?
    ) -> WidgetEntryModel {
        let converter = CalendarConverter()
        let dates = converter.allDates(
            for: date,
            timeZone: timeZone,
            hijriVariant: settings.hijriVariant,
            hijriDayOffset: settings.hijriDayOffset,
            language: settings.language
        )

        let header = PanelHeader.build(
            location: location,
            method: method,
            dates: dates,
            language: settings.language,
            usePersianDigits: settings.usePersianDigits
        )

        let panelSchedule = PanelSchedule.build(
            todaySchedule: todaySchedule,
            tomorrowSchedule: tomorrowSchedule,
            yesterdaySchedule: yesterdaySchedule,
            visiblePrayers: visiblePrayers,
            now: date,
            timeZone: timeZone,
            language: settings.language,
            usePersianDigits: settings.usePersianDigits
        )

        let (todayOccasions, upcomingDatedOccasions) = resolveOccasions(
            from: snapshotOccasions,
            at: date,
            timeZone: timeZone,
            settings: settings,
            converter: converter
        )

        let occasions = PanelOccasionsDisplay.build(
            todayOccasions: todayOccasions,
            upcomingOccasions: upcomingDatedOccasions,
            now: date,
            timeZone: timeZone,
            language: settings.language,
            usePersianDigits: settings.usePersianDigits
        )

        let countdownRange: ClosedRange<Date>?
        if let nextRow = panelSchedule.nextRow, nextRow.date > date {
            countdownRange = date...nextRow.date
        } else {
            countdownRange = nil
        }

        return WidgetEntryModel(
            date: date,
            location: location,
            timeZone: timeZone,
            header: header,
            rows: panelSchedule.rows,
            nextRow: panelSchedule.nextRow,
            nextBannerTitle: panelSchedule.nextBannerTitle,
            isNextTomorrow: panelSchedule.nextRow?.isTomorrow ?? false,
            countdownRange: countdownRange,
            occasions: occasions,
            isSnapshotStale: isSnapshotStale(snapshotAge: snapshotAge),
            accentColorHex: settings.accentColorHex,
            localeIdentifier: localeIdentifier(language: settings.language, usePersianDigits: settings.usePersianDigits),
            language: settings.language,
            usePersianDigits: settings.usePersianDigits
        )
    }

    private static func resolveOccasions(
        from candidateOccasions: [Occasion],
        at date: Date,
        timeZone: TimeZone,
        settings: WidgetDisplaySettings,
        converter: CalendarConverter
    ) -> (today: [Occasion], upcoming: [DatedOccasion]) {
        let activeCandidates = candidateOccasions.filter { !$0.isHidden }
        guard !activeCandidates.isEmpty else {
            return ([], [])
        }

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let baseComponents = gregorian.dateComponents([.year, .month, .day], from: date)
        let localNoon = gregorian.date(from: DateComponents(
            year: baseComponents.year,
            month: baseComponents.month,
            day: baseComponents.day,
            hour: 12
        )) ?? date

        var todayOccasions: [Occasion] = []
        var seenTodayIDs: Set<String> = []
        var upcomingOccasions: [DatedOccasion] = []
        var seenDatedIDs: Set<String> = []

        for offset in 0..<14 {
            guard let dayDate = gregorian.date(byAdding: .day, value: offset, to: localNoon) else {
                continue
            }
            let dayDates = converter.allDates(
                for: dayDate,
                timeZone: timeZone,
                hijriVariant: settings.hijriVariant,
                hijriDayOffset: settings.hijriDayOffset,
                language: settings.language
            )
            let dayKey = DateKeyFormatter.key(for: dayDate, in: timeZone)

            for occasion in activeCandidates {
                let matches: Bool = switch occasion.calendarKey.calendar {
                case .jalali: occasion.calendarKey.matches(dayDates.jalali)
                case .hijri: occasion.calendarKey.matches(dayDates.hijri)
                case .gregorian: occasion.calendarKey.matches(dayDates.gregorian)
                }
                guard matches else { continue }

                if offset == 0 {
                    if seenTodayIDs.insert(occasion.id).inserted {
                        todayOccasions.append(occasion)
                    }
                } else {
                    let dated = DatedOccasion(date: dayDate, dateKey: dayKey, occasion: occasion)
                    if seenDatedIDs.insert(dated.id).inserted {
                        upcomingOccasions.append(dated)
                    }
                }
            }
        }

        return (todayOccasions, upcomingOccasions)
    }
}
