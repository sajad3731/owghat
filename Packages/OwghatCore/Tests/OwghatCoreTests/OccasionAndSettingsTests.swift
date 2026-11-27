import Foundation
import Testing
@testable import OwghatCore

@Suite("City Database, Occasions, and Settings Persistence")
struct OccasionAndSettingsTests {
    @Test("Bundled city database searches Tehran in English and Persian")
    func cityDatabaseSearch() {
        let db = CityDatabase()
        #expect(db.cities.count >= 25)
        #expect(db.search("tehran").first?.id == "ir-tehran")
        #expect(db.search("تهران").first?.id == "ir-tehran")
        #expect(db.search("ي").contains { $0.persianName.contains("ی") })
    }

    @Test("OccasionStore resolves bundled Nowruz and supports custom and hidden occasions")
    func occasionFilteringAndCustomization() {
        let tehranTZ = TimeZone(identifier: "Asia/Tehran")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tehranTZ
        let nowruzDate = cal.date(from: DateComponents(year: 2025, month: 3, day: 21, hour: 12))!

        let store = OccasionStore()
        var settings = AppSettings.default

        let defaultMatches = store.occasions(on: nowruzDate, timeZone: tehranTZ, settings: settings)
        #expect(defaultMatches.contains { $0.id == "jalali-nowruz-1" })

        // Hide bundled Nowruz and add a custom Jalali event on 1 Farvardin
        if var bundledNowruz = store.bundledOccasions.first(where: { $0.id == "jalali-nowruz-1" }) {
            bundledNowruz.isHidden = true
            settings.editedBundledOccasions.append(bundledNowruz)
        }
        settings.customOccasions.append(
            Occasion(
                id: "custom-1",
                titleEn: "Family Gathering",
                titleFa: "دورهمی خانوادگی",
                calendarKey: OccasionCalendarKey(calendar: .jalali, month: 1, day: 1),
                hasReminder: true,
                reminderMinutesBefore: 30
            )
        )

        let updatedMatches = store.occasions(on: nowruzDate, timeZone: tehranTZ, settings: settings)
        #expect(!updatedMatches.contains { $0.id == "jalali-nowruz-1" })
        #expect(updatedMatches.contains { $0.id == "custom-1" })
    }

    @Test("SettingsStore persists settings and round-trips export JSON")
    func settingsPersistenceAndExport() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("owghat-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "com.example.owghat.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(
            appGroupIdentifier: suiteName,
            customDirectoryURL: tempDir,
            userDefaults: defaults
        )

        var settings = AppSettings.default
        settings.language = .english
        settings.usePersianDigits = false
        settings.hijriDayOffset = -1
        settings.prayerOffsets[.maghrib] = 3
        settings.manualOverrides["2025-03-21"] = [.fajr: LocalTimeOfDay(hour: 4, minute: 40)]

        try store.saveSettings(settings)
        let loaded = store.loadSettings()
        #expect(loaded == settings)

        let exportedData = try store.exportJSON(for: settings)
        let imported = try store.importJSON(from: exportedData)
        #expect(imported == settings)
    }
}
