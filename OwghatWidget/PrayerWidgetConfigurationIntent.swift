import AppIntents
import OwghatCore

/// Selectable prayer options exposed to WidgetKit configuration intents.
enum PrayerAppEnum: String, AppEnum, CaseIterable {
    case imsak
    case fajr
    case sunrise
    case dhuhr
    case sunset
    case maghrib
    case isha
    case midnight

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Prayer")

    static let caseDisplayRepresentations: [PrayerAppEnum: DisplayRepresentation] = [
        .imsak: "Imsak",
        .fajr: "Fajr (Sobh)",
        .sunrise: "Sunrise",
        .dhuhr: "Dhuhr",
        .sunset: "Sunset",
        .maghrib: "Maghrib",
        .isha: "Isha",
        .midnight: "Midnight"
    ]

    var corePrayer: Prayer {
        Prayer(rawValue: rawValue) ?? .fajr
    }
}

/// Widget configuration allowing users to select which prayers are displayed.
struct PrayerWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Configure Prayers"
    static let description = IntentDescription("Choose which prayer times are visible in this widget.")

    @Parameter(
        title: "Prayers",
        default: [.fajr, .sunrise, .dhuhr, .sunset, .maghrib, .midnight]
    )
    var prayers: [PrayerAppEnum]

    init() {}
}
