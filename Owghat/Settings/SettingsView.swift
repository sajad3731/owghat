import OwghatCore
import SwiftUI

/// Multi-tab macOS Settings window for editing calculation, location, Adhan, appearance, and events.
struct SettingsView: View {
    let appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.general"), systemImage: "gearshape")
                }

            PrayerCalculationSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.calculation"), systemImage: "location")
                }

            AdhanSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.adhan"), systemImage: "speaker.wave.2")
                }

            AppearanceSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.appearance"), systemImage: "paintbrush")
                }

            EventsSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.events"), systemImage: "calendar")
                }
        }
        .frame(width: 560, height: 420)
        .padding()
    }
}
