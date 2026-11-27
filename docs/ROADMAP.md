# Owghat Roadmap

This document tracks the development milestones for Owghat (اوقات), a native macOS prayer-times app written in Swift 6 and SwiftUI.

## M0 — Repo + Scaffold + CI
- [x] Initialize repository structure (`Owghat`, `OwghatWidget`, `Packages/OwghatCore`, `OwghatTests`)
- [x] Author `project.yml` and commit generated `Owghat.xcodeproj`
- [x] Configure shared App Group (`group.<bundle-prefix>.owghat`) and placeholder bundle IDs
- [x] Set up `Localizable.xcstrings` (`fa`, `en`), asset catalogs, and royalty-free placeholder chime
- [x] Configure GitHub Actions CI (`macos-15`) for `swift test` and `xcodebuild`
- [x] Add `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, MIT `LICENSE`, and issue templates

## M1 — Core Engine (Offline) + Tests
- [x] Define `PrayerTimesProvider` protocol and `OfflinePrayerTimesProvider` astronomical calculator
- [x] Support Tehran (Institute of Geophysics: Fajr 17.7°, Maghrib 4.5°, Isha 14°, Shia midnight) as default, plus Jafari, MWL, Umm al-Qura, Egyptian, Karachi, ISNA, and custom parameters
- [x] Implement per-prayer minute offsets and date-specific manual overrides
- [x] Implement Jalali (`.persian`), Hijri (`.islamicUmmAlQura` / `.islamicCivil` with ±day offset), and Gregorian calendar converters
- [x] Bundle Iranian and major world cities JSON and religious/official occasions JSON
- [x] Write `OwghatCoreTests` covering Tehran dates, offsets/overrides, calendar offsets, midnight rollover, and DST/timezone edge cases

## M2 — Menu Bar Panel
- [x] Polish `MenuBarExtra` `.window` popover layout, visual hierarchy, and keyboard navigation
- [x] Add live countdown ring/header with next prayer highlight and full RTL/LTR layout polish
- [x] Support all menu bar label variants (icon only, next prayer + time, countdown, Persian/Latin digits)
- [x] Add quick actions in panel (mute today, stop playing Adhan, refresh online comparison, open settings)

## M3 — Adhan Scheduler + Audio + Notifications + Launch at Login
- [ ] Harden timer arming and re-arming across `NSWorkspace.didWakeNotification`, time zone changes, and day rollover
- [ ] Complete `AVAudioPlayer` fade-in, per-prayer audio routing, and post-Adhan Doa sequencing
- [ ] Add pre-Adhan reminder scheduling (N minutes before)
- [ ] Wire `UNUserNotificationCenter` backup alerts with Stop and Snooze actions
- [ ] Complete custom audio file import/management in Application Support
- [ ] Finalize `SMAppService.mainApp` launch-at-login and Dock icon toggle (`LSUIElement`)

## M4 — Widgets
- [ ] Refine Small, Medium, and Large WidgetKit layouts for Desktop and Notification Center
- [ ] Verify timeline entries at every prayer boundary and calendar midnight
- [ ] Complete `AppIntents` `WidgetConfigurationIntent` so users can choose displayed prayers per widget instance
- [ ] Ensure `WidgetCenter.shared.reloadAllTimelines()` triggers smoothly on settings/location changes

## M5 — Settings and Editing
- [ ] Build full editing controls for per-prayer minute offsets and per-date manual overrides
- [ ] Build custom calculation method editor (Fajr/Maghrib/Isha angles, sunset delays, midnight mode)
- [ ] Complete location picker: searchable bundled city list, CoreLocation auto-detection, and custom lat/long/timezone entry
- [ ] Add appearance controls: Persian/English language switcher, Persian/Latin digits, theme (system/light/dark), accent color picker
- [ ] Add JSON settings and custom events import/export UI

## M6 — Events and Occasions
- [ ] Add full occasion manager UI to browse, edit, and hide bundled Jalali/Hijri occasions
- [ ] Add custom event editor supporting one-off and yearly recurring events in Jalali, Hijri, or Gregorian calendars
- [ ] Connect optional event reminders to `UNUserNotificationCenter`

## M7 — Online Provider + Comparison
- [ ] Complete `AladhanPrayerTimesProvider` (`method=7` Tehran and mapped presets) with disk caching per day and location
- [ ] Surface offline-vs-online minute differences in the panel and settings UI
- [ ] Add manual refresh and error/offline state indicators without impacting offline reliability

## M8 — Signing, Notarization, DMG Release
- [ ] Configure Developer ID signing, hardened runtime, and provisioning for App + Widget extension
- [ ] Automate Apple notarization and stapling in release workflow
- [ ] Package signed `.dmg` / `.zip` archive with Sparkle or GitHub Releases release notes
