import Foundation
import OwghatCore
import ServiceManagement
import SwiftUI
import WidgetKit

/// Selectable tabs in the macOS Settings window.
enum SettingsTab: Hashable {
    case general
    case calculation
    case adhan
    case appearance
    case events
}

/// Central observable state coordinating settings, prayer schedule, audio playback, and widgets.
@Observable
@MainActor
final class AppState {
    var settings: AppSettings
    var yesterdaySchedule: DailyPrayerTimes?
    var todaySchedule: DailyPrayerTimes?
    var tomorrowSchedule: DailyPrayerTimes?
    var nextPrayer: NextPrayerResolution?
    var todayOccasions: [Occasion] = []
    var upcomingOccasions: [DatedOccasion] = []
    var dates: TripleCalendarDate?
    var isPlayingAdhan: Bool = false
    var isRefreshing: Bool = false
    var statusMessage: String?
    var selectedSettingsTab: SettingsTab = .general

    private let settingsStore: SettingsStore
    private let provider: any PrayerTimesProvider
    private let resolver = PrayerTimeResolver()
    private let occasionStore = OccasionStore()
    private let calendarConverter = CalendarConverter()
    let audioPlayer = AdhanAudioPlayer()
    let scheduler: AdhanScheduler
    let locationManager = LocationManager()
    let cityDatabase = CityDatabase()

    private var boundaryRefreshTask: Task<Void, Never>?
    private var retryRefreshTask: Task<Void, Never>?
    private var refreshBackoff = RefreshBackoff()

