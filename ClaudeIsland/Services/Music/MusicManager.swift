import AppKit
import Combine
import Foundation

@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var playbackState = PlaybackState()
    @Published private(set) var albumArt: NSImage?

    private var cancellables = Set<AnyCancellable>()
    private let controller: MediaControllerProtocol

    init(controller: MediaControllerProtocol? = nil) {
        self.controller = controller ?? NowPlayingController()

        self.controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
                self?.albumArt = state.artworkData.flatMap(NSImage.init(data:))
            }
            .store(in: &cancellables)

        self.controller.refresh()
    }

    var isVisible: Bool {
        playbackState.hasDisplayableContent
    }

    var fallbackSymbolName: String {
        playbackState.isPlaying ? "music.note" : "music.note.list"
    }

    var progressFraction: Double {
        guard playbackState.duration > 0 else { return 0 }
        return min(max(playbackState.currentTime / playbackState.duration, 0), 1)
    }

    func refresh() { controller.refresh() }
    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }
    func openSourceApp() { controller.openSourceApp() }
}
