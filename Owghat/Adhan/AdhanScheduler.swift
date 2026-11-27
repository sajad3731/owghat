import AppKit
import Foundation
import OwghatCore
import UserNotifications

/// Releases a `ProcessInfo` activity assertion automatically if deallocated early.
private final class ActivityAssertionBox: @unchecked Sendable {
    private var token: (any NSObjectProtocol)?

    init(reason: String) {
        self.token = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: reason
        )
    }

    func end() {
        if let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }

    deinit {
        if let token {
            ProcessInfo.processInfo.endActivity(token)
        }
    }
}

/// Executes scheduled Adhan events, App Nap assertions, and `UNUserNotificationCenter` diffs.
@MainActor
final class AdhanScheduler: NSObject, UNUserNotificationCenterDelegate {
    private enum Constants {
        static let categoryID = "OWGHAT_ADHAN_ALERT"
        static let stopActionID = "OWGHAT_STOP_ADHAN"
        static let snoozeActionID = "OWGHAT_SNOOZE_ADHAN"
        static let willPlayAudioKey = "willPlayAudio"
        static let appNapLeadSeconds: TimeInterval = 60
    }

    private let audioPlayer: AdhanAudioPlayer
    private let planner = AdhanPlanner()
    private var earliestEventTask: Task<Void, Never>?
    private var appNapTask: Task<Void, Never>?
    private var notificationSyncTask: Task<Void, Never>?
    private var midnightTask: Task<Void, Never>?
    private var appNapAssertion: ActivityAssertionBox?
    private var systemObservers: [NSObjectProtocol] = []
    private var scheduledNotificationIDs = Set<String>()

    var onScheduleNeedsRefresh: (() -> Void)?
    var onOpenPanelOrWindow: (() -> Void)?

    init(audioPlayer: AdhanAudioPlayer) {
        self.audioPlayer = audioPlayer
        super.init()
        UNUserNotificationCenter.current().delegate = self
        configureNotificationCategories(language: .persian)
        installSystemObservers()
    }

    deinit {
        earliestEventTask?.cancel()
        appNapTask?.cancel()
        notificationSyncTask?.cancel()
        midnightTask?.cancel()
    }

