import SwiftUI

struct MusicCardView: View {
    @ObservedObject var musicManager: MusicManager

    var body: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 6) {
                Text(musicManager.playbackState.title.isEmpty ? "Nothing Playing" : musicManager.playbackState.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(musicManager.playbackState.artist.isEmpty ? musicManager.playbackState.album : musicManager.playbackState.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)

                ProgressView(value: musicManager.progressFraction)
                    .tint(Color.white.opacity(0.9))

                HStack {
                    Text(formatTime(musicManager.playbackState.currentTime))
                    Spacer()
                    Text(formatTime(musicManager.playbackState.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            }

            VStack(spacing: 8) {
                Button(action: musicManager.previousTrack) { Image(systemName: "backward.fill") }
                Button(action: musicManager.togglePlayPause) { Image(systemName: musicManager.playbackState.isPlaying ? "pause.fill" : "play.fill") }
                Button(action: musicManager.nextTrack) { Image(systemName: "forward.fill") }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private extension MusicCardView {
    var artwork: some View {
        Button(action: musicManager.openSourceApp) {
            Group {
                if let image = musicManager.albumArt {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: musicManager.fallbackSymbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