    init(
        settingsStore: SettingsStore = SettingsStore(),
        provider: any PrayerTimesProvider = HybridPrayerTimesProvider()
    ) {
        self.settingsStore = settingsStore
        self.provider = provider
        self.settings = settingsStore.loadSettings()
        self.scheduler = AdhanScheduler(audioPlayer: audioPlayer)

        audioPlayer.onPlaybackStateChanged = { [weak self] playing in
            self?.isPlayingAdhan = playing
        }

        scheduler.onScheduleNeedsRefresh = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshSchedule(force: true)
            }
        }

        locationManager.onLocationUpdated = { [weak self] location in
            guard let self else { return }
            self.updateSettings { settings in
                settings.locationMode = .coreLocation
                settings.selectedLocation = location
            }
        }

        locationManager.onAuthorizationError = { [weak self] message in
            self?.statusMessage = message
        }

        applyDockIconPolicy()

        Task {
            await scheduler.requestNotificationPermission()
            await refreshSchedule(force: true)
        }
    }

    var activeTimeZone: TimeZone {
        settings.selectedLocation.timeZone
    }

    var isMutedToday: Bool {
        settings.adhan.isMuted(on: Date(), timeZone: activeTimeZone)
    }

    var accentColor: Color {
        Color(owghatHex: settings.accentColorHex)
    }

    func dismissStatusMessage() {
        statusMessage = nil
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        do {
            try settingsStore.saveSettings(settings)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
        applyDockIconPolicy()
        applyLaunchAtLogin()

        Task {
            await refreshSchedule(force: true)
        }
    }

    func refreshSchedule(now: Date = Date(), force: Bool = false) async {
        guard !isRefreshing else { return }
        if !force && !refreshBackoff.canRetry(at: now) {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        retryRefreshTask?.cancel()
        retryRefreshTask = nil

        let tz = activeTimeZone
        let location = settings.selectedLocation

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = tz
        let yesterdayDate = gregorian.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrowDate = gregorian.date(byAdding: .day, value: 1, to: now) ?? now

        let yesterdayComponents = gregorian.dateComponents([.year, .month, .day], from: yesterdayDate)
        let todayComponents = gregorian.dateComponents([.year, .month, .day], from: now)
        let tomorrowComponents = gregorian.dateComponents([.year, .month, .day], from: tomorrowDate)

        do {
            let yesterday = try await provider.prayerTimes(
                for: yesterdayComponents,
                location: location,
                timeZone: tz,
                settings: settings
            )
            let today = try await provider.prayerTimes(
                for: todayComponents,
                location: location,
                timeZone: tz,
                settings: settings
            )
            let tomorrow = try await provider.prayerTimes(
                for: tomorrowComponents,
                location: location,
                timeZone: tz,
                settings: settings
            )

            yesterdaySchedule = yesterday
            todaySchedule = today
            tomorrowSchedule = tomorrow

            let resolvedNext = resolver.nextPrayer(
                at: now,
                schedules: [yesterday, today, tomorrow],
                visiblePrayers: settings.visiblePrayers
            )
            nextPrayer = resolvedNext

            dates = calendarConverter.allDates(
                for: now,
                timeZone: tz,
                hijriVariant: settings.hijriVariant,
                hijriDayOffset: settings.hijriDayOffset,
                language: settings.language
            )

            todayOccasions = occasionStore.occasions(on: now, timeZone: tz, settings: settings)
            upcomingOccasions = occasionStore.upcomingOccasions(from: now, days: 14, timeZone: tz, settings: settings)

            let snapshot = WidgetSnapshot(
                generatedAt: now,
                location: location,
                timeZoneIdentifier: tz.identifier,
                todaySchedule: today,
                tomorrowSchedule: tomorrow,
                upcomingOccasions: Array(upcomingOccasions.prefix(6).map(\.occasion))
            )
            try? settingsStore.saveWidgetSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()

            scheduler.arm(
                nextResolution: resolvedNext,
                todaySchedule: today,
                settings: settings,
                timeZone: tz
            )

            if let resolvedNext, resolvedNext.entry.date > now {
                refreshBackoff.recordSuccess()
                scheduleBoundaryRefresh(for: resolvedNext.entry.date, now: now)
            } else if !settings.visiblePrayers.isEmpty {
                let delay = refreshBackoff.recordFailure(at: now)
                scheduleRetryRefresh(after: delay)
            } else {
                refreshBackoff.recordSuccess()
                boundaryRefreshTask?.cancel()
                boundaryRefreshTask = nil
            }
        } catch {
            statusMessage = error.localizedDescription
            let delay = refreshBackoff.recordFailure(at: now)
            scheduleRetryRefresh(after: delay)
        }
    }

    func justReachedEntry(at now: Date) -> PrayerTimeEntry? {
        let candidates = [yesterdaySchedule, todaySchedule, tomorrowSchedule]
            .compactMap { $0?.orderedEntries(filteredBy: settings.visiblePrayers) }
            .flatMap { $0 }
            .filter { entry in
                let elapsed = now.timeIntervalSince(entry.date)
                return elapsed >= 0 && elapsed < MenuBarLabelFormatter.boundaryBannerDuration
            }
        return candidates.max { $0.date < $1.date }
    }

    func toggleMuteToday() {
        let todayKey = DateKeyFormatter.key(for: Date(), in: activeTimeZone)
        updateSettings { settings in
            if settings.adhan.mutedDateKey == todayKey {
                settings.adhan.mutedDateKey = nil
            } else {
                settings.adhan.mutedDateKey = todayKey
            }
        }
    }

    func stopAdhanPlayback() {
        audioPlayer.stop()
    }

    func previewAdhan(for prayer: Prayer) {
        let choice = settings.adhan.audioPerPrayer[prayer] ?? .bundledPlaceholder
        audioPlayer.play(choice: choice, postAdhanDoa: .none, settings: settings.adhan)
    }

    func importAudioFile(from url: URL) {
        do {
            let clip = try audioPlayer.importAudio(from: url)
            updateSettings { settings in
                settings.adhan.importedClips.append(clip)
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportSettingsData() throws -> Data {
        try settingsStore.exportJSON(for: settings)
    }

    func importSettingsData(from data: Data) throws {
        let imported = try settingsStore.importJSON(from: data)
        updateSettings { $0 = imported }
    }

    func applyDockIconPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.adhan.showDockIcon ? .regular : .accessory
        NSApp?.setActivationPolicy(policy)
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.adhan.launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration requires a signed app bundle; keep silent during unsigned dev builds.
        }
    }

    /// Fires a single refresh right after the next prayer boundary passes (no 1 Hz polling).
    private func scheduleBoundaryRefresh(for targetDate: Date, now: Date) {
        boundaryRefreshTask?.cancel()
        let delay = max(0.05, targetDate.timeIntervalSince(now) + 0.05)
        boundaryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.refreshSchedule(force: false)
        }
    }

    private func scheduleRetryRefresh(after delay: TimeInterval) {
        retryRefreshTask?.cancel()
        retryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            await self.refreshSchedule(force: false)
        }
    }
}
