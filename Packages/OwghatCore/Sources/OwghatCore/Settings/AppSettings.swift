import Foundation

/// Appearance theme preference.
public enum ThemeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }
}

/// Display options for the menu bar status item label.
public enum MenuBarLabelStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case iconOnly
    case nextPrayerAndTime
    case countdown
    case nextPrayerAndCountdown

    public var id: String { rawValue }
}

/// Metadata for a user-imported Adhan or Doa audio file stored in Application Support.
public struct ImportedAudioClip: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public var displayName: String
    public var storedFileName: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        storedFileName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.storedFileName = storedFileName
        self.createdAt = createdAt
    }
}

/// Choice of audio for a prayer notification.
public enum PrayerAudioChoice: Codable, Sendable, Equatable, Hashable {
    case none
    case bundledPlaceholder
    case imported(UUID)
}

/// Audio playback, notification, and background behavior settings.
public struct AdhanSettings: Codable, Sendable, Equatable {
    /// Mutes Adhan playback until the end of this local date (`YYYY-MM-DD`).
    public var mutedDateKey: String?
    public var audioPerPrayer: [Prayer: PrayerAudioChoice]
    public var volume: Double
    public var fadeInSeconds: Double
    public var preAdhanReminderMinutes: Int?
    public var postAdhanDoaClip: PrayerAudioChoice
    public var notificationsEnabled: Bool
    /// When true, muted days still deliver silent banner notifications; when false, muted days suppress notifications.
    public var silentNotificationsOnMutedDays: Bool
    public var launchAtLogin: Bool
    public var showDockIcon: Bool
    public var importedClips: [ImportedAudioClip]

    public init(
        mutedDateKey: String? = nil,
        audioPerPrayer: [Prayer: PrayerAudioChoice] = [
            .fajr: .bundledPlaceholder,
            .dhuhr: .bundledPlaceholder,
            .maghrib: .bundledPlaceholder
        ],
        volume: Double = 0.85,
        fadeInSeconds: Double = 3.0,
        preAdhanReminderMinutes: Int? = nil,
        postAdhanDoaClip: PrayerAudioChoice = .none,
        notificationsEnabled: Bool = true,
        silentNotificationsOnMutedDays: Bool = true,
        launchAtLogin: Bool = false,
        showDockIcon: Bool = false,
        importedClips: [ImportedAudioClip] = []
    ) {
        self.mutedDateKey = mutedDateKey
        self.audioPerPrayer = audioPerPrayer
        self.volume = max(0, min(1, volume))
        self.fadeInSeconds = max(0, fadeInSeconds)
        self.preAdhanReminderMinutes = preAdhanReminderMinutes
        self.postAdhanDoaClip = postAdhanDoaClip
        self.notificationsEnabled = notificationsEnabled
        self.silentNotificationsOnMutedDays = silentNotificationsOnMutedDays
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
        self.importedClips = importedClips
    }

