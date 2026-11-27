import AppKit
import OwghatCore
import SwiftUI

@main
struct OwghatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(appState: appState, showsOpenWindowButton: true)
                .environment(\.layoutDirection, appState.settings.language.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, Locale(identifier: appState.settings.language.rawValue))
                .preferredColorScheme(preferredColorScheme)
                .tint(appState.accentColor)
        } label: {
            MenuBarLabelView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .environment(\.layoutDirection, appState.settings.language.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, Locale(identifier: appState.settings.language.rawValue))
                .preferredColorScheme(preferredColorScheme)
        }

        Window(appTitle, id: "main") {
            MainOverviewView(appState: appState)
                .environment(\.layoutDirection, appState.settings.language.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, Locale(identifier: appState.settings.language.rawValue))
                .preferredColorScheme(preferredColorScheme)
                .tint(appState.accentColor)
        }
        .defaultSize(width: 400, height: 560)
    }

    private var appTitle: String {
        appState.settings.language == .persian ? AppConfig.persianAppName : AppConfig.appName
    }

    private var preferredColorScheme: ColorScheme? {
        switch appState.settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore()
        let settings = store.loadSettings()
        NSApp.setActivationPolicy(settings.adhan.showDockIcon ? .regular : .accessory)
    }
}

/// Optional main overview window presenting the daily schedule and quick settings access.
struct MainOverviewView: View {
    let appState: AppState

    var body: some View {
        MenuBarPanelView(appState: appState, showsOpenWindowButton: false)
            .frame(minWidth: 360, minHeight: 500)
            .padding()
    }
}
