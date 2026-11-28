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

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(
            name: LocalizedStringResource("widget.intent.prayer_type", defaultValue: "Prayer")
        )
    }

    static var caseDisplayRepresentations: [PrayerAppEnum: DisplayRepresentation] {
        [
            .imsak: DisplayRepresentation(title: LocalizedStringResource("prayer.imsak", defaultValue: "Imsak")),
            .fajr: DisplayRepresentation(title: LocalizedStringResource("prayer.fajr", defaultValue: "Fajr")),
            .sunrise: DisplayRepresentation(title: LocalizedStringResource("prayer.sunrise", defaultValue: "Sunrise")),
            .dhuhr: DisplayRepresentation(title: LocalizedStringResource("prayer.dhuhr", defaultValue: "Dhuhr")),
            .sunset: DisplayRepresentation(title: LocalizedStringResource("prayer.sunset", defaultValue: "Sunset")),
            .maghrib: DisplayRepresentation(title: LocalizedStringResource("prayer.maghrib", defaultValue: "Maghrib")),
            .isha: DisplayRepresentation(title: LocalizedStringResource("prayer.isha", defaultValue: "Isha")),
            .midnight: DisplayRepresentation(title: LocalizedStringResource("prayer.midnight", defaultValue: "Midnight"))
        ]
    }

    var corePrayer: Prayer {
        Prayer(rawValue: rawValue) ?? .fajr
    }
}

/// Widget configuration allowing users to follow Owghat app defaults or select custom prayers per widget.
struct PrayerWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("widget.intent.title", defaultValue: "Configure Prayers")
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource(
                "widget.intent.description",
                defaultValue: "Choose which prayer times are visible in this widget."
            )
        )
    }

    @Parameter(
        title: LocalizedStringResource("widget.intent.follow_app.title", defaultValue: "Follow App Settings"),
        description: LocalizedStringResource("widget.intent.follow_app.description", defaultValue: "Use the default prayers configured in Owghat."),
        default: true
    )
    var followAppSettings: Bool

    @Parameter(
        title: LocalizedStringResource("widget.intent.prayers.title", defaultValue: "Prayers"),
        description: LocalizedStringResource("widget.intent.prayers.description", defaultValue: "Custom prayers shown when not following app settings."),
        default: [.fajr, .sunrise, .dhuhr, .sunset, .maghrib, .midnight]
    )
    var prayers: [PrayerAppEnum]

    init() {}
}
