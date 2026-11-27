import AVFoundation
import Foundation
import OwghatCore

/// Errors thrown during Adhan audio resolution or import.
public enum AudioImportError: Error, LocalizedError {
    case unreadableSource
    case unsupportedAudioFormat

    public var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return "Unable to read the selected audio file."
        case .unsupportedAudioFormat:
            return "Unsupported audio format."
        }
    }
}

/// Manages Adhan and post-Adhan Doa playback with fade-in and custom audio import.
@MainActor
final class AdhanAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var pendingDoaURL: URL?
    private var currentVolume: Float = 0.85
    private var currentFadeIn: TimeInterval = 3.0
    var onPlaybackStateChanged: ((Bool) -> Void)?

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    func play(
        choice: PrayerAudioChoice,
        postAdhanDoa: PrayerAudioChoice,
        settings: AdhanSettings
    ) {
        guard let url = resolveURL(for: choice, importedClips: settings.importedClips) else {
            return
        }
        pendingDoaURL = resolveURL(for: postAdhanDoa, importedClips: settings.importedClips)
        currentVolume = Float(settings.volume)
        currentFadeIn = settings.fadeInSeconds
        startPlayback(url: url, volume: currentVolume, fadeInSeconds: currentFadeIn)
    }

    func stop() {
        pendingDoaURL = nil
        player?.stop()
        player = nil
        onPlaybackStateChanged?(false)
    }

    /// Copies a user-selected audio file into Application Support and returns its descriptor.
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

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        return ImportedAudioClip(id: id, displayName: displayName, storedFileName: fileName)
    }

    func removeImportedAudio(_ clip: ImportedAudioClip) {
        let url = audioLibraryDirectory().appendingPathComponent(clip.storedFileName)
        try? FileManager.default.removeItem(at: url)
    }

    private func startPlayback(url: URL, volume: Float, fadeInSeconds: TimeInterval) {
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.volume = fadeInSeconds > 0 ? 0.0 : volume
            newPlayer.prepareToPlay()
            newPlayer.play()
            if fadeInSeconds > 0 {
                newPlayer.setVolume(volume, fadeDuration: fadeInSeconds)
            }
            player = newPlayer
            onPlaybackStateChanged?(true)
        } catch {
            pendingDoaURL = nil
            onPlaybackStateChanged?(false)
        }
    }

    private func resolveURL(for choice: PrayerAudioChoice, importedClips: [ImportedAudioClip]) -> URL? {
        switch choice {
        case .none:
            return nil
        case .bundledPlaceholder:
            return Bundle.main.url(forResource: "gentle-chime", withExtension: "wav", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: "gentle-chime", withExtension: "wav")
        case .imported(let id):
            guard let clip = importedClips.first(where: { $0.id == id }) else { return nil }
            let url = audioLibraryDirectory().appendingPathComponent(clip.storedFileName)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
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
                self.startPlayback(url: nextDoa, volume: self.currentVolume, fadeInSeconds: 1.0)
            } else {
                self.pendingDoaURL = nil
                self.player = nil
                self.onPlaybackStateChanged?(false)
            }
        }
    }
}
