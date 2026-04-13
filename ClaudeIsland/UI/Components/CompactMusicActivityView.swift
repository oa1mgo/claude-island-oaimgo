import SwiftUI

struct CompactMusicActivityView: View {
    @ObservedObject var musicManager: MusicManager

    var body: some View {
        HStack(spacing: 8) {
            artwork

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(secondaryText)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: musicManager.playbackState.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension CompactMusicActivityView {
    var artwork: some View {
        Group {
            if let image = musicManager.albumArt {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(width: 16, height: 16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    var primaryText: String {
        trimmedText(musicManager.playbackState.title)
            ?? trimmedText(musicManager.playbackState.artist)
            ?? "Now Playing"
    }

    var secondaryText: String {
        let primary = primaryText
        let candidates = [
            trimmedText(musicManager.playbackState.artist),
            trimmedText(musicManager.playbackState.album)
        ]
        .compactMap { $0 }
        .filter { $0 != primary }

        return candidates.first ?? "Music"
    }

    func trimmedText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
