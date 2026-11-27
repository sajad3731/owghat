import OwghatCore
import SwiftUI

/// Menu bar label, digits, theme, and Hijri calendar offset settings.
struct AppearanceSettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Picker("Menu bar label", selection: Binding(
                get: { appState.settings.menuBarLabelStyle },
                set: { style in appState.updateSettings { $0.menuBarLabelStyle = style } }
            )) {
                Text("Icon only").tag(MenuBarLabelStyle.iconOnly)
                Text("Next prayer + time").tag(MenuBarLabelStyle.nextPrayerAndTime)
                Text("Countdown").tag(MenuBarLabelStyle.countdown)
                Text("Next prayer + countdown").tag(MenuBarLabelStyle.nextPrayerAndCountdown)
            }

            Toggle("Use Persian digits", isOn: Binding(
                get: { appState.settings.usePersianDigits },
                set: { enabled in appState.updateSettings { $0.usePersianDigits = enabled } }
            ))

            Picker("Theme", selection: Binding(
                get: { appState.settings.themeMode },
                set: { mode in appState.updateSettings { $0.themeMode = mode } }
            )) {
                Text("System").tag(ThemeMode.system)
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
            }

            Stepper(
                value: Binding(
                    get: { appState.settings.hijriDayOffset },
                    set: { offset in appState.updateSettings { $0.hijriDayOffset = offset } }
                ),
                in: -3...3
            ) {
                Text("Hijri day offset: \(appState.settings.hijriDayOffset)")
            }
        }
        .formStyle(.grouped)
    }
}
