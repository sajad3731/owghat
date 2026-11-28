import Foundation
import OwghatCore
import ServiceManagement
import SwiftUI
import UserNotifications
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
    var dayAfterSchedule: DailyPrayerTimes?
    var nextPrayer: NextPrayerResolution?
    var todayOccasions: [Occasion] = []
    var upcomingOccasions: [DatedOccasion] = []
    var dates: TripleCalendarDate?
    var isPlayingAdhan: Bool = false
    var currentPlayingPrayer: Prayer?
    var isRefreshing: Bool = false
    var statusMessage: String?
    var selectedSettingsTab: SettingsTab = .general
    var launchAtLoginStatus: SMAppService.Status = SMAppService.mainApp.status
    var launchAtLoginError: String?
    var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    var openMainWindowCounter: Int = 0
    var selectedDeepLinkPrayer: Prayer?

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
    private var refreshCoalescer = RefreshCoalescer()
    private var lastWidgetFingerprint: WidgetFingerprint?

    init(
        settingsStore: SettingsStore = SettingsStore(),
        provider: any PrayerTimesProvider = HybridPrayerTimesProvider()
    ) {
        self.settingsStore = settingsStore
        self.provider = provider
        self.settings = settingsStore.loadSettings()
        self.scheduler = AdhanScheduler(audioPlayer: audioPlayer)

        audioPlayer.onPlaybackStateChanged = { [weak self] playing, prayer in
            self?.isPlayingAdhan = playing
            self?.currentPlayingPrayer = prayer
        }

        audioPlayer.onPlaybackWarning = { [weak self] warning in
            self?.statusMessage = warning
        }

        scheduler.onScheduleNeedsRefresh = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshSchedule(force: true)
            }
        }

        scheduler.onOpenPanelOrWindow = { [weak self] in
            self?.openMainWindowCounter += 1
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
        syncLaunchAtLoginStatus(updateStoredToggle: true)

        Task {
            notificationAuthorizationStatus = await scheduler.requestNotificationPermissionOnce()
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

    var isUsingSharedWidgetContainer: Bool {
        settingsStore.isUsingSharedContainer
    }

    func handleWidgetURL(_ url: URL) {
        guard let deepLink = WidgetDeepLink(url: url) else { return }
        switch deepLink {
        case .panel:
            selectedDeepLinkPrayer = nil
        case .prayer(let prayer):
            selectedDeepLinkPrayer = prayer
        }
    }

    func dismissStatusMessage() {
        statusMessage = nil
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        let previousLaunchAtLogin = settings.adhan.launchAtLogin
        let previousShowDockIcon = settings.adhan.showDockIcon

        transform(&settings)
        do {
            try settingsStore.saveSettings(settings)
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }

        if settings.adhan.showDockIcon != previousShowDockIcon {
            applyDockIconPolicy()
        }
        if settings.adhan.launchAtLogin != previousLaunchAtLogin {
            applyLaunchAtLogin(enabled: settings.adhan.launchAtLogin)
        }

        Task {
            await refreshSchedule(force: true)
        }
    }

    /// Refreshes the schedule. A request made while a refresh is running is queued and runs
    /// right after it with the latest settings, so rapid setting changes are never lost.
    func refreshSchedule(now: Date = Date(), force: Bool = false) async {
        guard refreshCoalescer.begin(force: force) else { return }
        isRefreshing = true

        var runNow = now
        var runForce = force
        while true {
            await performRefresh(now: runNow, force: runForce)
            guard let queuedForce = refreshCoalescer.finish() else { break }
            runNow = Date()
            runForce = queuedForce
        }

        isRefreshing = false
    }

    private func performRefresh(now: Date, force: Bool) async {
        if !force && !refreshBackoff.canRetry(at: now) {
            return
        }

        retryRefreshTask?.cancel()
        retryRefreshTask = nil

        let tz = activeTimeZone
        let location = settings.selectedLocation

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = tz
        let yesterdayDate = gregorian.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrowDate = gregorian.date(byAdding: .day, value: 1, to: now) ?? now
        let dayAfterDate = gregorian.date(byAdding: .day, value: 2, to: now) ?? tomorrowDate

        let yesterdayComponents = gregorian.dateComponents([.year, .month, .day], from: yesterdayDate)
        let todayComponents = gregorian.dateComponents([.year, .month, .day], from: now)
        let tomorrowComponents = gregorian.dateComponents([.year, .month, .day], from: tomorrowDate)
        let dayAfterComponents = gregorian.dateComponents([.year, .month, .day], from: dayAfterDate)

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
            let dayAfter = try await provider.prayerTimes(
                for: dayAfterComponents,
                location: location,
                timeZone: tz,
                settings: settings
            )

            yesterdaySchedule = yesterday
            todaySchedule = today
            tomorrowSchedule = tomorrow
            dayAfterSchedule = dayAfter

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
            if (try? settingsStore.saveWidgetSnapshot(snapshot)) != nil {
                let nextFingerprint = WidgetFingerprint(snapshot: snapshot, settings: settings)
                if WidgetReloadPolicy.shouldReload(previous: lastWidgetFingerprint, next: nextFingerprint) {
                    lastWidgetFingerprint = nextFingerprint
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }

            scheduler.arm(
                schedules: [yesterday, today, tomorrow, dayAfter],
                settings: settings,
                timeZone: tz,
                now: now
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
        if isPlayingAdhan && currentPlayingPrayer == prayer {
            audioPlayer.stop()
            return
        }
        let choice = settings.adhan.audioPerPrayer[prayer] ?? .bundledPlaceholder
        let resolvedChoice: PrayerAudioChoice = (choice == .none) ? .bundledPlaceholder : choice
        audioPlayer.play(
            prayer: prayer,
            choice: resolvedChoice,
            postAdhanDoa: .none,
            settings: settings.adhan,
            language: settings.language
        )
    }

    func setLiveVolume(_ volume: Double) {
        audioPlayer.setLiveVolume(volume)
    }

    func commitVolume(_ volume: Double) {
        let clamped = max(0, min(1, volume))
        updateSettings { $0.adhan.volume = clamped }
    }

    func importAudioFile(from url: URL) {
        do {
            let clip = try audioPlayer.importAudio(from: url)
            updateSettings { settings in
                settings.adhan.importedClips.append(clip)
            }
        } catch let importError as AudioImportError {
            statusMessage = importError.localizedDescription(for: settings.language)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func renameImportedClip(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSettings { settings in
            if let index = settings.adhan.importedClips.firstIndex(where: { $0.id == id }) {
                settings.adhan.importedClips[index].displayName = trimmed
            }
        }
    }

    func deleteImportedClip(_ clip: ImportedAudioClip) {
        audioPlayer.removeImportedAudio(clip)
        var affected: [Prayer] = []
        updateSettings { settings in
            affected = settings.adhan.removeImportedClip(id: clip.id)
        }
        if !affected.isEmpty {
            let names = affected
                .map { $0.localizedName(for: settings.language) }
                .joined(separator: settings.language == .persian ? "، " : ", ")
            statusMessage = LocalizedStrings.format(
                "adhan.clips.reassigned_notice",
                language: settings.language,
                names
            )
        }
    }

    func syncSystemStatuses() async {
        syncLaunchAtLoginStatus(updateStoredToggle: true)
        notificationAuthorizationStatus = await scheduler.currentNotificationAuthorizationStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        updateSettings { $0.adhan.launchAtLogin = enabled }
    }

    func openNotificationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
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

    private func syncLaunchAtLoginStatus(updateStoredToggle: Bool) {
        let currentStatus = SMAppService.mainApp.status
        launchAtLoginStatus = currentStatus
        guard updateStoredToggle else { return }

        let effectiveEnabled = (currentStatus == .enabled || currentStatus == .requiresApproval)
        if settings.adhan.launchAtLogin != effectiveEnabled {
            settings.adhan.launchAtLogin = effectiveEnabled
            try? settingsStore.saveSettings(settings)
        }
    }

    private func applyLaunchAtLogin(enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        syncLaunchAtLoginStatus(updateStoredToggle: false)
    }

    /// Fires a single refresh right after the next prayer boundary passes (no 1 Hz polling).
    private func scheduleBoundaryRefresh(for targetDate: Date, now: Date) {
        boundaryRefreshTask?.cancel()
        let delay = max(0.05, targetDate.timeIntervalSince(now) + 0.05)
        boundaryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // Drop the handle first: the refresh reschedules this task and must not cancel
            // the task it is running in (that would cancel its own network fetch).
            self.boundaryRefreshTask = nil
            await self.refreshSchedule(force: false)
        }
    }

    private func scheduleRetryRefresh(after delay: TimeInterval) {
        retryRefreshTask?.cancel()
        retryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // Same as above: `performRefresh` cancels `retryRefreshTask` before fetching.
            self.retryRefreshTask = nil
            await self.refreshSchedule(force: false)
        }
    }
}
