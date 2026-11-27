import OwghatCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

/// Adhan audio routing, volume/fade-in, reminders, Doa, notifications, imported clips, and launch-at-login controls.
struct AdhanSettingsView: View {
    let appState: AppState
    @State private var isImportingAudio = false
    @State private var draftVolume: Double = 0.85
    @State private var isDraggingVolume = false

    private let reminderOptions: [Int] = [5, 10, 15, 30]
    private var adhanPrayers: [Prayer] {
        Prayer.allCases.filter(\.isAdhanPrayer)
    }

    var body: some View {
        Form {
            prayerAudioSection
            playbackAndAlertsSection
            importedClipsSection
            systemSection
        }
        .formStyle(.grouped)
        .onAppear {
            draftVolume = appState.settings.adhan.volume
            Task {
                await appState.syncSystemStatuses()
            }
        }
        .onChange(of: appState.settings.adhan.volume) { _, newValue in
            if !isDraggingVolume {
                draftVolume = newValue
            }
        }
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio]
        ) { result in
            if case .success(let url) = result {
                appState.importAudioFile(from: url)
            }
        }
    }

    // MARK: - Sections

    private var prayerAudioSection: some View {
        Section(LocalizedStringKey("adhan.prayer_audio.section")) {
            ForEach(adhanPrayers) { prayer in
                HStack(spacing: 8) {
                    Picker(prayer.localizedName(for: appState.settings.language), selection: audioBinding(for: prayer)) {
                        audioChoiceMenuItems
                    }

                    let isPreviewingThis = appState.isPlayingAdhan && appState.currentPlayingPrayer == prayer
                    Button {
                        appState.previewAdhan(for: prayer)
                    } label: {
                        Image(systemName: isPreviewingThis ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(LocalizedStringKey(isPreviewingThis ? "adhan.clips.stop_preview" : "adhan.clips.preview"))
                    .accessibilityLabel(LocalizedStringKey(isPreviewingThis ? "adhan.clips.stop_preview" : "adhan.clips.preview"))
                }
            }
        }
    }

    private var playbackAndAlertsSection: some View {
        Section(LocalizedStringKey("adhan.playback.section")) {
            Slider(
                value: Binding(
                    get: { draftVolume },
                    set: { newValue in
                        draftVolume = newValue
                        appState.setLiveVolume(newValue)
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isDraggingVolume = editing
                    if !editing {
                        appState.commitVolume(draftVolume)
                    }
                }
            ) {
                Text(LocalizedStringKey("adhan.volume"))
            }

            Stepper(
                value: Binding(
                    get: { Int(appState.settings.adhan.fadeInSeconds.rounded()) },
                    set: { seconds in appState.updateSettings { $0.adhan.fadeInSeconds = Double(seconds) } }
                ),
                in: 0...10
            ) {
                let secondsText = DigitFormatter.format(
                    String(Int(appState.settings.adhan.fadeInSeconds.rounded())),
                    persianDigits: appState.settings.usePersianDigits
                )
                HStack {
                    Text(LocalizedStringKey("adhan.fade_in"))
                    Spacer()
                    Text(LocalizedStrings.format("adhan.fade_in.seconds", language: appState.settings.language, secondsText))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Picker(
                LocalizedStringKey("adhan.reminder.label"),
                selection: Binding(
                    get: { appState.settings.adhan.preAdhanReminderMinutes ?? 0 },
                    set: { minutes in
                        appState.updateSettings {
                            $0.adhan.preAdhanReminderMinutes = minutes > 0 ? minutes : nil
                        }
                    }
                )
            ) {
                Text(LocalizedStringKey("adhan.reminder.off")).tag(0)
                ForEach(reminderOptions, id: \.self) { minutes in
                    let formatted = DigitFormatter.format(
                        String(minutes),
                        persianDigits: appState.settings.usePersianDigits
                    )
                    Text(LocalizedStrings.format("adhan.reminder.minutes", language: appState.settings.language, formatted))
                        .tag(minutes)
                }
            }

            Picker(
                LocalizedStringKey("adhan.post_doa"),
                selection: Binding(
                    get: { appState.settings.adhan.postAdhanDoaClip },
                    set: { choice in appState.updateSettings { $0.adhan.postAdhanDoaClip = choice } }
                )
            ) {
                audioChoiceMenuItems
            }

            Toggle(
                LocalizedStringKey("adhan.notifications.enable"),
                isOn: Binding(
                    get: { appState.settings.adhan.notificationsEnabled },
                    set: { enabled in appState.updateSettings { $0.adhan.notificationsEnabled = enabled } }
                )
            )

            Toggle(
                LocalizedStringKey("adhan.notifications.silent_on_muted"),
                isOn: Binding(
                    get: { appState.settings.adhan.silentNotificationsOnMutedDays },
                    set: { enabled in appState.updateSettings { $0.adhan.silentNotificationsOnMutedDays = enabled } }
                )
            )
            .disabled(!appState.settings.adhan.notificationsEnabled)

            if appState.notificationAuthorizationStatus == .denied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(LocalizedStringKey("adhan.notifications.denied_warning"))
                        .font(.caption)
                    Spacer()
                    Button(LocalizedStringKey("adhan.notifications.open_settings")) {
                        appState.openNotificationSystemSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var importedClipsSection: some View {
        Section(LocalizedStringKey("adhan.clips.section")) {
            Button(LocalizedStringKey("adhan.clips.import")) {
                isImportingAudio = true
            }

            if appState.settings.adhan.importedClips.isEmpty {
                Text(LocalizedStringKey("adhan.clips.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.settings.adhan.importedClips) { clip in
                    ImportedClipRow(clip: clip) { newName in
                        appState.renameImportedClip(id: clip.id, newName: newName)
                    } onDelete: {
                        appState.deleteImportedClip(clip)
                    }
                }
            }

            if let notice = appState.statusMessage, !notice.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(appState.accentColor)
                    Text(notice)
                        .font(.caption)
                    Spacer()
                    Button {
                        appState.dismissStatusMessage()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(LocalizedStringKey("menubar.dismiss_warning"))
                }
            }
        }
    }

    private var systemSection: some View {
        Section(LocalizedStringKey("adhan.system.section")) {
            Toggle(
                LocalizedStringKey("adhan.system.launch_at_login"),
                isOn: Binding(
                    get: { appState.settings.adhan.launchAtLogin },
                    set: { enabled in appState.setLaunchAtLogin(enabled) }
                )
            )

            Text(LocalizedStringKey(launchStatusKey))
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.launchAtLoginStatus == .requiresApproval {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(LocalizedStringKey("adhan.system.requires_approval"))
                        .font(.caption)
                    Spacer()
                    Button(LocalizedStringKey("adhan.system.open_login_items")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .controlSize(.small)
                }
            }

            if let launchError = appState.launchAtLoginError, !launchError.isEmpty {
                Text(launchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle(
                LocalizedStringKey("adhan.system.show_dock_icon"),
                isOn: Binding(
                    get: { appState.settings.adhan.showDockIcon },
                    set: { enabled in appState.updateSettings { $0.adhan.showDockIcon = enabled } }
                )
            )
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var audioChoiceMenuItems: some View {
        Text(LocalizedStringKey("adhan.audio.none")).tag(PrayerAudioChoice.none)
        Text(LocalizedStringKey("adhan.audio.bundled")).tag(PrayerAudioChoice.bundledPlaceholder)
        ForEach(appState.settings.adhan.importedClips) { clip in
            Text(clip.displayName).tag(PrayerAudioChoice.imported(clip.id))
        }
    }

    private func audioBinding(for prayer: Prayer) -> Binding<PrayerAudioChoice> {
        Binding(
            get: { appState.settings.adhan.audioPerPrayer[prayer] ?? .none },
            set: { choice in appState.updateSettings { $0.adhan.audioPerPrayer[prayer] = choice } }
        )
    }

    private var launchStatusKey: String {
        switch appState.launchAtLoginStatus {
        case .enabled:
            return "adhan.system.status.enabled"
        case .requiresApproval:
            return "adhan.system.status.requires_approval"
        case .notFound:
            return "adhan.system.status.not_found"
        case .notRegistered:
            return "adhan.system.status.not_registered"
        @unknown default:
            return "adhan.system.status.not_registered"
        }
    }
}

private struct ImportedClipRow: View {
    let clip: ImportedAudioClip
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var editedName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                LocalizedStringKey("adhan.clips.rename"),
                text: $editedName,
                onCommit: { onRename(editedName) }
            )
            .textFieldStyle(.roundedBorder)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(LocalizedStringKey("adhan.clips.delete"))
            .accessibilityLabel(LocalizedStringKey("adhan.clips.delete"))
        }
        .onAppear {
            editedName = clip.displayName
        }
        .onChange(of: clip.displayName) { _, updated in
            editedName = updated
        }
    }
}
