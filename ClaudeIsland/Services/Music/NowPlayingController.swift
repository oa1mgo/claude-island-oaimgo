import AppKit
import Combine
import Foundation

final class NowPlayingController: MediaControllerProtocol {
    private enum AdapterCommand: Int {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private let decoder = JSONDecoder()

    private var streamProcess: Process?
    private var streamPipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init() {
        startStreamingUpdates()
        refresh()
    }

    deinit {
        streamTask?.cancel()
        streamProcess?.terminate()

        if let streamPipeHandler {
            Task {
                await streamPipeHandler.close()
            }
        }
    }
}

extension NowPlayingController {
    func refresh() {
        Task { [weak self] in
            guard let self, let data = await self.runAdapter(arguments: ["get"]) else { return }
            self.applySnapshot(from: data)
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
        guard let scriptURL = adapterScriptURL, let frameworkURL = adapterFrameworkURL else {
            return
        }

        let process = Process()
        let pipeHandler = JSONLinesPipeHandler()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkURL.path, "stream", "--debounce=50"]
        process.standardOutput = pipeHandler.pipe
        process.standardError = Pipe()

        do {
            try process.run()
            streamProcess = process
            streamPipeHandler = pipeHandler
            streamTask = Task { [weak self] in
                guard let self else { return }
                await pipeHandler.readJSONLines(as: AdapterStreamEvent.self) { [weak self] event in
                    await MainActor.run {
                        self?.apply(event: event)
                    }
                }
            }
        } catch {
            streamProcess = nil
            streamPipeHandler = nil
        }
    }

    private func sendCommand(_ command: AdapterCommand) {
        Task { [weak self] in
            guard let self else { return }
            _ = await self.runAdapter(arguments: ["send", String(command.rawValue)])

            try? await Task.sleep(for: .milliseconds(200))
            self.refresh()
        }
    }

    func runAdapter(arguments: [String]) async -> Data? {
        guard let scriptURL = adapterScriptURL, let frameworkURL = adapterFrameworkURL else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkURL.path] + arguments
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            process.terminationHandler = { _ in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: data.isEmpty ? nil : data)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    var adapterScriptURL: URL? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    }

    var adapterFrameworkURL: URL? {
        guard let archiveURL = Bundle.main.url(forResource: "MediaRemoteAdapter.framework", withExtension: "zip") else {
            return nil
        }

        let extractionRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ClaudeIslandMediaRemoteAdapter",
            isDirectory: true
        )
        let frameworkURL = extractionRoot.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)

        if FileManager.default.fileExists(atPath: frameworkURL.path) {
            return frameworkURL
        }

        try? FileManager.default.removeItem(at: extractionRoot)
        try? FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractionRoot.path]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? frameworkURL : nil
        } catch {
            return nil
        }
    }

    func applySnapshot(from data: Data) {
        guard let snapshot = try? decoder.decode(AdapterSnapshot.self, from: data) else { return }

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
        let title = resolvedString(payload.title, previous: previous.title, diff: diff)
        let artist = resolvedString(payload.artist, previous: previous.artist, diff: diff)
        let album = resolvedString(payload.album, previous: previous.album, diff: diff)
        let currentTime = resolvedDouble(payload.elapsedTime, previous: previous.currentTime, diff: diff)
        let duration = resolvedDouble(payload.duration, previous: previous.duration, diff: diff)
        let artworkData = resolvedArtworkData(payload.artworkData, previous: previous.artworkData, diff: diff)

        return PlaybackState(
            bundleIdentifier: payload.bundleIdentifier
                ?? payload.parentApplicationBundleIdentifier
                ?? (diff ? previous.bundleIdentifier : NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
            isPlaying: payload.playing ?? (diff ? previous.isPlaying : false),
            title: title,
            artist: artist,
            album: album,
            currentTime: currentTime,
            duration: duration,
            artworkData: artworkData
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

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            while true {
                let data = try await readData()
                guard !data.isEmpty else { break }

                if let chunk = String(data: data, encoding: .utf8) {
                    buffer.append(chunk)

                    while let range = buffer.range(of: "\n") {
                        let line = String(buffer[..<range.lowerBound])
                        buffer = String(buffer[range.upperBound...])

                        guard
                            !line.isEmpty,
                            let data = line.data(using: .utf8),
                            let value = try? JSONDecoder().decode(T.self, from: data)
                        else {
                            continue
                        }

                        await onLine(value)
                    }
                }
            }
        } catch {
            return
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
