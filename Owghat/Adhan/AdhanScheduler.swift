import AppKit
import Foundation
import OwghatCore
import UserNotifications

/// Schedules timers and backup local notifications for upcoming prayers and pre-Adhan reminders.
@MainActor
final class AdhanScheduler: NSObject, UNUserNotificationCenterDelegate {
    private enum Constants {
        static let categoryID = "OWGHAT_ADHAN_ALERT"
        static let stopActionID = "OWGHAT_STOP_ADHAN"
        static let snoozeActionID = "OWGHAT_SNOOZE_ADHAN"
    }

    private let audioPlayer: AdhanAudioPlayer
    private var armedTimer: Timer?
    private var reminderTimer: Timer?
    private var systemObservers: [NSObjectProtocol] = []
    var onScheduleNeedsRefresh: (() -> Void)?

    init(audioPlayer: AdhanAudioPlayer) {
        self.audioPlayer = audioPlayer
        super.init()
        configureNotificationCategories()
        installSystemObservers()
    }

    deinit {
        armedTimer?.invalidate()
        reminderTimer?.invalidate()
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Arms timers and local notifications for the next prayer event.
    func arm(
        nextResolution: NextPrayerResolution?,
        todaySchedule: DailyPrayerTimes?,
        settings: AppSettings,
        timeZone: TimeZone
    ) {
        armedTimer?.invalidate()
        reminderTimer?.invalidate()
        armedTimer = nil
        reminderTimer = nil

        guard let nextResolution else { return }
        let now = Date()
        let entry = nextResolution.entry
        let interval = entry.date.timeIntervalSince(now)
        guard interval > 0 else { return }

        let choice = settings.adhan.audioPerPrayer[entry.prayer] ?? .none
        let isMuted = settings.adhan.isMuted(on: entry.date, timeZone: timeZone)

        if !isMuted && choice != .none {
            let timer = Timer(fire: entry.date, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.audioPlayer.play(
                        choice: choice,
                        postAdhanDoa: settings.adhan.postAdhanDoaClip,
                        settings: settings.adhan
                    )
                    self.onScheduleNeedsRefresh?()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            armedTimer = timer
        }

        if let reminderMinutes = settings.adhan.preAdhanReminderMinutes, reminderMinutes > 0 {
            let reminderDate = entry.date.addingTimeInterval(TimeInterval(-reminderMinutes * 60))
            if reminderDate > now {
                let rTimer = Timer(fire: reminderDate, interval: 0, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.deliverImmediateReminderNotification(
                            prayer: entry.prayer,
                            minutesBefore: reminderMinutes,
                            language: settings.language
                        )
                    }
                }
                RunLoop.main.add(rTimer, forMode: .common)
                reminderTimer = rTimer
            }
        }

        if settings.adhan.notificationsEnabled {
            scheduleBackupNotifications(schedule: todaySchedule, settings: settings, timeZone: timeZone)
        }
    }

    private func installSystemObservers() {
        let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onScheduleNeedsRefresh?()
            }
        }

        let tzObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onScheduleNeedsRefresh?()
            }
        }

        let dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onScheduleNeedsRefresh?()
            }
        }

        systemObservers = [wakeObserver, tzObserver, dayObserver]
    }

    private func configureNotificationCategories() {
        let stopAction = UNNotificationAction(
            identifier: Constants.stopActionID,
            title: "Stop",
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Constants.snoozeActionID,
            title: "Snooze 5 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Constants.categoryID,
            actions: [stopAction, snoozeAction],
            intentIdentifiers: []
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    private func scheduleBackupNotifications(
        schedule: DailyPrayerTimes?,
        settings: AppSettings,
        timeZone: TimeZone
    ) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard let schedule else { return }
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        for entry in schedule.orderedEntries(filteredBy: settings.visiblePrayers) where entry.date > now {
            guard entry.prayer.isAdhanPrayer else { continue }
            let content = UNMutableNotificationContent()
            content.title = settings.language == .persian ? AppConfig.persianAppName : AppConfig.appName
            content.body = entry.prayer.localizedName(for: settings.language)
            content.sound = .default
            content.categoryIdentifier = Constants.categoryID

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "owghat-\(schedule.dateKey)-\(entry.prayer.rawValue)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func deliverImmediateReminderNotification(
        prayer: Prayer,
        minutesBefore: Int,
        language: AppLanguage
    ) {
        let content = UNMutableNotificationContent()
        content.title = language == .persian ? AppConfig.persianAppName : AppConfig.appName
        let prayerTitle = prayer.localizedName(for: language)
        content.body = language == .persian
            ? "\(DigitFormatter.toPersian(String(minutesBefore))) دقیقه تا \(prayerTitle)"
            : "\(minutesBefore) min until \(prayerTitle)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "owghat-reminder-\(prayer.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        await MainActor.run {
            if actionID == Constants.stopActionID {
                audioPlayer.stop()
            } else if actionID == Constants.snoozeActionID {
                audioPlayer.stop()
                let snoozeContent = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent
                    ?? UNMutableNotificationContent()
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "owghat-snooze-\(UUID().uuidString)",
                    content: snoozeContent,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
}
