import OwghatCore
import SwiftUI

/// Multi-tab macOS Settings window for editing calculation, location, Adhan, appearance, and events.
struct SettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedSettingsTab) {
            GeneralSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.general"), systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            PrayerCalculationSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.calculation"), systemImage: "location")
                }
                .tag(SettingsTab.calculation)

            AdhanSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.adhan"), systemImage: "speaker.wave.2")
                }
                .tag(SettingsTab.adhan)

            AppearanceSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.appearance"), systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            EventsSettingsView(appState: appState)
                .tabItem {
                    Label(LocalizedStringKey("settings.tab.events"), systemImage: "calendar")
                }
                .tag(SettingsTab.events)
        }
        .tint(appState.accentColor)
        .frame(width: 560, height: 420)
        .padding()
    }
}
