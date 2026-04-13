import AppKit
import Combine
import Foundation

@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published private(set) var playbackState = PlaybackState()
    @Published private(set) var albumArt: NSImage?

    private var cancellables = Set<AnyCancellable>()
    private let controller: MediaControllerProtocol

    init(controller: MediaControllerProtocol = NowPlayingController()) {
        self.controller = controller

        controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
                self?.albumArt = state.artworkData.flatMap(NSImage.init(data:))
            }
            .store(in: &cancellables)

        controller.refresh()
    }

    var isVisible: Bool {
        playbackState.hasDisplayableContent
    }

    func refresh() { controller.refresh() }
    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }
    func openSourceApp() { controller.openSourceApp() }
}
