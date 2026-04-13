import AppKit
import Combine
import CryptoKit
import Foundation
import OSLog

@MainActor
final class NowPlayingController: MediaControllerProtocol {
    private enum AdapterCommand: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private struct AdapterExecutionResult {
        let data: Data
        let standardError: String
        let terminationStatus: Int32
    }

    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.celestial.ClaudeIsland", category: "NowPlaying")

    private var cachedFrameworkURL: URL?
    private var streamProcess: Process?
    private var streamPipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init() {
        startStreamingUpdates()
    }

    deinit {
        streamTask?.cancel()

        if let streamProcess, streamProcess.isRunning {
            streamProcess.terminate()
        }

        if let streamPipeHandler {
            Task {
                await streamPipeHandler.close()
            }
        }
    }
}

extension NowPlayingController {
    func refresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let result = await self.runAdapter(arguments: ["get"], context: "refresh") else { return }

            guard result.terminationStatus == 0 else {
                self.logger.error("Adapter refresh failed with status \(result.terminationStatus)")
                return
            }

            self.applySnapshot(from: result.data)
        }
    }

    func togglePlayPause() {
        sendCommand(.togglePlayPause)
    }

    func nextTrack() {
        sendCommand(.nextTrack)
    }

    func previousTrack() {
        sendCommand(.previousTrack)
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

private extension NowPlayingController {
    func startStreamingUpdates() {
        guard let scriptURL = adapterScriptURL(), let frameworkURL = adapterFrameworkURL() else {
            return
        }

        let process = Process()
        let pipeHandler = JSONLinesPipeHandler()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path, "stream", "--debounce=50"]
        process.standardOutput = pipeHandler.pipe
        process.standardError = errorPipe
        process.terminationHandler = { [logger] process in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus != 0 {
                logger.error("Adapter stream exited with status \(process.terminationStatus): \(errorOutput, privacy: .public)")
            }
        }

        do {
            try process.run()
            streamProcess = process
            streamPipeHandler = pipeHandler
            streamTask = Task { @MainActor [weak self] in
                guard let self else { return }

                await pipeHandler.readJSONLines(as: AdapterStreamEvent.self, logger: self.logger) { [weak self] event in
                    guard let self else { return }
                    self.apply(event: event)
                }
            }
        } catch {
            logger.error("Failed to launch adapter stream: \(String(describing: error), privacy: .public)")
            streamProcess = nil
            streamPipeHandler = nil
        }
    }

    private func sendCommand(_ command: AdapterCommand) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let result = await self.runAdapter(
                arguments: ["send", String(command.rawValue)],
                context: "send-\(command.rawValue)"
            ) else {
                return
            }

            guard result.terminationStatus == 0 else {
                self.logger.error("Adapter command \(command.rawValue) failed with status \(result.terminationStatus)")
                return
            }

            try? await Task.sleep(for: .milliseconds(200))
            self.refresh()
        }
    }

    private func runAdapter(arguments: [String], context: String) async -> AdapterExecutionResult? {
        guard let scriptURL = adapterScriptURL(), let frameworkURL = adapterFrameworkURL() else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkURL.path] + arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { [logger] process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    logger.error("Adapter \(context, privacy: .public) failed with status \(process.terminationStatus): \(errorOutput, privacy: .public)")
                }

                continuation.resume(
                    returning: AdapterExecutionResult(
                        data: outputData,
                        standardError: errorOutput,
                        terminationStatus: process.terminationStatus
                    )
                )
            }

            do {
                try process.run()
            } catch {
                logger.error("Failed to launch adapter \(context, privacy: .public): \(String(describing: error), privacy: .public)")
                continuation.resume(returning: nil)
            }
        }
    }

    func adapterScriptURL() -> URL? {
        if let url = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl") {
            return url
        }

        logger.error("Missing bundled resource: mediaremote-adapter.pl")
        return nil
    }

    func adapterFrameworkURL() -> URL? {
        if let cachedFrameworkURL, FileManager.default.fileExists(atPath: cachedFrameworkURL.path) {
            return cachedFrameworkURL
        }

        guard let archiveURL = Bundle.main.url(forResource: "MediaRemoteAdapter.framework", withExtension: "zip") else {
            logger.error("Missing bundled resource: MediaRemoteAdapter.framework.zip")
            return nil
        }

        guard
            let archiveData = try? Data(contentsOf: archiveURL),
            let extractionRoot = adapterExtractionRoot(for: archiveData)
        else {
            logger.error("Failed to prepare adapter extraction root")
            return nil
        }

        let frameworkURL = extractionRoot.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        if FileManager.default.fileExists(atPath: frameworkURL.path) {
            cachedFrameworkURL = frameworkURL
            return frameworkURL
        }

        let extractedFrameworkURL = extractFrameworkArchive(at: archiveURL, to: extractionRoot)
        cachedFrameworkURL = extractedFrameworkURL
        return extractedFrameworkURL
    }

    func applySnapshot(from data: Data) {
        guard let snapshot = try? decoder.decode(AdapterSnapshot.self, from: data) else {
            logDecodeFailure(for: data, context: "snapshot")
            return
        }

        let state = makePlaybackState(
            payload: snapshot,
            diff: false,
            previous: subject.value
        )
        subject.send(state)
    }

    func apply(event: AdapterStreamEvent) {
        guard event.type == nil || event.type == "data" else { return }

        let state = makePlaybackState(
            payload: event.payload,
            diff: event.diff ?? false,
            previous: subject.value
        )
        subject.send(state)
    }

    func makePlaybackState(
        payload: AdapterPayload,
        diff: Bool,
        previous: PlaybackState
    ) -> PlaybackState {
        PlaybackState(
            bundleIdentifier: payload.bundleIdentifier
                ?? payload.parentApplicationBundleIdentifier
                ?? (diff ? previous.bundleIdentifier : NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
            isPlaying: payload.playing ?? (diff ? previous.isPlaying : false),
            title: resolvedString(payload.title, previous: previous.title, diff: diff),
            artist: resolvedString(payload.artist, previous: previous.artist, diff: diff),
            album: resolvedString(payload.album, previous: previous.album, diff: diff),
            currentTime: resolvedDouble(payload.elapsedTime, previous: previous.currentTime, diff: diff),
            duration: resolvedDouble(payload.duration, previous: previous.duration, diff: diff),
            playbackRate: resolvedDouble(payload.playbackRate, previous: previous.playbackRate, diff: diff),
            lastUpdated: resolvedDate(payload.timestamp, previous: previous.lastUpdated, diff: diff),
            artworkData: resolvedArtworkData(payload.artworkData, previous: previous.artworkData, diff: diff)
        )
    }

    func resolvedString(_ value: String?, previous: String, diff: Bool) -> String {
        if let value {
            return value
        }
        return diff ? previous : ""
    }

    func resolvedDouble(_ value: Double?, previous: Double, diff: Bool) -> Double {
        if let value {
            return value
        }
        return diff ? previous : 0
    }

    func resolvedArtworkData(_ value: String?, previous: Data?, diff: Bool) -> Data? {
        if let value {
            return Data(base64Encoded: value)
        }
        return diff ? previous : nil
    }

    func resolvedDate(_ value: String?, previous: Date, diff: Bool) -> Date {
        if let value, let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return diff ? previous : Date()
    }

    func logDecodeFailure(for data: Data, context: String) {
        let sample = String(data: data.prefix(256), encoding: .utf8) ?? "<non-utf8>"
        logger.error("Failed to decode adapter \(context, privacy: .public): \(sample, privacy: .public)")
    }

    func adapterExtractionRoot(for archiveData: Data) -> URL? {
        let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        let baseDirectoryName = Bundle.main.bundleIdentifier ?? "ClaudeIsland"

        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            logger.error("Unable to resolve caches directory for adapter extraction")
            return nil
        }

        let baseURL = cachesURL
            .appendingPathComponent(baseDirectoryName, isDirectory: true)
            .appendingPathComponent("MusicAdapter", isDirectory: true)

        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent(digest, isDirectory: true)
    }

    func extractFrameworkArchive(at archiveURL: URL, to extractionRoot: URL) -> URL? {
        let finalFrameworkURL = extractionRoot.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        let tempRootURL = extractionRoot.deletingLastPathComponent()
            .appendingPathComponent("\(extractionRoot.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: tempRootURL, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, tempRootURL.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                logger.error("Framework archive extraction failed with status \(process.terminationStatus)")
                try? FileManager.default.removeItem(at: tempRootURL)
                return nil
            }

            let extractedFrameworkURL = tempRootURL.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
            guard FileManager.default.fileExists(atPath: extractedFrameworkURL.path) else {
                logger.error("Extracted framework missing after archive expansion")
                try? FileManager.default.removeItem(at: tempRootURL)
                return nil
            }

            do {
                try FileManager.default.moveItem(at: tempRootURL, to: extractionRoot)
            } catch {
                if FileManager.default.fileExists(atPath: finalFrameworkURL.path) {
                    try? FileManager.default.removeItem(at: tempRootURL)
                    return finalFrameworkURL
                }

                logger.error("Failed to finalize framework extraction: \(String(describing: error), privacy: .public)")
                try? FileManager.default.removeItem(at: tempRootURL)
                return nil
            }

            return finalFrameworkURL
        } catch {
            logger.error("Failed to extract framework archive: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: tempRootURL)
            return nil
        }
    }
}

