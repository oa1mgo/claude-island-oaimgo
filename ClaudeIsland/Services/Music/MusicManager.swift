import AppKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

@MainActor
final class MusicManager: ObservableObject {
    @Published private(set) var playbackState = PlaybackState()
    @Published private(set) var albumArt: NSImage?
    @Published private(set) var artworkGradient: [NSColor] = [
        NSColor.white.withAlphaComponent(0.95),
        NSColor.white.withAlphaComponent(0.75),
        NSColor.white.withAlphaComponent(0.55)
    ]

    private var cancellables = Set<AnyCancellable>()
    private let controller: MediaControllerProtocol
    private let ciContext = CIContext(options: nil)

    init(controller: MediaControllerProtocol? = nil) {
        self.controller = controller ?? NowPlayingController()

        self.controller.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
                let image = state.artworkData.flatMap(NSImage.init(data:))
                self?.albumArt = image
                self?.artworkGradient = self?.gradientColors(from: image) ?? [
                    NSColor.white.withAlphaComponent(0.95),
                    NSColor.white.withAlphaComponent(0.75),
                    NSColor.white.withAlphaComponent(0.55)
                ]
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

    private func gradientColors(from image: NSImage?) -> [NSColor] {
        guard
            let image,
            let tiffData = image.tiffRepresentation,
            let ciImage = CIImage(data: tiffData)
        else {
            return [
                NSColor.white.withAlphaComponent(0.95),
                NSColor.white.withAlphaComponent(0.75),
                NSColor.white.withAlphaComponent(0.55)
            ]
        }

        let extent = ciImage.extent
        guard !extent.isEmpty else {
            return [
                NSColor.white.withAlphaComponent(0.95),
                NSColor.white.withAlphaComponent(0.75),
                NSColor.white.withAlphaComponent(0.55)
            ]
        }

        let regions = [
            CGRect(x: extent.minX, y: extent.minY, width: extent.width * 0.5, height: extent.height),
            CGRect(x: extent.minX + extent.width * 0.25, y: extent.minY, width: extent.width * 0.5, height: extent.height),
            CGRect(x: extent.minX + extent.width * 0.5, y: extent.minY, width: extent.width * 0.5, height: extent.height)
        ]

        let extracted = regions.compactMap { averageColor(in: ciImage, region: $0) }.map(normalizedGradientColor(_:))
        if extracted.count >= 3 {
            return extracted
        }

        if let single = averageColor(in: ciImage, region: extent) {
            let base = normalizedGradientColor(single)
            return [
                adjustedColor(base, saturation: 1.15, brightness: 1.18, alpha: 0.95),
                adjustedColor(base, saturation: 1.0, brightness: 1.0, alpha: 0.8),
                adjustedColor(base, saturation: 0.9, brightness: 0.78, alpha: 0.65)
            ]
        }

        return [
            NSColor.white.withAlphaComponent(0.95),
            NSColor.white.withAlphaComponent(0.75),
            NSColor.white.withAlphaComponent(0.55)
        ]
    }

    private func averageColor(in image: CIImage, region: CGRect) -> NSColor? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image.cropped(to: region)
        filter.extent = region

        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return NSColor(
            calibratedRed: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }

    private func normalizedGradientColor(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let adjustedSaturation = max(0.35, min(saturation * 1.18 + 0.08, 0.95))
        let adjustedBrightness = max(0.5, min(brightness * 1.08 + 0.1, 0.98))

        let base = NSColor(calibratedHue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1)
        return adjustedColor(base, saturation: 1.0, brightness: 1.0, alpha: 0.92)
    }

    private func adjustedColor(_ color: NSColor, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) -> NSColor {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return color.withAlphaComponent(alpha) }

        var hue: CGFloat = 0
        var currentSaturation: CGFloat = 0
        var currentBrightness: CGFloat = 0
        var currentAlpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &currentSaturation, brightness: &currentBrightness, alpha: &currentAlpha)

        return NSColor(
            calibratedHue: hue,
            saturation: min(max(currentSaturation * saturation, 0), 1),
            brightness: min(max(currentBrightness * brightness, 0), 1),
            alpha: alpha
        )
    }
}
