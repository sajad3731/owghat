import AVFoundation
import Foundation
import OwghatCore

/// Errors thrown during Adhan audio validation or import.
public enum AudioImportError: Error, LocalizedError {
    case unreadableSource
    case unsupportedAudioFormat
    case invalidAudioDuration

    public var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return LocalizedStrings.systemString("error.audio.unreadable")
        case .unsupportedAudioFormat:
            return LocalizedStrings.systemString("error.audio.unsupported_format")
        case .invalidAudioDuration:
            return LocalizedStrings.systemString("error.audio.invalid_duration")
        }
    }

    func localizedDescription(for language: AppLanguage) -> String {
        switch self {
        case .unreadableSource:
            return LocalizedStrings.string("error.audio.unreadable", language: language)
        case .unsupportedAudioFormat:
            return LocalizedStrings.string("error.audio.unsupported_format", language: language)
        case .invalidAudioDuration:
            return LocalizedStrings.string("error.audio.invalid_duration", language: language)
        }
    }
}

/// Manages Adhan and post-Adhan Doa playback with fade-in, fallback, and validated audio import.
@MainActor
final class AdhanAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private static let maxImportDurationSeconds: TimeInterval = 15 * 60

    private var player: AVAudioPlayer?
    private var pendingDoaURL: URL?
    private var currentVolume: Float = 0.85
    private var currentFadeIn: TimeInterval = 3.0
    private(set) var currentPrayer: Prayer?

    var onPlaybackStateChanged: ((Bool, Prayer?) -> Void)?
    var onPlaybackWarning: ((String) -> Void)?

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    func setLiveVolume(_ volume: Double) {
        let clamped = Float(max(0, min(1, volume)))
        currentVolume = clamped
        player?.volume = clamped
    }

    func play(
        prayer: Prayer?,
        choice: PrayerAudioChoice,
        postAdhanDoa: PrayerAudioChoice,
        settings: AdhanSettings,
        language: AppLanguage
    ) {
        stop()

        guard choice != .none else { return }

        currentVolume = Float(max(0, min(1, settings.volume)))
        currentFadeIn = max(0, settings.fadeInSeconds)
        currentPrayer = prayer
        pendingDoaURL = resolveURL(for: postAdhanDoa, importedClips: settings.importedClips)

        if let resolvedURL = resolveURL(for: choice, importedClips: settings.importedClips) {
            if startPlayback(url: resolvedURL, volume: currentVolume, fadeInSeconds: currentFadeIn) {
                return
            }
        }

        // Fall back to the bundled tone if an imported clip is missing or unreadable.
        if case .imported = choice {
            let prayerTitle = prayer?.localizedName(for: language) ?? ""
            let warning = LocalizedStrings.format("adhan.clips.missing_fallback", language: language, prayerTitle)
            onPlaybackWarning?(warning)

            if let fallbackURL = resolveBundledURL(),
               startPlayback(url: fallbackURL, volume: currentVolume, fadeInSeconds: currentFadeIn) {
                return
            }
        }

        pendingDoaURL = nil
        currentPrayer = nil
        onPlaybackStateChanged?(false, nil)
    }

    func stop() {
        pendingDoaURL = nil
        currentPrayer = nil
        player?.stop()
        player = nil
        onPlaybackStateChanged?(false, nil)
    }

    /// Copies, validates (`0 < duration <= 15 min`), and returns metadata for an imported audio file.
    func importAudio(from sourceURL: URL) throws -> ImportedAudioClip {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let supported = ["mp3", "m4a", "wav", "aiff", "caf", "aac", "mp4"]
        guard supported.contains(ext.lowercased()) else {
            throw AudioImportError.unsupportedAudioFormat
        }

        let directory = audioLibraryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let destinationURL = directory.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AudioImportError.unreadableSource
        }

        do {
            let probe = try AVAudioPlayer(contentsOf: destinationURL)
            let duration = probe.duration
            guard duration.isFinite, duration > 0, duration <= Self.maxImportDurationSeconds else {
                try? FileManager.default.removeItem(at: destinationURL)
                throw AudioImportError.invalidAudioDuration
            }
        } catch let importError as AudioImportError {
            try? FileManager.default.removeItem(at: destinationURL)
            throw importError
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw AudioImportError.unreadableSource
        }

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        return ImportedAudioClip(id: id, displayName: displayName, storedFileName: fileName)
    }

    func removeImportedAudio(_ clip: ImportedAudioClip) {
        let url = audioLibraryDirectory().appendingPathComponent(clip.storedFileName)
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    private func startPlayback(url: URL, volume: Float, fadeInSeconds: TimeInterval) -> Bool {
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.volume = fadeInSeconds > 0 ? 0.0 : volume
            newPlayer.prepareToPlay()
            guard newPlayer.play() else {
                return false
            }
            if fadeInSeconds > 0 {
                newPlayer.setVolume(volume, fadeDuration: fadeInSeconds)
            }
            player = newPlayer
            onPlaybackStateChanged?(true, currentPrayer)
            return true
        } catch {
            return false
        }
    }

    private func resolveURL(for choice: PrayerAudioChoice, importedClips: [ImportedAudioClip]) -> URL? {
        switch choice {
        case .none:
            return nil
        case .bundledPlaceholder:
            return resolveBundledURL()
        case .imported(let id):
            guard let clip = importedClips.first(where: { $0.id == id }) else { return nil }
            let url = audioLibraryDirectory().appendingPathComponent(clip.storedFileName)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private func resolveBundledURL() -> URL? {
        Bundle.main.url(forResource: "gentle-chime", withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: "gentle-chime", withExtension: "wav")
    }

    private func audioLibraryDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(AppConfig.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if flag, let nextDoa = self.pendingDoaURL {
                self.pendingDoaURL = nil
                if self.startPlayback(url: nextDoa, volume: self.currentVolume, fadeInSeconds: 1.0) {
                    return
                }
            }
            self.pendingDoaURL = nil
            self.currentPrayer = nil
            self.player = nil
            self.onPlaybackStateChanged?(false, nil)
        }
    }
}
