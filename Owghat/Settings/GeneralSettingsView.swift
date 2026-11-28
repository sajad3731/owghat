import AppKit
import OwghatCore
import SwiftUI
import UniformTypeIdentifiers

/// Language, background behavior, and JSON import/export settings.
struct GeneralSettingsView: View {
    let appState: AppState
    @State private var isImportingBackup = false

    var body: some View {
        Form {
            Picker("Language", selection: Binding(
                get: { appState.settings.language },
                set: { lang in appState.updateSettings { $0.language = lang } }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { appState.settings.adhan.launchAtLogin },
                set: { enabled in appState.updateSettings { $0.adhan.launchAtLogin = enabled } }
            ))

            Toggle("Show Dock icon", isOn: Binding(
                get: { appState.settings.adhan.showDockIcon },
                set: { enabled in appState.updateSettings { $0.adhan.showDockIcon = enabled } }
            ))

            if !appState.isUsingSharedWidgetContainer {
                Label(
                    LocalizedStringKey("settings.general.shared_container_warning"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Backup") {
                HStack {
                    Button("Export JSON…") {
                        exportSettingsPanel()
                    }
                    Button("Import JSON…") {
                        isImportingBackup = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json]
        ) { result in
            if case .success(let url) = result,
               let data = try? Data(contentsOf: url) {
                try? appState.importSettingsData(from: data)
            }
        }
    }

    private func exportSettingsPanel() {
        guard let data = try? appState.exportSettingsData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "owghat-settings.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }
}
