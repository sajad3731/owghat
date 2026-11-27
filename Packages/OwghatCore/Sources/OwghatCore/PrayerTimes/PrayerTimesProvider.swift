import Foundation

/// Strategy for selecting offline vs online prayer times.
public enum PrayerSourceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case offlineOnly
    case onlineOnly
    case offlineWithOnlineComparison

    public var id: String { rawValue }
}

/// Abstract provider capable of producing daily prayer schedules.
public protocol PrayerTimesProvider: Sendable {
    func prayerTimes(
        for date: DateComponents,
        location: GeoLocation,
        timeZone: TimeZone,
        settings: AppSettings
    ) async throws -> DailyPrayerTimes
}

/// Default offline provider backed by `AstronomicalPrayerCalculator`.
public struct OfflinePrayerTimesProvider: PrayerTimesProvider, Sendable {
    private let calculator: AstronomicalPrayerCalculator

    public init(calculator: AstronomicalPrayerCalculator = AstronomicalPrayerCalculator()) {
        self.calculator = calculator
    }

    public func prayerTimes(
        for date: DateComponents,
        location: GeoLocation,
        timeZone: TimeZone,
        settings: AppSettings
    ) async throws -> DailyPrayerTimes {
        try calculator.calculate(
            for: date,
            location: location,
            timeZone: timeZone,
            method: settings.calculationMethod,
            offsets: settings.prayerOffsets,
            manualOverrides: settings.manualOverrides
        )
    }
}

/// Errors raised by the optional Aladhan online provider.
public enum AladhanProviderError: Error, Sendable {
    case invalidDate
    case invalidURL
    case invalidResponse
    case missingTimingField(String)
}

/// Thread-safe daily cache for online API responses.
public actor PrayerTimesDiskCache {
    private var memoryCache: [String: DailyPrayerTimes] = [:]
    private let cacheDirectory: URL?

    public init(cacheDirectory: URL? = nil) {
        self.cacheDirectory = cacheDirectory
    }

    public func cachedTimes(for key: String) -> DailyPrayerTimes? {
        if let hit = memoryCache[key] {
            return hit
        }
        guard let fileURL = fileURL(for: key),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(DailyPrayerTimes.self, from: data) else {
            return nil
        }
        memoryCache[key] = decoded
        return decoded
    }

    public func store(_ times: DailyPrayerTimes, for key: String) {
        memoryCache[key] = times
        guard let fileURL = fileURL(for: key) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(times) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func fileURL(for key: String) -> URL? {
        let sanitized = key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory?.appendingPathComponent("\(sanitized).json")
    }
}

/// Optional Aladhan API provider (`method=7` Tehran by default), cached per day/location.
public struct AladhanPrayerTimesProvider: PrayerTimesProvider, Sendable {
    private let session: URLSession
    private let cache: PrayerTimesDiskCache
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        cache: PrayerTimesDiskCache = PrayerTimesDiskCache(),
        baseURL: URL = AppConfig.aladhanBaseURL
    ) {
        self.session = session
        self.cache = cache
        self.baseURL = baseURL
    }

    public func prayerTimes(
        for date: DateComponents,
        location: GeoLocation,
        timeZone: TimeZone,
        settings: AppSettings
    ) async throws -> DailyPrayerTimes {
        guard let year = date.year, let month = date.month, let day = date.day else {
            throw AladhanProviderError.invalidDate
        }

        let dateKey = DateKeyFormatter.key(for: date)
        let cacheKey = "\(dateKey)_\(String(format: "%.4f_%.4f", location.latitude, location.longitude))_\(settings.calculationMethod.id)_\(timeZone.identifier)"

        if let cached = await cache.cachedTimes(for: cacheKey) {
            return applyUserAdjustments(to: cached, date: date, timeZone: timeZone, settings: settings)
        }

        let formattedDate = String(format: "%02d-%02d-%04d", day, month, year)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("timings/\(formattedDate)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "method", value: String(settings.calculationMethod.aladhanMethodID)),
            URLQueryItem(name: "timezonestring", value: timeZone.identifier)
        ]

        guard let url = components?.url else {
            throw AladhanProviderError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AladhanProviderError.invalidResponse
        }

        let payload = try JSONDecoder().decode(AladhanResponse.self, from: data)
        let rawEntries = try parseEntries(
            timings: payload.data.timings,
            date: date,
            timeZone: timeZone
        )

        let rawSchedule = DailyPrayerTimes(
            dateKey: dateKey,
            timeZoneIdentifier: timeZone.identifier,
            location: location,
            method: settings.calculationMethod,
            entries: rawEntries,
            source: .online
        )
        await cache.store(rawSchedule, for: cacheKey)
        return applyUserAdjustments(to: rawSchedule, date: date, timeZone: timeZone, settings: settings)
    }

    private func parseEntries(
        timings: [String: String],
        date: DateComponents,
        timeZone: TimeZone
    ) throws -> [Prayer: PrayerTimeEntry] {
        let mapping: [(Prayer, String)] = [
            (.imsak, "Imsak"),
            (.fajr, "Fajr"),
            (.sunrise, "Sunrise"),
            (.dhuhr, "Dhuhr"),
            (.sunset, "Sunset"),
            (.maghrib, "Maghrib"),
            (.isha, "Isha"),
            (.midnight, "Midnight")
        ]

        var result: [Prayer: PrayerTimeEntry] = [:]
        for (prayer, key) in mapping {
            guard let raw = timings[key],
                  let timeOfDay = parseClockString(raw),
                  let resolved = timeOfDay.date(on: date, in: timeZone) else {
                throw AladhanProviderError.missingTimingField(key)
            }
            result[prayer] = PrayerTimeEntry(prayer: prayer, date: resolved)
        }
        return result
    }

    private func parseClockString(_ raw: String) -> LocalTimeOfDay? {
        let cleaned = raw.split(separator: " ").first.map(String.init) ?? raw
        let parts = cleaned.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return LocalTimeOfDay(hour: hour, minute: minute)
    }

    private func applyUserAdjustments(
        to base: DailyPrayerTimes,
        date: DateComponents,
        timeZone: TimeZone,
        settings: AppSettings
    ) -> DailyPrayerTimes {
        let dayOverrides = settings.manualOverrides[base.dateKey] ?? [:]
        var adjustedEntries: [Prayer: PrayerTimeEntry] = [:]

        for (prayer, entry) in base.entries {
            if let overrideTime = dayOverrides[prayer],
               let overrideDate = overrideTime.date(on: date, in: timeZone) {
                adjustedEntries[prayer] = PrayerTimeEntry(
                    prayer: prayer,
                    date: overrideDate,
                    isOverridden: true,
                    appliedOffsetMinutes: 0
                )
            } else {
                let offset = settings.prayerOffsets[prayer] ?? 0
                adjustedEntries[prayer] = PrayerTimeEntry(
                    prayer: prayer,
                    date: entry.date.addingTimeInterval(TimeInterval(offset * 60)),
                    isOverridden: false,
                    appliedOffsetMinutes: offset
                )
            }
        }

        return DailyPrayerTimes(
            dateKey: base.dateKey,
            timeZoneIdentifier: base.timeZoneIdentifier,
            location: base.location,
            method: base.method,
            entries: adjustedEntries,
            source: base.source,
            comparison: base.comparison
        )
    }
}

