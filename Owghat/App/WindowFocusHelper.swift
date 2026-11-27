import AppKit
import OwghatCore
import SwiftUI

/// Activates the menu bar agent app and orders target windows to the front.
@MainActor
enum WindowFocusHelper {
    static func openMainWindow(using openWindow: OpenWindowAction) {
        NSApp.activate()
        openWindow(id: "main")
        Task { @MainActor in
            await Task.yield()
            NSApp.activate()
            for window in NSApp.windows {
                let id = window.identifier?.rawValue ?? ""
                if id == "main" || window.title == AppConfig.appName || window.title == AppConfig.persianAppName {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }

    static func openSettings(using openSettings: OpenSettingsAction) {
        NSApp.activate()
        openSettings()
        Task { @MainActor in
            await Task.yield()
            NSApp.activate()
            for window in NSApp.windows {
                let id = window.identifier?.rawValue ?? ""
                if id.localizedCaseInsensitiveContains("settings") {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}
