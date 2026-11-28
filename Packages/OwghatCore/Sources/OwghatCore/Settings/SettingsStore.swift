import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Portable JSON envelope used for importing and exporting all settings and occasions.
public struct OwghatExportEnvelope: Codable, Sendable, Equatable {
    public let exportedAt: Date
    public let appName: String
    public let settings: AppSettings

    public init(exportedAt: Date = Date(), appName: String = AppConfig.appName, settings: AppSettings) {
        self.exportedAt = exportedAt
        self.appName = appName
        self.settings = settings
    }
}

/// Persists `AppSettings` and `WidgetSnapshot` via the shared App Group (`UserDefaults` and JSON file).
public final class SettingsStore: @unchecked Sendable {
    private static let settingsKey = "owghat.settings.v1"
    private static let snapshotKey = "owghat.widgetSnapshot.v1"
    private static let loggedGroupTracker = LoggedGroupTracker()
    #if canImport(OSLog)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? AppConfig.appBundleIdentifier,
        category: "SettingsStore"
    )
    #endif

    public let isUsingSharedContainer: Bool

    private let userDefaults: UserDefaults?
    private let settingsFileURL: URL?
    private let snapshotFileURL: URL?
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        appGroupIdentifier: String = AppConfig.appGroupIdentifier,
        customDirectoryURL: URL? = nil,
        userDefaults: UserDefaults? = nil
    ) {
        self.userDefaults = userDefaults ?? UserDefaults(suiteName: appGroupIdentifier)

        let baseDirectory: URL?
        if let customDirectoryURL {
            self.isUsingSharedContainer = false
            baseDirectory = customDirectoryURL
        } else if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            self.isUsingSharedContainer = true
            baseDirectory = groupURL.appendingPathComponent(AppConfig.appSupportDirectoryName, isDirectory: true)
        } else {
            self.isUsingSharedContainer = false
            Self.logUnavailableContainerOnce(appGroupIdentifier: appGroupIdentifier)
            baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent(AppConfig.appSupportDirectoryName, isDirectory: true)
        }

        self.settingsFileURL = baseDirectory?.appendingPathComponent("settings.json")
        self.snapshotFileURL = baseDirectory?.appendingPathComponent("widget-snapshot.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadSettings() -> AppSettings {
        lock.lock()
        defer { lock.unlock() }

        if let fileURL = settingsFileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            return decoded
        }

        if let data = userDefaults?.data(forKey: Self.settingsKey),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            return decoded
        }

        return .default
    }

    public func saveSettings(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try encoder.encode(settings)
        if let fileURL = settingsFileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
        userDefaults?.set(data, forKey: Self.settingsKey)
    }

    public func loadWidgetSnapshot() -> WidgetSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        if let fileURL = snapshotFileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(WidgetSnapshot.self, from: data) {
            return decoded
        }

        if let data = userDefaults?.data(forKey: Self.snapshotKey),
           let decoded = try? decoder.decode(WidgetSnapshot.self, from: data) {
            return decoded
        }

        return nil
    }

    public func saveWidgetSnapshot(_ snapshot: WidgetSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }

        let data = try encoder.encode(snapshot)
        if let fileURL = snapshotFileURL {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
        userDefaults?.set(data, forKey: Self.snapshotKey)
    }

    public func exportJSON(for settings: AppSettings) throws -> Data {
        let envelope = OwghatExportEnvelope(settings: settings)
        return try encoder.encode(envelope)
    }

    public func importJSON(from data: Data) throws -> AppSettings {
        if let envelope = try? decoder.decode(OwghatExportEnvelope.self, from: data) {
            return envelope.settings
        }
        return try decoder.decode(AppSettings.self, from: data)
    }

    private static func logUnavailableContainerOnce(appGroupIdentifier: String) {
        guard loggedGroupTracker.markLoggedIfNeeded(appGroupIdentifier) else { return }

        #if canImport(OSLog)
        logger.warning(
            "Shared App Group container '\(appGroupIdentifier, privacy: .public)' is unavailable; falling back to local Application Support."
        )
        #endif
    }

    private final class LoggedGroupTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var identifiers: Set<String> = []

        func markLoggedIfNeeded(_ identifier: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return identifiers.insert(identifier).inserted
        }
    }
}
