import Foundation

struct PlaybackState: Equatable, Sendable {
    var bundleIdentifier: String?
    var isPlaying: Bool
    var title: String
    var artist: String
    var album: String
    var currentTime: TimeInterval
    var duration: TimeInterval
    var artworkData: Data?

    init(
        bundleIdentifier: String? = nil,
        isPlaying: Bool = false,
        title: String = "",
        artist: String = "",
        album: String = "",
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        artworkData: Data? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.currentTime = currentTime
        self.duration = duration
        self.artworkData = artworkData
    }

    var hasDisplayableContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
