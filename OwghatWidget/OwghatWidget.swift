import AppIntents
import OwghatCore
import SwiftUI
import WidgetKit

struct PrayerTimelineEntry: TimelineEntry {
    let date: Date
    let location: GeoLocation
    let timeZone: TimeZone
    let schedule: DailyPrayerTimes
    let dates: TripleCalendarDate
    let occasions: [Occasion]
    let language: AppLanguage
    let usePersianDigits: Bool
    let visiblePrayers: Set<Prayer>
    let nextPrayer: PrayerTimeEntry?
}

struct OwghatTimelineProvider: AppIntentTimelineProvider {
    private let calculator = AstronomicalPrayerCalculator()
    private let converter = CalendarConverter()
    private let occasionStore = OccasionStore()

    func placeholder(in context: Context) -> PrayerTimelineEntry {
        makeEntry(at: Date(), configuration: PrayerWidgetConfigurationIntent())
    }

    func snapshot(for configuration: PrayerWidgetConfigurationIntent, in context: Context) async -> PrayerTimelineEntry {
        makeEntry(at: Date(), configuration: configuration)
    }

    func timeline(for configuration: PrayerWidgetConfigurationIntent, in context: Context) async -> Timeline<PrayerTimelineEntry> {
        let now = Date()
        let store = SettingsStore()
        let settings = store.loadSettings()
        let tz = settings.selectedLocation.timeZone

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = tz
        let startOfToday = gregorian.startOfDay(for: now)
        let startOfTomorrow = gregorian.date(byAdding: .day, value: 1, to: startOfToday)
            ?? now.addingTimeInterval(86_400)

        let todaySchedule = resolvedSchedule(for: now, settings: settings, snapshot: store.loadWidgetSnapshot())
        let boundaryDates = ([now, startOfTomorrow] + todaySchedule.orderedEntries().map(\.date))
            .filter { $0 >= now && $0 <= startOfTomorrow }
            .sorted()

        var uniqueBoundaries: [Date] = []
        for date in boundaryDates {
            if let last = uniqueBoundaries.last, abs(date.timeIntervalSince(last)) < 1 {
                continue
            }
            uniqueBoundaries.append(date)
        }

        let entries = uniqueBoundaries.map { entryDate in
            makeEntry(at: entryDate, configuration: configuration, store: store)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeEntry(
        at date: Date,
        configuration: PrayerWidgetConfigurationIntent,
        store: SettingsStore = SettingsStore()
    ) -> PrayerTimelineEntry {
        let settings = store.loadSettings()
        let snapshot = store.loadWidgetSnapshot()
        let tz = settings.selectedLocation.timeZone
        let schedule = resolvedSchedule(for: date, settings: settings, snapshot: snapshot)

        let configuredSet = Set(configuration.prayers.map(\.corePrayer))
        let visible = configuredSet.isEmpty ? settings.widgetDefaultPrayers : configuredSet

        let upcoming = schedule
            .orderedEntries(filteredBy: visible)
            .first { $0.date > date }

        let dates = converter.allDates(
            for: date,
            timeZone: tz,
            hijriVariant: settings.hijriVariant,
            hijriDayOffset: settings.hijriDayOffset,
            language: settings.language
        )

        let occasions = occasionStore.occasions(on: date, timeZone: tz, settings: settings)

        return PrayerTimelineEntry(
            date: date,
            location: settings.selectedLocation,
            timeZone: tz,
            schedule: schedule,
            dates: dates,
            occasions: occasions,
            language: settings.language,
            usePersianDigits: settings.usePersianDigits,
            visiblePrayers: visible,
            nextPrayer: upcoming
        )
    }

    private func resolvedSchedule(
        for date: Date,
        settings: AppSettings,
        snapshot: WidgetSnapshot?
    ) -> DailyPrayerTimes {
        let tz = settings.selectedLocation.timeZone
        let key = DateKeyFormatter.key(for: date, in: tz)

        if let snapshot {
            if snapshot.todaySchedule.dateKey == key {
                return snapshot.todaySchedule
            }
            if snapshot.tomorrowSchedule.dateKey == key {
                return snapshot.tomorrowSchedule
            }
        }

        let components = DateKeyFormatter.components(from: date, in: tz)
        if let calculated = try? calculator.calculate(
            for: components,
            location: settings.selectedLocation,
            timeZone: tz,
            method: settings.calculationMethod,
            offsets: settings.prayerOffsets,
            manualOverrides: settings.manualOverrides
        ) {
            return calculated
        }

        return DailyPrayerTimes(
            dateKey: key,
            timeZoneIdentifier: tz.identifier,
            location: settings.selectedLocation,
            method: settings.calculationMethod,
            entries: [:],
            source: .offline
        )
    }
}

struct OwghatWidgetEntryView: View {
    let entry: PrayerTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                largeView
            }
        }
        .environment(\.layoutDirection, entry.language.isRTL ? .rightToLeft : .leftToRight)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.location.localizedName(for: entry.language))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let next = entry.nextPrayer {
                Label(next.prayer.localizedName(for: entry.language), systemImage: next.prayer.symbolName)
                    .font(.headline)
                Text(
                    DigitFormatter.formatTime(
                        next.date,
                        timeZone: entry.timeZone,
                        persianDigits: entry.usePersianDigits
                    )
                )
                .font(.title2.monospacedDigit().weight(.semibold))
                Text(next.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.dates.jalali.formattedLong(persianDigits: entry.usePersianDigits))
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.location.localizedName(for: entry.language))
                    .font(.headline)
                Spacer()
                Text(entry.dates.jalali.formattedLong(persianDigits: entry.usePersianDigits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            let entries = entry.schedule.orderedEntries(filteredBy: entry.visiblePrayers)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(entries) { item in
                    let isNext = entry.nextPrayer?.prayer == item.prayer
                    HStack {
                        Text(item.prayer.localizedName(for: entry.language))
                            .font(.caption.weight(isNext ? .bold : .regular))
                        Spacer()
                        Text(
                            DigitFormatter.formatTime(
                                item.date,
                                timeZone: entry.timeZone,
                                persianDigits: entry.usePersianDigits
                            )
                        )
                        .font(.caption.monospacedDigit().weight(isNext ? .bold : .regular))
                    }
                    .foregroundStyle(isNext ? Color.accentColor : Color.primary)
                }
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.location.localizedName(for: entry.language))
                    .font(.headline)
                Text("\(entry.dates.jalali.weekdayName) • \(entry.dates.jalali.formattedLong(persianDigits: entry.usePersianDigits))")
                    .font(.caption)
                Text("\(entry.dates.hijri.formattedLong(persianDigits: entry.usePersianDigits)) • \(entry.dates.gregorian.formattedLong(persianDigits: entry.usePersianDigits))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            let entries = entry.schedule.orderedEntries(filteredBy: entry.visiblePrayers)
            ForEach(entries) { item in
                let isNext = entry.nextPrayer?.prayer == item.prayer
                HStack {
                    Image(systemName: item.prayer.symbolName)
                        .frame(width: 16)
                    Text(item.prayer.localizedName(for: entry.language))
                    Spacer()
                    Text(
                        DigitFormatter.formatTime(
                            item.date,
                            timeZone: entry.timeZone,
                            persianDigits: entry.usePersianDigits
                        )
                    )
                    .monospacedDigit()
                }
                .font(.subheadline.weight(isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Color.accentColor : Color.primary)
            }

            if !entry.occasions.isEmpty {
                Divider()
                ForEach(entry.occasions.prefix(3)) { occasion in
                    Text("• \(occasion.localizedTitle(for: entry.language))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

struct OwghatWidget: Widget {
    let kind: String = AppConfig.widgetBundleIdentifier

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: PrayerWidgetConfigurationIntent.self,
            provider: OwghatTimelineProvider()
        ) { entry in
            OwghatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringKey("widget.title"))
        .description(LocalizedStringKey("widget.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
