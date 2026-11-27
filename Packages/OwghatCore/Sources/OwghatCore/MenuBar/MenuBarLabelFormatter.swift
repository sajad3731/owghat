import Foundation

/// Pure value output describing what the menu bar status item displays.
public struct MenuBarLabelContent: Sendable, Equatable {
    public let symbolName: String
    public let text: String?

    public init(symbolName: String, text: String?) {
        self.symbolName = symbolName
        self.text = text
    }
}

/// Formats the macOS menu bar status item icon and label text without jitter or `-00:00` artifacts.
public struct MenuBarLabelFormatter: Sendable {
    public static let boundaryBannerDuration: TimeInterval = 60

    public init() {}

    /// Builds menu bar symbol and text for `now`.
    /// - Parameters:
    ///   - nextEntry: The upcoming (or active boundary) prayer entry.
    ///   - justReachedEntry: Optional recently passed prayer entry within the 60s boundary window.
    ///   - now: Current timestamp.
    ///   - style: User-configured menu bar label style.
    ///   - language: Active UI language.
    ///   - usePersianDigits: Whether numbers use Persian numerals (`۰–۹`).
    ///   - timeZone: Active location time zone.
    ///   - isMutedToday: Whether Adhan audio is muted for today.
    ///   - isPlayingAdhan: Whether Adhan audio is currently playing.
    public func format(
        nextEntry: PrayerTimeEntry?,
        justReachedEntry: PrayerTimeEntry? = nil,
        now: Date,
        style: MenuBarLabelStyle,
        language: AppLanguage,
        usePersianDigits: Bool,
        timeZone: TimeZone,
        isMutedToday: Bool,
        isPlayingAdhan: Bool
    ) -> MenuBarLabelContent {
        let symbolName: String
        if isPlayingAdhan {
            symbolName = "speaker.wave.2.fill"
        } else if isMutedToday {
            symbolName = "bell.slash"
        } else {
            symbolName = "moon.stars"
        }

        if style == .iconOnly {
            return MenuBarLabelContent(symbolName: symbolName, text: nil)
        }

        // If a prayer boundary was reached within the last 60s, show its name instead of a negative countdown.
        if let reached = justReachedEntry, isWithinBoundaryWindow(entry: reached, now: now) {
            let prayerName = reached.prayer.localizedName(for: language)
            switch style {
            case .iconOnly:
                return MenuBarLabelContent(symbolName: symbolName, text: nil)
            case .countdown, .nextPrayerAndCountdown:
                return MenuBarLabelContent(symbolName: symbolName, text: prayerName)
            case .nextPrayerAndTime:
                let clock = DigitFormatter.formatTime(reached.date, timeZone: timeZone, persianDigits: usePersianDigits)
                return MenuBarLabelContent(symbolName: symbolName, text: "\(prayerName) \(clock)")
            }
        }

        guard let nextEntry else {
            return MenuBarLabelContent(symbolName: symbolName, text: nil)
        }

        let prayerName = nextEntry.prayer.localizedName(for: language)
        let remaining = nextEntry.date.timeIntervalSince(now)

        if remaining <= 0 {
            switch style {
            case .iconOnly:
                return MenuBarLabelContent(symbolName: symbolName, text: nil)
            case .countdown, .nextPrayerAndCountdown:
                return MenuBarLabelContent(symbolName: symbolName, text: prayerName)
            case .nextPrayerAndTime:
                let clock = DigitFormatter.formatTime(nextEntry.date, timeZone: timeZone, persianDigits: usePersianDigits)
                return MenuBarLabelContent(symbolName: symbolName, text: "\(prayerName) \(clock)")
            }
        }

        switch style {
        case .iconOnly:
            return MenuBarLabelContent(symbolName: symbolName, text: nil)

        case .nextPrayerAndTime:
            let clock = DigitFormatter.formatTime(nextEntry.date, timeZone: timeZone, persianDigits: usePersianDigits)
            return MenuBarLabelContent(symbolName: symbolName, text: "\(prayerName) \(clock)")

        case .countdown:
            let countdown = formatRoundedUpCountdown(remaining: remaining, persianDigits: usePersianDigits)
            return MenuBarLabelContent(symbolName: symbolName, text: countdown)

        case .nextPrayerAndCountdown:
            let countdown = formatRoundedUpCountdown(remaining: remaining, persianDigits: usePersianDigits)
            return MenuBarLabelContent(symbolName: symbolName, text: "\(prayerName) \(countdown)")
        }
    }

    private func isWithinBoundaryWindow(entry: PrayerTimeEntry, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(entry.date)
        return elapsed >= 0 && elapsed < Self.boundaryBannerDuration
    }

    private func formatRoundedUpCountdown(remaining: TimeInterval, persianDigits: Bool) -> String {
        let totalMinutes = max(1, Int(ceil(remaining / 60.0)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let raw = String(format: "−%02d:%02d", hours, minutes)
        return DigitFormatter.format(raw, persianDigits: persianDigits)
    }
}
