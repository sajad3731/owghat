import AppIntents
import OwghatCore
import SwiftUI
import WidgetKit

struct PrayerTimelineEntry: TimelineEntry {
    let date: Date
    let model: WidgetEntryModel
}

struct OwghatTimelineProvider: AppIntentTimelineProvider {
    private let calculator = AstronomicalPrayerCalculator()
    private let occasionStore = OccasionStore()

    func placeholder(in context: Context) -> PrayerTimelineEntry {
        makeEntry(
            at: Date(),
            configuration: PrayerWidgetConfigurationIntent(),
            settings: SettingsStore().loadSettings(),
            snapshot: nil,
            scheduleCache: [:],
            fallbackOccasions: [],
            forceFreshHint: true
        ).entry
    }

    func snapshot(for configuration: PrayerWidgetConfigurationIntent, in context: Context) async -> PrayerTimelineEntry {
        let store = SettingsStore()
        let settings = store.loadSettings()
        let snapshot = store.loadWidgetSnapshot()
        let now = Date()
        let tz = settings.selectedLocation.timeZone
        let fallbackOccasions = occasionStore.upcomingOccasions(
            from: now,
            days: 16,
            timeZone: tz,
            settings: settings
        ).map(\.occasion)

        return makeEntry(
            at: now,
            configuration: configuration,
            settings: settings,
            snapshot: snapshot,
            scheduleCache: [:],
            fallbackOccasions: fallbackOccasions,
            forceFreshHint: context.isPreview
        ).entry
    }