    private enum CodingKeys: String, CodingKey {
        case mutedDateKey
        case audioPerPrayer
        case volume
        case fadeInSeconds
        case preAdhanReminderMinutes
        case postAdhanDoaClip
        case notificationsEnabled
        case silentNotificationsOnMutedDays
        case launchAtLogin
        case showDockIcon
        case importedClips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mutedDateKey = try container.decodeIfPresent(String.self, forKey: .mutedDateKey)
        audioPerPrayer = try container.decodeIfPresent([Prayer: PrayerAudioChoice].self, forKey: .audioPerPrayer) ?? [
            .fajr: .bundledPlaceholder,
            .dhuhr: .bundledPlaceholder,
            .maghrib: .bundledPlaceholder
        ]
        let rawVolume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 0.85
        volume = max(0, min(1, rawVolume))
        let rawFade = try container.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 3.0
        fadeInSeconds = max(0, rawFade)
        preAdhanReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .preAdhanReminderMinutes)
        postAdhanDoaClip = try container.decodeIfPresent(PrayerAudioChoice.self, forKey: .postAdhanDoaClip) ?? .none
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        silentNotificationsOnMutedDays = try container.decodeIfPresent(Bool.self, forKey: .silentNotificationsOnMutedDays) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        importedClips = try container.decodeIfPresent([ImportedAudioClip].self, forKey: .importedClips) ?? []
    }

    public func isMuted(on date: Date, timeZone: TimeZone) -> Bool {
        guard let mutedDateKey else { return false }
        return mutedDateKey == DateKeyFormatter.key(for: date, in: timeZone)
    }

    /// Removes an imported clip and reassigns any prayers referencing it back to the bundled tone.
    /// Returns the prayers whose audio choice was reassigned, in chronological prayer order.
    @discardableResult
    public mutating func removeImportedClip(id: UUID) -> [Prayer] {
        importedClips.removeAll { $0.id == id }
        var affected: [Prayer] = []
        for prayer in Prayer.allCases where audioPerPrayer[prayer] == .imported(id) {
            audioPerPrayer[prayer] = .bundledPlaceholder
            affected.append(prayer)
        }
        if postAdhanDoaClip == .imported(id) {
            postAdhanDoaClip = .none
        }
        return affected
    }
}

/// Complete user-editable configuration persisted across the app and widget extension.
public struct AppSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var locationMode: LocationSelectionMode
    public var selectedLocation: GeoLocation
    public var calculationMethod: CalculationMethod
    public var sourceMode: PrayerSourceMode
    public var visiblePrayers: Set<Prayer>
    public var widgetDefaultPrayers: Set<Prayer>
    public var prayerOffsets: [Prayer: Int]
    public var manualOverrides: [String: [Prayer: LocalTimeOfDay]]
    public var adhan: AdhanSettings
    public var menuBarLabelStyle: MenuBarLabelStyle
    public var language: AppLanguage
    public var usePersianDigits: Bool
    public var hijriVariant: HijriCalendarVariant
    public var hijriDayOffset: Int
    public var themeMode: ThemeMode
    public var accentColorHex: String
    public var editedBundledOccasions: [Occasion]
    public var customOccasions: [Occasion]

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        locationMode: LocationSelectionMode = .cityPreset,
        selectedLocation: GeoLocation = .tehran,
        calculationMethod: CalculationMethod = .tehran,
        sourceMode: PrayerSourceMode = .offlineOnly,
        visiblePrayers: Set<Prayer> = Prayer.defaultVisible,
        widgetDefaultPrayers: Set<Prayer> = Prayer.defaultVisible,
        prayerOffsets: [Prayer: Int] = [:],
        manualOverrides: [String: [Prayer: LocalTimeOfDay]] = [:],
        adhan: AdhanSettings = AdhanSettings(),
        menuBarLabelStyle: MenuBarLabelStyle = .nextPrayerAndCountdown,
        language: AppLanguage = .persian,
        usePersianDigits: Bool = true,
        hijriVariant: HijriCalendarVariant = .ummAlQura,
        hijriDayOffset: Int = 0,
        themeMode: ThemeMode = .system,
        accentColorHex: String = "#0E7490",
        editedBundledOccasions: [Occasion] = [],
        customOccasions: [Occasion] = []
    ) {
        self.schemaVersion = schemaVersion
        self.locationMode = locationMode
        self.selectedLocation = selectedLocation
        self.calculationMethod = calculationMethod
        self.sourceMode = sourceMode
        self.visiblePrayers = visiblePrayers
        self.widgetDefaultPrayers = widgetDefaultPrayers
        self.prayerOffsets = prayerOffsets
        self.manualOverrides = manualOverrides
        self.adhan = adhan
        self.menuBarLabelStyle = menuBarLabelStyle
        self.language = language
        self.usePersianDigits = usePersianDigits
        self.hijriVariant = hijriVariant
        self.hijriDayOffset = hijriDayOffset
        self.themeMode = themeMode
        self.accentColorHex = accentColorHex
        self.editedBundledOccasions = editedBundledOccasions
        self.customOccasions = customOccasions
    }

    public static let `default` = AppSettings()
}
