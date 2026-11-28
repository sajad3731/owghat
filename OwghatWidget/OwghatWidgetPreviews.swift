import OwghatCore
import SwiftUI
import WidgetKit

/// Deterministic sample data builder used by WidgetKit `#Preview` canvases.
enum WidgetPreviewSamples {
    private static let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private static let calculator = AstronomicalPrayerCalculator()

    static func sampleEntry(
        language: AppLanguage,
        usePersianDigits: Bool,
        isLateNight: Bool = false,
        isStale: Bool = false
    ) -> PrayerTimelineEntry {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ
        let date = cal.date(
            from: DateComponents(
                year: 2025,
                month: 3,
                day: 20,
                hour: isLateNight ? 21 : 11,
                minute: 30
            )
        )!

        let today = (try? calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 20),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )) ?? DailyPrayerTimes(
            dateKey: "2025-03-20",
            timeZoneIdentifier: tehranTZ.identifier,
            location: .tehran,
            method: .tehran,
            entries: [:],
            source: .offline
        )

        let tomorrow = (try? calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )) ?? today

        let nowruz = Occasion(
            id: "jalali-nowruz-1",
            titleEn: "Nowruz (Persian New Year)",
            titleFa: "آغاز نوروز",
            calendarKey: OccasionCalendarKey(calendar: .jalali, month: 1, day: 1),
            isOfficialHoliday: true,
            isBundled: true
        )

        var settings = WidgetDisplaySettings(appSettings: .default)
        settings.language = language
        settings.usePersianDigits = usePersianDigits

        let model = WidgetEntryModel.build(
            location: .tehran,
            method: .tehran,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            snapshotOccasions: [nowruz],
            settings: settings,
            visiblePrayers: Prayer.defaultVisible,
            date: date,
            timeZone: tehranTZ,
            snapshotAge: isStale ? 49 * 3600 : 120
        )
        return PrayerTimelineEntry(date: date, model: model)
    }
}

#Preview("Small (Persian)", as: .systemSmall) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .persian, usePersianDigits: true)
    WidgetPreviewSamples.sampleEntry(language: .persian, usePersianDigits: true, isLateNight: true)
}

#Preview("Small (English)", as: .systemSmall) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .english, usePersianDigits: false)
    WidgetPreviewSamples.sampleEntry(language: .english, usePersianDigits: false, isLateNight: true)
}

#Preview("Medium (Persian)", as: .systemMedium) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .persian, usePersianDigits: true)
}

#Preview("Medium (English)", as: .systemMedium) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .english, usePersianDigits: false)
}

#Preview("Large (Persian)", as: .systemLarge) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .persian, usePersianDigits: true)
    WidgetPreviewSamples.sampleEntry(language: .persian, usePersianDigits: true, isStale: true)
}

#Preview("Large (English)", as: .systemLarge) {
    OwghatWidget()
} timeline: {
    WidgetPreviewSamples.sampleEntry(language: .english, usePersianDigits: false)
    WidgetPreviewSamples.sampleEntry(language: .english, usePersianDigits: false, isStale: true)
}
