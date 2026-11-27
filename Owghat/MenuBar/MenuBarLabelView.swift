import OwghatCore
import SwiftUI

/// Renders the menu bar status item text and icon according to `MenuBarLabelStyle`.
struct MenuBarLabelView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.isMutedToday ? "bell.slash" : "moon.stars")
            if let text = labelText {
                Text(text)
                    .monospacedDigit()
            }
        }
    }

    private var labelText: String? {
        guard let next = appState.nextPrayer else { return nil }
        let lang = appState.settings.language
        let persianDigits = appState.settings.usePersianDigits
        let prayerName = next.entry.prayer.localizedName(for: lang)
        let timeString = DigitFormatter.formatTime(
            next.entry.date,
            timeZone: appState.activeTimeZone,
            persianDigits: persianDigits
        )
        let countdown = next.formattedCountdown(persianDigits: persianDigits)

        switch appState.settings.menuBarLabelStyle {
        case .iconOnly:
            return nil
        case .nextPrayerAndTime:
            return "\(prayerName) \(timeString)"
        case .countdown:
            return countdown
        case .nextPrayerAndCountdown:
            return "\(prayerName) \(countdown)"
        }
    }
}