    func timeline(for configuration: PrayerWidgetConfigurationIntent, in context: Context) async -> Timeline<PrayerTimelineEntry> {
        let now = Date()
        let store = SettingsStore()
        let settings = store.loadSettings()
        let snapshot = store.loadWidgetSnapshot()
        let tz = settings.selectedLocation.timeZone

        let visible = WidgetPrayerSelection.resolveVisiblePrayers(
            followAppSettings: configuration.followAppSettings,
            customSelection: Set(configuration.prayers.map(\.corePrayer)),
            appDefaultPrayers: settings.widgetDefaultPrayers
        )

        var scheduleCache: [String: DailyPrayerTimes] = [:]
        let today = resolveSchedule(for: now, dayOffset: 0, settings: settings, snapshot: snapshot, cache: &scheduleCache)
        let tomorrow = resolveSchedule(for: now, dayOffset: 1, settings: settings, snapshot: snapshot, cache: &scheduleCache)
        let yesterday = resolveSchedule(for: now, dayOffset: -1, settings: settings, snapshot: snapshot, cache: &scheduleCache)

        let entryDates = WidgetTimelinePlanner.timelineDates(
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            yesterdaySchedule: yesterday,
            visiblePrayers: visible,
            timeZone: tz,
            now: now
        )

        let fallbackOccasions = occasionStore.upcomingOccasions(
            from: now,
            days: 16,
            timeZone: tz,
            settings: settings
        ).map(\.occasion)

        let entries: [PrayerTimelineEntry] = entryDates.map { entryDate in
            let built = makeEntry(
                at: entryDate,
                configuration: configuration,
                settings: settings,
                snapshot: snapshot,
                scheduleCache: scheduleCache,
                fallbackOccasions: fallbackOccasions,
                forceFreshHint: false
            )
            scheduleCache = built.cache
            return built.entry
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeEntry(
        at date: Date,
        configuration: PrayerWidgetConfigurationIntent,
        settings: AppSettings,
        snapshot: WidgetSnapshot?,
        scheduleCache: [String: DailyPrayerTimes],
        fallbackOccasions: [Occasion],
        forceFreshHint: Bool
    ) -> (entry: PrayerTimelineEntry, cache: [String: DailyPrayerTimes]) {
        var cache = scheduleCache
        let tz = settings.selectedLocation.timeZone

        let today = resolveSchedule(for: date, dayOffset: 0, settings: settings, snapshot: snapshot, cache: &cache)
        let tomorrow = resolveSchedule(for: date, dayOffset: 1, settings: settings, snapshot: snapshot, cache: &cache)
        let yesterday = resolveSchedule(for: date, dayOffset: -1, settings: settings, snapshot: snapshot, cache: &cache)

        let visible = WidgetPrayerSelection.resolveVisiblePrayers(
            followAppSettings: configuration.followAppSettings,
            customSelection: Set(configuration.prayers.map(\.corePrayer)),
            appDefaultPrayers: settings.widgetDefaultPrayers
        )

        let snapshotMatchesSettings = isSnapshotCompatible(snapshot, with: settings, timeZone: tz)
        let snapshotAge: TimeInterval?
        let candidateOccasions: [Occasion]

        if forceFreshHint {
            snapshotAge = 0
            candidateOccasions = snapshotMatchesSettings
                ? (snapshot?.upcomingOccasions ?? fallbackOccasions)
                : fallbackOccasions
        } else if let snapshot, snapshotMatchesSettings {
            let age = max(0, date.timeIntervalSince(snapshot.generatedAt))
            snapshotAge = age
            candidateOccasions = age <= WidgetEntryModel.staleSnapshotAgeThreshold
                ? snapshot.upcomingOccasions
                : fallbackOccasions
        } else {
            snapshotAge = nil
            candidateOccasions = fallbackOccasions
        }

        let model = WidgetEntryModel.build(
            location: settings.selectedLocation,
            method: settings.calculationMethod,
            todaySchedule: today,
            tomorrowSchedule: tomorrow,
            yesterdaySchedule: yesterday,
            snapshotOccasions: candidateOccasions,
            settings: WidgetDisplaySettings(appSettings: settings),
            visiblePrayers: visible,
            date: date,
            timeZone: tz,
            snapshotAge: snapshotAge
        )

        return (PrayerTimelineEntry(date: date, model: model), cache)
    }

    private func isSnapshotCompatible(
        _ snapshot: WidgetSnapshot?,
        with settings: AppSettings,
        timeZone: TimeZone
    ) -> Bool {
        guard let snapshot else { return false }
        return snapshot.location == settings.selectedLocation
            && snapshot.timeZoneIdentifier == timeZone.identifier
            && snapshot.todaySchedule.method == settings.calculationMethod
    }

    private func resolveSchedule(
        for anchorDate: Date,
        dayOffset: Int,
        settings: AppSettings,
        snapshot: WidgetSnapshot?,
        cache: inout [String: DailyPrayerTimes]
    ) -> DailyPrayerTimes {
        let tz = settings.selectedLocation.timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = tz

        let anchorComponents = gregorian.dateComponents([.year, .month, .day], from: anchorDate)
        let anchorNoon = gregorian.date(from: DateComponents(
            year: anchorComponents.year,
            month: anchorComponents.month,
            day: anchorComponents.day,
            hour: 12
        )) ?? anchorDate

        let targetDate = gregorian.date(byAdding: .day, value: dayOffset, to: anchorNoon) ?? anchorNoon
        let targetComponents = DateKeyFormatter.components(from: targetDate, in: tz)
        let key = DateKeyFormatter.key(for: targetComponents)

        if let cached = cache[key] {
            return cached
        }

        if let snapshot, isSnapshotCompatible(snapshot, with: settings, timeZone: tz) {
            if snapshot.todaySchedule.dateKey == key {
                cache[key] = snapshot.todaySchedule
                return snapshot.todaySchedule
            }
            if snapshot.tomorrowSchedule.dateKey == key {
                cache[key] = snapshot.tomorrowSchedule
                return snapshot.tomorrowSchedule
            }
        }

        let resolved: DailyPrayerTimes
        if let calculated = try? calculator.calculate(
            for: targetComponents,
            location: settings.selectedLocation,
            timeZone: tz,
            method: settings.calculationMethod,
            offsets: settings.prayerOffsets,
            manualOverrides: settings.manualOverrides
        ) {
            resolved = calculated
        } else {
            resolved = DailyPrayerTimes(
                dateKey: key,
                timeZoneIdentifier: tz.identifier,
                location: settings.selectedLocation,
                method: settings.calculationMethod,
                entries: [:],
                source: .offline
            )
        }

        cache[key] = resolved
        return resolved
    }
}

struct OwghatWidgetEntryView: View {
    let entry: PrayerTimelineEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var model: WidgetEntryModel {
        entry.model
    }

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
        // Hierarchical styles only: when the desktop is not in front, macOS removes the widget
        // background and draws the content on glass. Fixed Color foregrounds vanish there.
        .foregroundStyle(.primary)
        .tint(renderingMode == .fullColor ? Color(owghatHex: model.accentColorHex) : .accentColor)
        .environment(\.layoutDirection, model.language.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: model.localeIdentifier))
        .widgetURL(WidgetDeepLink.panel.url)
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func rowForegroundStyle(for state: PrayerRowState) -> AnyShapeStyle {
        switch state {
        case .next:
            return AnyShapeStyle(.tint)
        case .upcoming:
            return AnyShapeStyle(.primary)
        case .passed:
            return AnyShapeStyle(.secondary)
        }
    }

    private func rowOpacity(for state: PrayerRowState) -> Double {
        guard state == .passed else { return 1.0 }
        return renderingMode == .fullColor ? 0.65 : 0.6
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Text(model.header.locationName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            if let nextRow = model.nextRow {
                if model.isNextTomorrow {
                    Text(LocalizedStringKey("menubar.tomorrow"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: nextRow.prayer.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    Text(nextRow.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(nextRow.formattedTime)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let range = model.countdownRange {
                    Text(timerInterval: range, countsDown: true)
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(DigitFormatter.format("00:00", persianDigits: model.usePersianDigits))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(model.header.jalaliLine)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                Text(LocalizedStringKey("menubar.no_prayers"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if model.isSnapshotStale {
                staleHintRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    Text(model.header.locationName)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if model.isSnapshotStale {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(model.header.jalaliLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Divider()

            if model.rows.isEmpty {
                Spacer(minLength: 0)
                Text(LocalizedStringKey("menubar.no_prayers"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 6
                ) {
                    ForEach(model.rows) { row in
                        HStack(spacing: 4) {
                            Image(systemName: row.prayer.symbolName)
                                .font(.caption2)
                                .frame(width: 14)

                            Text(row.isTomorrow ? (model.nextBannerTitle ?? row.title) : row.title)
                                .font(.caption.weight(row.state == .next ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 4)

                            Text(row.formattedTime)
                                .font(.caption.monospacedDigit().weight(row.state == .next ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundStyle(rowForegroundStyle(for: row.state))
                        .opacity(rowOpacity(for: row.state))
                        .widgetAccentable(row.state == .next)
                        .accessibilityLabel(row.accessibilityLabel)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                        .widgetAccentable()
                    Text(model.header.locationName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(model.header.methodName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(model.header.jalaliLine)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(model.header.secondaryDateLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            if model.rows.isEmpty {
                Text(LocalizedStringKey("menubar.no_prayers"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 5) {
                    ForEach(model.rows) { row in
                        Link(destination: WidgetDeepLink.prayer(row.prayer).url) {
                            HStack(spacing: 6) {
                                Image(systemName: row.prayer.symbolName)
                                    .frame(width: 16)

                                Text(row.title)
                                    .lineLimit(1)

                                if row.isTomorrow {
                                    Text(LocalizedStringKey("menubar.tomorrow"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 6)

                                if row.isOverridden {
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Text(row.formattedTime)
                                    .monospacedDigit()
                            }
                            .font(.subheadline.weight(row.state == .next ? .semibold : .regular))
                            .foregroundStyle(rowForegroundStyle(for: row.state))
                            .opacity(rowOpacity(for: row.state))
                            .widgetAccentable(row.state == .next)
                            .accessibilityLabel(row.accessibilityLabel)
                        }
                    }
                }
            }

            if let occasions = model.occasions, !occasions.items.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        LocalizedStringKey(
                            occasions.isShowingUpcoming ? "menubar.upcoming_occasion" : "menubar.occasions"
                        )
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(occasions.items.prefix(3)) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.isOfficialHoliday ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .frame(width: 5, height: 5)
                                .widgetAccentable(item.isOfficialHoliday)

                            Text(item.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if let relative = item.relativeDateText {
                                Spacer(minLength: 4)
                                Text(relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if model.isSnapshotStale {
                staleHintRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var staleHintRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
            Text(LocalizedStringKey("widget.stale_hint"))
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
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
