import Foundation
import Testing
@testable import OwghatCore

@Suite("AdhanPlanner, AdhanFireDecision, and NotificationPlan")
struct AdhanPlannerAndNotificationTests {
    private let calculator = AstronomicalPrayerCalculator()
    private let planner = AdhanPlanner()
    private let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
    private let berlinTZ = TimeZone(identifier: "Europe/Berlin")!

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    @Test("Plans 48h horizon across Tehran and Europe/Berlin DST transitions ignoring visiblePrayers")
    func multiDayHorizonDstAndHiddenPrayers() throws {
        let berlin = GeoLocation(
            id: "de-berlin",
            name: "Berlin",
            persianName: "برلین",
            countryCode: "DE",
            latitude: 52.5200,
            longitude: 13.4050,
            timeZoneIdentifier: "Europe/Berlin"
        )
        // Europe/Berlin springs forward on 2025-03-30 (02:00 -> 03:00).
        let day1 = try calculator.calculate(for: DateComponents(year: 2025, month: 3, day: 29), location: berlin, timeZone: berlinTZ, method: .mwl)
        let day2 = try calculator.calculate(for: DateComponents(year: 2025, month: 3, day: 30), location: berlin, timeZone: berlinTZ, method: .mwl)
        let day3 = try calculator.calculate(for: DateComponents(year: 2025, month: 3, day: 31), location: berlin, timeZone: berlinTZ, method: .mwl)

        var adhanSettings = AdhanSettings(
            audioPerPrayer: [
                .fajr: .bundledPlaceholder,
                .dhuhr: .bundledPlaceholder,
                .maghrib: .bundledPlaceholder,
                .isha: .bundledPlaceholder
            ],
            preAdhanReminderMinutes: 15,
            postAdhanDoaClip: .bundledPlaceholder,
            notificationsEnabled: true
        )
        adhanSettings.mutedDateKey = nil

        // Hide .isha and .maghrib from display settings; planner must still schedule all 4 Adhan prayers.
        var appSettings = AppSettings.default
        appSettings.visiblePrayers = [.fajr, .dhuhr]
        appSettings.adhan = adhanSettings

        let now = makeDate(year: 2025, month: 3, day: 29, hour: 10, minute: 0, timeZone: berlinTZ)
        let events = planner.plan(
            schedules: [day1, day2, day3],
            settings: appSettings.adhan,
            timeZone: berlinTZ,
            now: now,
            horizon: 48 * 3600
        )

        let adhanPrayers = events.filter { $0.kind == .adhan }.map(\.prayer)
        #expect(adhanPrayers.contains(.isha))
        #expect(adhanPrayers.contains(.maghrib))
        #expect(!adhanPrayers.contains(.sunrise))
        #expect(!adhanPrayers.contains(.midnight))

        // Verify chronological ordering across DST spring-forward boundary.
        for pair in zip(events, events.dropFirst()) {
            #expect(pair.0.fireDate <= pair.1.fireDate)
        }
        #expect(events.allSatisfy { $0.fireDate > now && $0.fireDate <= now.addingTimeInterval(48 * 3600) })

        // Fall-back DST day in Europe/Berlin (2025-10-26)
        let fall1 = try calculator.calculate(for: DateComponents(year: 2025, month: 10, day: 25), location: berlin, timeZone: berlinTZ, method: .mwl)
        let fall2 = try calculator.calculate(for: DateComponents(year: 2025, month: 10, day: 26), location: berlin, timeZone: berlinTZ, method: .mwl)
        let fallNow = makeDate(year: 2025, month: 10, day: 25, hour: 20, minute: 0, timeZone: berlinTZ)
        let fallEvents = planner.plan(
            schedules: [fall1, fall2],
            settings: adhanSettings,
            timeZone: berlinTZ,
            now: fallNow
        )
        #expect(fallEvents.contains { $0.id == "adhan-2025-10-26-fajr" })
        #expect(fallEvents.contains { $0.id == "reminder-2025-10-26-fajr-15" })
    }

    @Test("Mutes only the muted local date in location time zone and restores alerts next day")
    func muteScopedToLocationTimeZone() throws {
        let day1 = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let day2 = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )

        // Mute 2025-03-21 in Tehran; silent banner enabled.
        let silentBannerSettings = AdhanSettings(
            mutedDateKey: "2025-03-21",
            audioPerPrayer: [.fajr: .bundledPlaceholder, .dhuhr: .bundledPlaceholder, .maghrib: .bundledPlaceholder],
            notificationsEnabled: true,
            silentNotificationsOnMutedDays: true
        )

