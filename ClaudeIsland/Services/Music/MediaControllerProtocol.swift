import Combine
import Foundation

protocol MediaControllerProtocol: AnyObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    func refresh()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func openSourceApp()
}