    func requestNotificationPermissionOnce() async -> UNAuthorizationStatus {
        let current = await fetchAuthorizationStatus()
        if current == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return await fetchAuthorizationStatus()
        }
        return current
    }

    func currentNotificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await fetchAuthorizationStatus()
    }

    /// Plans upcoming events across `schedules`, arms the earliest timer, and diffs system notifications.
    func arm(
        schedules: [DailyPrayerTimes],
        settings: AppSettings,
        timeZone: TimeZone,
        now: Date = Date()
    ) {
        earliestEventTask?.cancel()
        appNapTask?.cancel()
        notificationSyncTask?.cancel()
        midnightTask?.cancel()
        earliestEventTask = nil
        appNapTask = nil
        notificationSyncTask = nil
        midnightTask = nil
        appNapAssertion?.end()
        appNapAssertion = nil

        configureNotificationCategories(language: settings.language)
        armLocationMidnightObserver(timeZone: timeZone)

        let events = planner.plan(
            schedules: schedules,
            settings: settings.adhan,
            timeZone: timeZone,
            now: now
        )

        if let nextEvent = events.first {
            armEarliestEvent(nextEvent, settings: settings, timeZone: timeZone, now: now)
        }

        notificationSyncTask = Task { [weak self] in
            await self?.applyNotificationPlan(events: events, settings: settings, timeZone: timeZone)
        }
    }

    private func armEarliestEvent(
        _ event: AdhanEvent,
        settings: AppSettings,
        timeZone: TimeZone,
        now: Date
    ) {
        let delay = max(0, event.fireDate.timeIntervalSince(now))

        if delay <= Constants.appNapLeadSeconds {
            appNapAssertion = ActivityAssertionBox(reason: "Preparing scheduled Adhan event")
        } else {
            let leadDelay = delay - Constants.appNapLeadSeconds
            appNapTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(leadDelay))
                guard !Task.isCancelled, let self else { return }
                self.appNapAssertion = ActivityAssertionBox(reason: "Preparing scheduled Adhan event")
            }
        }

        earliestEventTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.executeEvent(event, settings: settings, timeZone: timeZone)
        }
    }

    private func executeEvent(_ event: AdhanEvent, settings: AppSettings, timeZone: TimeZone) {
        let now = Date()
        let decision = AdhanFireDecision.evaluate(
            event: event,
            now: now,
            graceWindow: AdhanFireDecision.defaultGraceWindow,
            notificationsEnabled: settings.adhan.notificationsEnabled
        )

        switch decision {
        case .play:
            switch event.kind {
            case .adhan:
                if let audioChoice = event.audio {
                    audioPlayer.play(
                        prayer: event.prayer,
                        choice: audioChoice,
                        postAdhanDoa: event.playsDoa ? settings.adhan.postAdhanDoaClip : .none,
                        settings: settings.adhan,
                        language: settings.language
                    )
                }
            case .reminder(let minutesBefore):
                let requestID = NotificationPlan.requestIdentifier(for: event)
                if !scheduledNotificationIDs.contains(requestID) {
                    deliverImmediateReminderNotification(
                        prayer: event.prayer,
                        minutesBefore: minutesBefore,
                        language: settings.language,
                        persianDigits: settings.usePersianDigits,
                        withSound: event.notificationSound
                    )
                }
            }

        case .notifyMissed:
            let pendingID = NotificationPlan.requestIdentifier(for: event)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [pendingID])
            deliverMissedNotification(
                event: event,
                language: settings.language,
                persianDigits: settings.usePersianDigits,
                timeZone: timeZone
            )

        case .skip:
            break
        }

        appNapAssertion?.end()
        appNapAssertion = nil
        onScheduleNeedsRefresh?()
    }

    private func applyNotificationPlan(
        events: [AdhanEvent],
        settings: AppSettings,
        timeZone: TimeZone
    ) async {
        let pendingSnapshots = await fetchPendingNotificationSnapshots()
        guard !Task.isCancelled else { return }

        let plan = NotificationPlan.build(
            events: settings.adhan.notificationsEnabled ? events : [],
            pendingRequests: pendingSnapshots
        )

        scheduledNotificationIDs = Set(plan.toKeep).union(plan.toAdd.map(\.id))

        let center = UNUserNotificationCenter.current()
        if !plan.toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.toRemove)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        for planned in plan.toAdd {
            let content = buildNotificationContent(
                for: planned.event,
                language: settings.language,
                persianDigits: settings.usePersianDigits
            )
            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: planned.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: planned.id,
                content: content,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func buildNotificationContent(
        for event: AdhanEvent,
        language: AppLanguage,
        persianDigits: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = language == .persian ? AppConfig.persianAppName : AppConfig.appName
        let prayerTitle = event.prayer.localizedName(for: language)

        switch event.kind {
        case .adhan:
            content.body = LocalizedStrings.format("notification.adhan.body", language: language, prayerTitle)
            content.categoryIdentifier = Constants.categoryID
        case .reminder(let minutesBefore):
            let mins = DigitFormatter.format(String(minutesBefore), persianDigits: persianDigits)
            content.body = LocalizedStrings.format("notification.reminder.body", language: language, mins, prayerTitle)
        }

        content.sound = event.notificationSound ? .default : nil
        content.userInfo = [
            Constants.willPlayAudioKey: event.audio != nil
        ]
        return content
    }

    private func deliverImmediateReminderNotification(
        prayer: Prayer,
        minutesBefore: Int,
        language: AppLanguage,
        persianDigits: Bool,
        withSound: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = language == .persian ? AppConfig.persianAppName : AppConfig.appName
        let prayerTitle = prayer.localizedName(for: language)
        let mins = DigitFormatter.format(String(minutesBefore), persianDigits: persianDigits)
        content.body = LocalizedStrings.format("notification.reminder.body", language: language, mins, prayerTitle)
        content.sound = withSound ? .default : nil
        let request = UNNotificationRequest(
            identifier: "\(NotificationPlan.reminderRequestPrefix)\(prayer.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func deliverMissedNotification(
        event: AdhanEvent,
        language: AppLanguage,
        persianDigits: Bool,
        timeZone: TimeZone
    ) {
        let content = UNMutableNotificationContent()
        content.title = language == .persian ? AppConfig.persianAppName : AppConfig.appName
        let prayerTitle = event.prayer.localizedName(for: language)
        let timeString = DigitFormatter.formatTime(event.fireDate, timeZone: timeZone, persianDigits: persianDigits)
        content.body = LocalizedStrings.format("notification.missed.body", language: language, prayerTitle, timeString)
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "\(NotificationPlan.missedRequestPrefix)\(event.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Schedules a refresh just after local midnight in the active location's time zone.
    private func armLocationMidnightObserver(timeZone: TimeZone) {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let startOfToday = calendar.startOfDay(for: now)
        guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return
        }
        let delay = max(1.0, nextMidnight.timeIntervalSince(now) + 1.0)
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.onScheduleNeedsRefresh?()
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

    private func configureNotificationCategories(language: AppLanguage) {
        let stopAction = UNNotificationAction(
            identifier: Constants.stopActionID,
            title: LocalizedStrings.string("notification.action.stop", language: language),
            options: [.destructive]
        )
        let snoozeAction = UNNotificationAction(
            identifier: Constants.snoozeActionID,
            title: LocalizedStrings.string("notification.action.snooze", language: language),
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

    private nonisolated func fetchAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    private nonisolated func fetchPendingNotificationSnapshots() async -> [PendingNotificationSnapshot] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.map { req in
            let nextTriggerDate: Date?
            if let calTrigger = req.trigger as? UNCalendarNotificationTrigger {
                nextTriggerDate = calTrigger.nextTriggerDate()
            } else if let intervalTrigger = req.trigger as? UNTimeIntervalNotificationTrigger {
                nextTriggerDate = intervalTrigger.nextTriggerDate()
            } else {
                nextTriggerDate = nil
            }
            let willPlayAudio = (req.content.userInfo[Constants.willPlayAudioKey] as? Bool) ?? false
            return PendingNotificationSnapshot(
                id: req.identifier,
                fireDate: nextTriggerDate,
                hasSound: req.content.sound != nil,
                willPlayAudio: willPlayAudio
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let willPlayAudio = (notification.request.content.userInfo[Constants.willPlayAudioKey] as? Bool) ?? false
        let hasSound = notification.request.content.sound != nil
        if willPlayAudio || !hasSound {
            return [.banner, .list]
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionID = response.actionIdentifier
        let originalTitle = response.notification.request.content.title
        let originalBody = response.notification.request.content.body

        await MainActor.run {
            if actionID == Constants.stopActionID || actionID == Constants.snoozeActionID {
                audioPlayer.stop()
            } else if actionID == UNNotificationDefaultActionIdentifier {
                onOpenPanelOrWindow?()
            }
        }

        if actionID == Constants.snoozeActionID {
            let snoozeContent = UNMutableNotificationContent()
            snoozeContent.title = originalTitle
            snoozeContent.body = originalBody
            snoozeContent.sound = .default
            snoozeContent.categoryIdentifier = Constants.categoryID
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(NotificationPlan.snoozeRequestPrefix)\(UUID().uuidString)",
                content: snoozeContent,
                trigger: trigger
            )
            center.add(request, withCompletionHandler: nil)
        }
    }
}
