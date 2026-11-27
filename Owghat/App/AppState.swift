import Foundation
import OwghatCore
import ServiceManagement
import SwiftUI
import WidgetKit

/// Central observable state coordinating settings, prayer schedule, audio playback, and widgets.
@Observable
@MainActor
final class AppState {
    var settings: AppSettings
    var todaySchedule: DailyPrayerTimes?
    var tomorrowSchedule: DailyPrayerTimes?
    var nextPrayer: NextPrayerResolution?
    var todayOccasions: [Occasion] = []
    var upcomingOccasions: [DatedOccasion] = []
    var dates: TripleCalendarDate?
    var isPlayingAdhan: Bool = false
    var statusMessage: String?

    private let settingsStore: SettingsStore
    private let provider = HybridPrayerTimesProvider()
    private let resolver = PrayerTimeResolver()
    private let occasionStore = OccasionStore()
    private let calendarConverter = CalendarConverter()
    let audioPlayer = AdhanAudioPlayer()
    let scheduler: AdhanScheduler
    let locationManager = LocationManager()
    let cityDatabase = CityDatabase()

    private var countdownTask: Task<Void, Never>?

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.loadSettings()
        self.scheduler = AdhanScheduler(audioPlayer: audioPlayer)

        audioPlayer.onPlaybackStateChanged = { [weak self] playing in
            self?.isPlayingAdhan = playing
        }

        scheduler.onScheduleNeedsRefresh = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshSchedule()
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
        startCountdownLoop()

        Task {
            await scheduler.requestNotificationPermission()
            await refreshSchedule()
        }
    }

    var activeTimeZone: TimeZone {
        settings.selectedLocation.timeZone
    }

    var isMutedToday: Bool {
        settings.adhan.isMuted(on: Date(), timeZone: activeTimeZone)
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
            await refreshSchedule()
        }
    }

    func refreshSchedule(now: Date = Date()) async {
        let tz = activeTimeZone
        let location = settings.selectedLocation

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = tz
        let todayComponents = gregorian.dateComponents([.year, .month, .day], from: now)
        let tomorrowDate = gregorian.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrowComponents = gregorian.dateComponents([.year, .month, .day], from: tomorrowDate)

        do {
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

            todaySchedule = today
            tomorrowSchedule = tomorrow
            nextPrayer = try await resolver.nextPrayer(
                at: now,
                location: location,
                timeZone: tz,
                settings: settings,
                provider: provider
            )

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
                nextResolution: nextPrayer,
                todaySchedule: today,
                settings: settings,
                timeZone: tz
            )
        } catch {
            statusMessage = error.localizedDescription
        }
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

    private func startCountdownLoop() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { break }
                if let entry = self.nextPrayer?.entry {
                    let remaining = entry.date.timeIntervalSinceNow
                    if remaining <= 0 {
                        await self.refreshSchedule()
                    } else {
                        self.nextPrayer = NextPrayerResolution(entry: entry, remainingInterval: remaining)
                    }
                }
            }
        }
    }
}
