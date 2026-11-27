import OwghatCore
import SwiftUI
import UniformTypeIdentifiers

/// Adhan audio playback, volume, notifications, and custom audio import settings.
struct AdhanSettingsView: View {
    let appState: AppState
    @State private var isImportingAudio = false

    var body: some View {
        Form {
            Slider(value: Binding(
                get: { appState.settings.adhan.volume },
                set: { vol in appState.updateSettings { $0.adhan.volume = vol } }
            ), in: 0...1) {
                Text("Volume")
            }

            Toggle("Enable backup notifications", isOn: Binding(
                get: { appState.settings.adhan.notificationsEnabled },
                set: { enabled in appState.updateSettings { $0.adhan.notificationsEnabled = enabled } }
            ))

            Section("Audio Clips") {
                Button("Import Audio File…") {
                    isImportingAudio = true
                }
                Button("Test Placeholder Tone") {
                    appState.previewAdhan(for: .fajr)
                }
                if !appState.settings.adhan.importedClips.isEmpty {
                    ForEach(appState.settings.adhan.importedClips) { clip in
                        Text(clip.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio]
        ) { result in
            if case .success(let url) = result {
                appState.importAudioFile(from: url)
            }
        }
    }
}
