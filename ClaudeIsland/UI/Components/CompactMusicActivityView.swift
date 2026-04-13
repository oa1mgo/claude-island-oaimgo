import AppKit
import SwiftUI

struct CompactMusicActivityView: View {
    @ObservedObject var musicManager: MusicManager

    var body: some View {
        HStack(spacing: 8) {
            artwork
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(secondaryText)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            CompactPlaybackIndicatorView(isPlaying: musicManager.playbackState.isPlaying)
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
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

private struct CompactPlaybackIndicatorView: View {
    let isPlaying: Bool

    var body: some View {
        CompactAudioSpectrumView(isPlaying: isPlaying)
            .frame(width: 16, height: 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct CompactAudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool

    func makeNSView(context: Context) -> CompactAudioSpectrum {
        let spectrum = CompactAudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: CompactAudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}

private final class CompactAudioSpectrum: NSView {
    private let barWidth: CGFloat = 2
    private let barCount = 4
    private let totalHeight: CGFloat = 14

    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying = true
    private var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    deinit {
        animationTimer?.invalidate()
    }

    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing || animationTimer == nil else { return }

        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    private func setupBars() {
        let spacing = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for index in 0..<barCount {
            let xPosition = CGFloat(index) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            barLayer.path = roundedBarPath()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }

    private func roundedBarPath() -> CGPath {
        let path = NSBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        )

        return path.cgPath
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateBars()
        }

        updateBars()
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (index, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[index]
            let targetScale = CGFloat.random(in: 0.35...1.0)
            barScales[index] = targetScale

            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false

            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }

            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[index] = 0.35
        }
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
