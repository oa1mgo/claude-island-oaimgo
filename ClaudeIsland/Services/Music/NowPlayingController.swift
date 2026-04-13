import AppKit
import Combine
import Foundation
#if canImport(MediaPlayer) && !os(macOS)
import MediaPlayer
#endif

final class NowPlayingController: MediaControllerProtocol {
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
#if canImport(MediaPlayer) && !os(macOS)
    private let player = MPMusicPlayerController.systemMusicPlayer
#endif

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init() {
#if canImport(MediaPlayer) && !os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        player.beginGeneratingPlaybackNotifications()
#endif
    }

    deinit {
#if canImport(MediaPlayer) && !os(macOS)
        player.endGeneratingPlaybackNotifications()
#endif
        NotificationCenter.default.removeObserver(self)
    }
}

extension NowPlayingController {
    func refresh() {
#if canImport(MediaPlayer) && !os(macOS)
        let item = player.nowPlayingItem
        let artworkData = item?.artwork?.image(at: NSSize(width: 256, height: 256)).tiffRepresentation

        subject.send(
            PlaybackState(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                isPlaying: player.playbackState == .playing,
                title: item?.title ?? "",
                artist: item?.artist ?? "",
                album: item?.albumTitle ?? "",
                currentTime: player.currentPlaybackTime,
                duration: item?.playbackDuration ?? 0,
                artworkData: artworkData
            )
        )
#else
        subject.send(
            PlaybackState(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            )
        )
#endif
    }

    @objc
    private func handlePlaybackChange() {
        refresh()
    }
}

extension NowPlayingController {
    func togglePlayPause() {
#if canImport(MediaPlayer) && !os(macOS)
        player.playbackState == .playing ? player.pause() : player.play()
#endif
        refresh()
    }

    func nextTrack() {
#if canImport(MediaPlayer) && !os(macOS)
        player.skipToNextItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
#else
        refresh()
#endif
    }

    func previousTrack() {
#if canImport(MediaPlayer) && !os(macOS)
        player.skipToPreviousItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
#else
        refresh()
#endif
    }

    func openSourceApp() {
        if let bundleIdentifier = subject.value.bundleIdentifier {
            NSWorkspace.shared.launchApplication(
                withBundleIdentifier: bundleIdentifier,
                options: [],
                additionalEventParamDescriptor: nil,
                launchIdentifier: nil
            )
        } else {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Music.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}