        // Check at 2025-03-21 15:00 in Asia/Tehran (equivalent to 11:30 UTC).
        let afternoon = makeDate(year: 2025, month: 3, day: 21, hour: 15, minute: 0, timeZone: tehranTZ)
        let eventsWithBanner = planner.plan(
            schedules: [day1, day2],
            settings: silentBannerSettings,
            timeZone: tehranTZ,
            now: afternoon
        )

        let todayMaghrib = eventsWithBanner.first { $0.id == "adhan-2025-03-21-maghrib" }
        #expect(todayMaghrib != nil)
        #expect(todayMaghrib?.audio == nil)
        #expect(todayMaghrib?.playsDoa == false)
        #expect(todayMaghrib?.postsNotification == true)
        #expect(todayMaghrib?.notificationSound == false)

        // Tomorrow's Fajr is unmuted even if mutedDateKey is still "2025-03-21".
        let tomorrowFajr = eventsWithBanner.first { $0.id == "adhan-2025-03-22-fajr" }
        #expect(tomorrowFajr?.audio == .bundledPlaceholder)
        #expect(tomorrowFajr?.notificationSound == true)

        // With silentNotificationsOnMutedDays = false, today's muted events are suppressed entirely.
        var noNotifOnMute = silentBannerSettings
        noNotifOnMute.silentNotificationsOnMutedDays = false
        let eventsNoMuteNotif = planner.plan(
            schedules: [day1, day2],
            settings: noNotifOnMute,
            timeZone: tehranTZ,
            now: afternoon
        )
        #expect(!eventsNoMuteNotif.contains { $0.dateKey == "2025-03-21" })
        #expect(eventsNoMuteNotif.contains { $0.id == "adhan-2025-03-22-fajr" })
    }

    @Test("Handles .none audio as notification-only when notifications enabled and no event when disabled")
    func noneAudioHandling() throws {
        let day = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )
        let morning = makeDate(year: 2025, month: 3, day: 21, hour: 8, minute: 0, timeZone: tehranTZ)

        let notifOnlySettings = AdhanSettings(
            audioPerPrayer: [.dhuhr: .none],
            notificationsEnabled: true
        )
        let eventsWithNotif = planner.plan(schedules: [day], settings: notifOnlySettings, timeZone: tehranTZ, now: morning)
        let dhuhrEvent = eventsWithNotif.first { $0.prayer == .dhuhr && $0.kind == .adhan }
        #expect(dhuhrEvent?.audio == nil)
        #expect(dhuhrEvent?.postsNotification == true)
        #expect(dhuhrEvent?.notificationSound == true)

        let disabledSettings = AdhanSettings(
            audioPerPrayer: [.dhuhr: .none],
            notificationsEnabled: false
        )
        let eventsDisabled = planner.plan(schedules: [day], settings: disabledSettings, timeZone: tehranTZ, now: morning)
        #expect(!eventsDisabled.contains { $0.prayer == .dhuhr })
    }

    @Test("Plans pre-Adhan reminder crossing midnight for 00:xx Fajr and respects manual overrides")
    func midnightCrossingReminderAndOverrides() throws {
        let osloTZ = TimeZone(identifier: "Europe/Oslo")!
        let tromso = GeoLocation(
            id: "no-tromso",
            name: "Tromsø",
            persianName: "ترومسو",
            countryCode: "NO",
            latitude: 69.6492,
            longitude: 18.9553,
            timeZoneIdentifier: "Europe/Oslo"
        )

        // Manual override placing 2025-05-10 Fajr at 00:15 so a 30m reminder fires on 2025-05-09 at 23:45.
        let manualSchedule = try calculator.calculate(
            for: DateComponents(year: 2025, month: 5, day: 10),
            location: tromso,
            timeZone: osloTZ,
            method: .mwl,
            manualOverrides: ["2025-05-10": [.fajr: LocalTimeOfDay(hour: 0, minute: 15)]]
        )

        let now = makeDate(year: 2025, month: 5, day: 9, hour: 23, minute: 30, timeZone: osloTZ)
        let settings = AdhanSettings(
            audioPerPrayer: [.fajr: .bundledPlaceholder],
            preAdhanReminderMinutes: 30,
            notificationsEnabled: true
        )

        let events = planner.plan(
            schedules: [manualSchedule],
            settings: settings,
            timeZone: osloTZ,
            now: now
        )

        let reminder = events.first { $0.id == "reminder-2025-05-10-fajr-30" }
        let fajr = events.first { $0.id == "adhan-2025-05-10-fajr" }
        #expect(reminder != nil)
        #expect(fajr != nil)
        #expect(reminder!.fireDate == makeDate(year: 2025, month: 5, day: 9, hour: 23, minute: 45, timeZone: osloTZ))
        #expect(fajr!.fireDate == makeDate(year: 2025, month: 5, day: 10, hour: 0, minute: 15, timeZone: osloTZ))
        #expect(events.first?.id == reminder?.id)
    }

    @Test("AdhanFireDecision returns .play within grace window and .notifyMissed or .skip when late")
    func fireDecisionGraceWindow() {
        let fireDate = makeDate(year: 2025, month: 3, day: 21, hour: 4, minute: 43, timeZone: tehranTZ)
        let adhanEvent = AdhanEvent(
            id: "adhan-2025-03-21-fajr",
            kind: .adhan,
            prayer: .fajr,
            dateKey: "2025-03-21",
            fireDate: fireDate,
            audio: .bundledPlaceholder,
            playsDoa: false,
            postsNotification: true,
            notificationSound: true
        )
        let reminderEvent = AdhanEvent(
            id: "reminder-2025-03-21-fajr-10",
            kind: .reminder(minutesBefore: 10),
            prayer: .fajr,
            dateKey: "2025-03-21",
            fireDate: fireDate,
            audio: nil,
            playsDoa: false,
            postsNotification: true,
            notificationSound: true
        )

        // 30s late -> .play
        #expect(AdhanFireDecision.evaluate(event: adhanEvent, now: fireDate.addingTimeInterval(30), graceWindow: 90) == .play)
        // Exactly 90s -> .play
        #expect(AdhanFireDecision.evaluate(event: adhanEvent, now: fireDate.addingTimeInterval(90), graceWindow: 90) == .play)
        // 2h late after sleep -> .notifyMissed (if notifications on) or .skip (if off)
        #expect(AdhanFireDecision.evaluate(event: adhanEvent, now: fireDate.addingTimeInterval(7200), graceWindow: 90, notificationsEnabled: true) == .notifyMissed)
        #expect(AdhanFireDecision.evaluate(event: adhanEvent, now: fireDate.addingTimeInterval(7200), graceWindow: 90, notificationsEnabled: false) == .skip)
        // Stale reminder is skipped rather than firing late
        #expect(AdhanFireDecision.evaluate(event: reminderEvent, now: fireDate.addingTimeInterval(7200), graceWindow: 90, notificationsEnabled: true) == .skip)
    }

    @Test("NotificationPlan preserves snoozes, enforces cap, and produces empty diff on stable re-plan")
    func notificationPlanDiffCapAndSnoozes() throws {
        let day1 = try calculator.calculate(for: DateComponents(year: 2025, month: 3, day: 21), location: .tehran, timeZone: tehranTZ, method: .tehran)
        let day2 = try calculator.calculate(for: DateComponents(year: 2025, month: 3, day: 22), location: .tehran, timeZone: tehranTZ, method: .tehran)

        let now = makeDate(year: 2025, month: 3, day: 21, hour: 3, minute: 0, timeZone: tehranTZ)
        let settings = AdhanSettings(
            audioPerPrayer: [.fajr: .bundledPlaceholder, .dhuhr: .bundledPlaceholder, .maghrib: .bundledPlaceholder, .isha: .bundledPlaceholder],
            preAdhanReminderMinutes: 10,
            notificationsEnabled: true
        )
        let events = planner.plan(schedules: [day1, day2], settings: settings, timeZone: tehranTZ, now: now)

        // Enforce cap of 4 pending notifications.
        let initialPlan = NotificationPlan.build(events: events, pendingRequests: [], maxPendingCount: 4)
        #expect(initialPlan.toAdd.count == 4)
        #expect(initialPlan.toRemove.isEmpty)

        // Simulate existing pending requests including a snooze and a stale managed request.
        var snapshots = initialPlan.toAdd.map {
            PendingNotificationSnapshot(
                id: $0.id,
                fireDate: $0.fireDate,
                hasSound: $0.hasSound,
                willPlayAudio: $0.willPlayAudio
            )
        }
        let snoozeID = "owghat-snooze-12345"
        let staleID = "owghat-adhan-2025-03-20-isha"
        snapshots.append(PendingNotificationSnapshot(id: snoozeID, fireDate: now.addingTimeInterval(300), hasSound: true))
        snapshots.append(PendingNotificationSnapshot(id: staleID, fireDate: now.addingTimeInterval(600), hasSound: true))

        let replan = NotificationPlan.build(events: events, pendingRequests: snapshots, maxPendingCount: 4)
        #expect(replan.toKeep.count == 4)
        #expect(replan.toAdd.isEmpty)
        #expect(replan.toRemove == [staleID])
        #expect(!replan.toRemove.contains(snoozeID))

        // Re-arming identical schedule with no stale requests changes nothing.
        let cleanSnapshots = initialPlan.toAdd.map {
            PendingNotificationSnapshot(id: $0.id, fireDate: $0.fireDate, hasSound: $0.hasSound, willPlayAudio: $0.willPlayAudio)
        }
        let stablePlan = NotificationPlan.build(events: events, pendingRequests: cleanSnapshots, maxPendingCount: 4)
        #expect(stablePlan.toKeep.count == 4)
        #expect(stablePlan.toAdd.isEmpty)
        #expect(stablePlan.toRemove.isEmpty)
    }

    @Test("Deleting an imported clip reassigns prayers to bundled tone and decodes legacy AdhanSettings")
    func clipDeletionReassignmentAndLegacyDecode() throws {
        let clipID = UUID()
        var settings = AdhanSettings(
            audioPerPrayer: [
                .fajr: .imported(clipID),
                .dhuhr: .bundledPlaceholder,
                .maghrib: .imported(clipID),
                .isha: .none
            ],
            postAdhanDoaClip: .imported(clipID),
            importedClips: [ImportedAudioClip(id: clipID, displayName: "Custom", storedFileName: "custom.m4a")]
        )

        let affected = settings.removeImportedClip(id: clipID)
        #expect(affected == [.fajr, .maghrib])
        #expect(settings.importedClips.isEmpty)
        #expect(settings.audioPerPrayer[.fajr] == .bundledPlaceholder)
        #expect(settings.audioPerPrayer[.maghrib] == .bundledPlaceholder)
        #expect(settings.audioPerPrayer[.dhuhr] == .bundledPlaceholder)
        #expect(settings.audioPerPrayer[.isha] == PrayerAudioChoice.none)
        #expect(settings.postAdhanDoaClip == PrayerAudioChoice.none)

        // Legacy JSON without silentNotificationsOnMutedDays decodes with default true.
        let legacyJSON = """
        {
          "audioPerPrayer": [],
          "volume": 0.8,
          "fadeInSeconds": 2.0,
          "postAdhanDoaClip": { "none": {} },
          "notificationsEnabled": true,
          "launchAtLogin": false,
          "showDockIcon": false,
          "importedClips": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AdhanSettings.self, from: legacyJSON)
        #expect(decoded.silentNotificationsOnMutedDays == true)
    }

    @Test("Respects offsets, overrides, and location midnight mute boundary regardless of UTC day")
    func offsetsAndTehranMidnightMuteBoundary() throws {
        // 2025-03-21 20:30 UTC is 2025-03-22 00:00 +03:30 in Asia/Tehran (already the next day in Tehran).
        let tehranDay21 = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 21),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran,
            offsets: [.maghrib: 4],
            manualOverrides: ["2025-03-21": [.dhuhr: LocalTimeOfDay(hour: 12, minute: 25)]]
        )
        let tehranDay22 = try calculator.calculate(
            for: DateComponents(year: 2025, month: 3, day: 22),
            location: .tehran,
            timeZone: tehranTZ,
            method: .tehran
        )

        let settings = AdhanSettings(
            mutedDateKey: "2025-03-21",
            audioPerPrayer: [.fajr: .bundledPlaceholder, .dhuhr: .bundledPlaceholder, .maghrib: .bundledPlaceholder],
            notificationsEnabled: true,
            silentNotificationsOnMutedDays: false
        )

        // At 2025-03-21 12:00 +03:30, Dhuhr and Maghrib on 2025-03-21 are muted, while 2025-03-22 Fajr is unmuted.
        let tehranNoon = makeDate(year: 2025, month: 3, day: 21, hour: 12, minute: 0, timeZone: tehranTZ)
        let mutedPlan = planner.plan(schedules: [tehranDay21, tehranDay22], settings: settings, timeZone: tehranTZ, now: tehranNoon)
        #expect(!mutedPlan.contains { $0.dateKey == "2025-03-21" })
        #expect(mutedPlan.first?.id == "adhan-2025-03-22-fajr")

        // When unmuted, planner preserves exact overridden Dhuhr (12:25) and offset Maghrib.
        var unmutedSettings = settings
        unmutedSettings.mutedDateKey = nil
        let unmutedPlan = planner.plan(schedules: [tehranDay21], settings: unmutedSettings, timeZone: tehranTZ, now: tehranNoon)
        let dhuhr = unmutedPlan.first { $0.prayer == .dhuhr }
        let maghrib = unmutedPlan.first { $0.prayer == .maghrib }
        #expect(dhuhr?.fireDate == makeDate(year: 2025, month: 3, day: 21, hour: 12, minute: 25, timeZone: tehranTZ))
        #expect(maghrib?.fireDate == tehranDay21.time(for: .maghrib))
    }
}