private struct AdapterStreamEvent: Decodable {
    let type: String?
    let diff: Bool?
    let payload: AdapterSnapshot
}

private struct AdapterSnapshot: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let timestamp: String?
    let playbackRate: Double?
    let artworkData: String?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
}

private typealias AdapterPayload = AdapterSnapshot

private actor JSONLinesPipeHandler {
    let pipe = Pipe()
    private let fileHandle: FileHandle
    private var buffer = ""

    init() {
        fileHandle = pipe.fileHandleForReading
    }

    func readJSONLines<T: Decodable>(
        as type: T.Type,
        logger: Logger,
        onLine: @escaping (T) async -> Void
    ) async {
        do {
            while true {
                let data = try await readData()
                guard !data.isEmpty else { break }

                if let chunk = String(data: data, encoding: .utf8) {
                    buffer.append(chunk)

                    while let range = buffer.range(of: "\n") {
                        let line = String(buffer[..<range.lowerBound])
                        buffer = String(buffer[range.upperBound...])

                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8) else { continue }

                        do {
                            let value = try JSONDecoder().decode(T.self, from: data)
                            await onLine(value)
                        } catch {
                            let sample = String(line.prefix(256))
                            logger.error("Failed to decode adapter stream line: \(sample, privacy: .public)")
                        }
                    }
                }
            }
        } catch {
            logger.error("Failed while reading adapter stream: \(String(describing: error), privacy: .public)")
        }
    }

    func close() async {
        fileHandle.readabilityHandler = nil
        try? fileHandle.close()
        try? pipe.fileHandleForWriting.close()
    }

    private func readData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
}