private struct AladhanResponse: Decodable {
    let data: AladhanData
}

private struct AladhanData: Decodable {
    let timings: [String: String]
}

/// Coordinates offline and online providers according to `AppSettings.sourceMode`.
public struct HybridPrayerTimesProvider: PrayerTimesProvider, Sendable {
    private let offline: OfflinePrayerTimesProvider
    private let online: AladhanPrayerTimesProvider

    public init(
        offline: OfflinePrayerTimesProvider = OfflinePrayerTimesProvider(),
        online: AladhanPrayerTimesProvider = AladhanPrayerTimesProvider()
    ) {
        self.offline = offline
        self.online = online
    }

    public func prayerTimes(
        for date: DateComponents,
        location: GeoLocation,
        timeZone: TimeZone,
        settings: AppSettings
    ) async throws -> DailyPrayerTimes {
        switch settings.sourceMode {
        case .offlineOnly:
            return try await offline.prayerTimes(for: date, location: location, timeZone: timeZone, settings: settings)

        case .onlineOnly:
            do {
                return try await online.prayerTimes(for: date, location: location, timeZone: timeZone, settings: settings)
            } catch {
                // Fall back to offline calculation so the app remains reliable offline.
                return try await offline.prayerTimes(for: date, location: location, timeZone: timeZone, settings: settings)
            }

        case .offlineWithOnlineComparison:
            let base = try await offline.prayerTimes(for: date, location: location, timeZone: timeZone, settings: settings)
            guard let remote = try? await online.prayerTimes(for: date, location: location, timeZone: timeZone, settings: settings) else {
                return base
            }
            var diffs: [Prayer: Int] = [:]
            for prayer in Prayer.allCases {
                if let offDate = base.time(for: prayer), let onDate = remote.time(for: prayer) {
                    diffs[prayer] = Int((onDate.timeIntervalSince(offDate) / 60.0).rounded())
                }
            }
            return DailyPrayerTimes(
                dateKey: base.dateKey,
                timeZoneIdentifier: base.timeZoneIdentifier,
                location: base.location,
                method: base.method,
                entries: base.entries,
                source: .hybrid,
                comparison: PrayerTimeComparison(minuteDifferences: diffs)
            )
        }
    }
}
