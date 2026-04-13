# ClaudeIsland Music Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a self-contained music playback subsystem to ClaudeIsland that powers an expanded home-panel music card and a lower-priority closed-notch music activity.

**Architecture:** Introduce a small music domain built around `PlaybackState`, `MediaControllerProtocol`, and `MusicManager`, then wire that domain into the home panel and closed-notch presentation without touching `SessionStore` or Claude hook ingestion. The first implementation uses a single system now-playing controller and keeps advanced `boring.notch` capabilities out of scope.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine, Xcode project filesystem-synced sources, `xcodebuild`

---

### Task 1: Create The Music Domain Model And Manager

**Files:**
- Create: `ClaudeIsland/Models/PlaybackState.swift`
- Create: `ClaudeIsland/Services/Music/MediaControllerProtocol.swift`
- Create: `ClaudeIsland/Services/Music/MusicManager.swift`
- Test: manual build via `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the playback model**

```swift
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
```

- [ ] **Step 2: Add the controller protocol**

```swift
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
```

- [ ] **Step 3: Add the observable music manager**

```swift
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
```

- [ ] **Step 4: Build to verify the new model layer compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: build progresses until either success or a missing `NowPlayingController` type error, which will be resolved in Task 2.

- [ ] **Step 5: Commit the domain skeleton**

```bash
git add ClaudeIsland/Models/PlaybackState.swift ClaudeIsland/Services/Music/MediaControllerProtocol.swift ClaudeIsland/Services/Music/MusicManager.swift
git commit -m "feat: add music playback domain skeleton"
```

### Task 2: Implement The Initial System Now Playing Controller

**Files:**
- Create: `ClaudeIsland/Services/Music/NowPlayingController.swift`
- Modify: `ClaudeIsland/Services/Music/MusicManager.swift`
- Test: manual build via `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the now-playing controller shell**

```swift
import AppKit
import Combine
import Foundation
import MediaPlayer

final class NowPlayingController: MediaControllerProtocol {
    private let subject = CurrentValueSubject<PlaybackState, Never>(PlaybackState())
    private let player = MPMusicPlayerController.systemMusicPlayer

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackChange),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        player.beginGeneratingPlaybackNotifications()
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }
}
```

- [ ] **Step 2: Implement normalized state refresh**

```swift
extension NowPlayingController {
    func refresh() {
        let item = player.nowPlayingItem
        let artworkData = item?.artwork?.image(at: NSSize(width: 256, height: 256)).tiffRepresentation

        subject.send(
            PlaybackState(
                bundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                isPlaying: player.playbackState == .playing,
                title: item?.title ?? "",
                artist: item?.artist ?? "",
                album: item?.albumTitle ?? "",
                currentTime: player.currentPlaybackTime,
                duration: item?.playbackDuration ?? 0,
                artworkData: artworkData
            )
        )
    }

    @objc
    private func handlePlaybackChange() {
        refresh()
    }
}
```

- [ ] **Step 3: Implement transport and app-open actions**

```swift
extension NowPlayingController {
    func togglePlayPause() {
        player.playbackState == .playing ? player.pause() : player.play()
        refresh()
    }

    func nextTrack() {
        player.skipToNextItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    func previousTrack() {
        player.skipToPreviousItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    func openSourceApp() {
        if let bundleIdentifier = subject.value.bundleIdentifier {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier, options: [], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
```

- [ ] **Step 4: Tighten the manager for fallback artwork and visibility**

```swift
var fallbackSymbolName: String {
    playbackState.isPlaying ? "music.note" : "music.note.list"
}

var progressFraction: Double {
    guard playbackState.duration > 0 else { return 0 }
    return min(max(playbackState.currentTime / playbackState.duration, 0), 1)
}
```

- [ ] **Step 5: Build and verify the controller compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: PASS, or a targeted compile error around `MediaPlayer`/availability that is fixed before moving on.

- [ ] **Step 6: Commit the controller**

```bash
git add ClaudeIsland/Services/Music/NowPlayingController.swift ClaudeIsland/Services/Music/MusicManager.swift
git commit -m "feat: add system now playing controller"
```

### Task 3: Add The Expanded Music Card To The Home Panel

**Files:**
- Create: `ClaudeIsland/UI/Views/MusicCardView.swift`
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Test: manual build via `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the music card view**

```swift
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
```

- [ ] **Step 2: Add artwork and time formatting helpers**

```swift
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
```

- [ ] **Step 3: Insert the card at the top of the home panel**

```swift
@StateObject private var musicManager = MusicManager.shared

var body: some View {
    VStack(spacing: 8) {
        if musicManager.isVisible {
            MusicCardView(musicManager: musicManager)
        }

        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }
}
```

- [ ] **Step 4: Keep the list scrollable without regressing current behavior**

```swift
private var instancesList: some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 2) {
            ForEach(sortedInstances) { session in
                InstanceRow(
                    session: session,
                    onFocus: { focusSession(session) },
                    onChat: { openChat(session) },
                    onArchive: { archiveSession(session) },
                    onApprove: { approveSession(session) },
                    onReject: { rejectSession(session) }
                )
                .id(session.stableId)
            }
        }
        .padding(.vertical, 4)
    }
    .scrollBounceBehavior(.basedOnSize)
}
```

- [ ] **Step 5: Build and verify the home panel integration**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: PASS with the music card compiled into the app.

- [ ] **Step 6: Commit the home panel UI**

```bash
git add ClaudeIsland/UI/Views/MusicCardView.swift ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: add home panel music card"
```

### Task 4: Add The Closed-Notch Compact Music Activity

**Files:**
- Create: `ClaudeIsland/UI/Components/CompactMusicActivityView.swift`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`
- Test: manual build via `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the compact closed-notch music activity view**

```swift
import SwiftUI

struct CompactMusicActivityView: View {
    @ObservedObject var musicManager: MusicManager

    var body: some View {
        HStack(spacing: 8) {
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
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(musicManager.playbackState.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(musicManager.playbackState.artist)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
            }

            Image(systemName: musicManager.playbackState.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}
```

- [ ] **Step 2: Add a dedicated music-activity visibility check in `NotchView`**

```swift
@StateObject private var musicManager = MusicManager.shared

private var showMusicActivity: Bool {
    musicManager.isVisible &&
    !hasPendingPermission &&
    !isAnyProcessing &&
    !hasWaitingForInput
}
```

- [ ] **Step 3: Thread the compact view into the closed header layout**

```swift
private var showClosedActivity: Bool {
    isProcessing || hasPendingPermission || hasWaitingForInput || showMusicActivity
}

@ViewBuilder
private var claudeClosedActivityView: some View {
    HStack(spacing: 4) {
        ClaudeCrabIcon(size: 14, animateLegs: isProcessing)

        if hasPendingPermission {
            PermissionIndicatorIcon(size: 14, color: Color(red: 0.85, green: 0.47, blue: 0.34))
        } else if hasWaitingForInput {
            ReadyForInputIndicatorIcon(size: 14)
        }
    }
}

@ViewBuilder
private var headerRow: some View {
    HStack(spacing: 0) {
        if showMusicActivity {
            CompactMusicActivityView(musicManager: musicManager)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            claudeClosedActivityView
        }
    }
}
```

- [ ] **Step 4: Preserve Claude priority and current compact-state behavior**

```swift
private var claudeExpansionWidth: CGFloat {
    let permissionIndicatorWidth: CGFloat = hasPendingPermission ? 18 : 0

    if activityCoordinator.expandingActivity.show {
        switch activityCoordinator.expandingActivity.type {
        case .claude:
            let baseWidth = 2 * max(0, closedNotchSize.height - 12) + 20
            return baseWidth + permissionIndicatorWidth
        case .none:
            break
        }
    }

    if hasPendingPermission {
        return 2 * max(0, closedNotchSize.height - 12) + 20 + permissionIndicatorWidth
    }

    if hasWaitingForInput {
        return 2 * max(0, closedNotchSize.height - 12) + 20
    }

    return 0
}

private var expansionWidth: CGFloat {
    if isProcessing || hasPendingPermission || hasWaitingForInput {
        return claudeExpansionWidth
    }

    if showMusicActivity {
        return max(120, closedNotchSize.height * 3.2)
    }

    return 0
}
```

- [ ] **Step 5: Build and verify the closed-notch integration**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: PASS with the compact music activity compiled and no regressions in existing Claude compact states.

- [ ] **Step 6: Commit the compact activity**

```bash
git add ClaudeIsland/UI/Components/CompactMusicActivityView.swift ClaudeIsland/UI/Views/NotchView.swift
git commit -m "feat: add compact music notch activity"
```

### Task 5: Verify The Feature End-To-End And Clean Up

**Files:**
- Modify: `ClaudeIsland/Services/Music/NowPlayingController.swift`
- Modify: `ClaudeIsland/UI/Views/MusicCardView.swift`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Run a clean build for the full feature**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: PASS

- [ ] **Step 2: Manually verify idle and active music states**

Run the app in Xcode, then verify:

```text
1. No active music: no music card, no compact music activity.
2. Music playing: music card appears in expanded home panel.
3. Music playing + closed notch: compact music activity appears.
```

Expected: all three checks behave exactly as described.

- [ ] **Step 3: Manually verify Claude priority suppression**

Run Claude Code so the notch enters active states, then verify:

```text
1. Claude processing suppresses compact music activity.
2. Claude permission approval suppresses compact music activity.
3. Expanded home panel still shows the music card even while Claude sessions exist.
```

Expected: compact music yields to Claude priority states; expanded panel remains stable.

- [ ] **Step 4: Fix any polish issues discovered during verification**

Targeted fixes should follow these examples:

```swift
Text(musicManager.playbackState.title.isEmpty ? "Unknown Track" : musicManager.playbackState.title)
    .lineLimit(1)
    .truncationMode(.tail)

let clampedTime = min(max(playbackState.currentTime, 0), playbackState.duration)
```

- [ ] **Step 5: Commit the verification cleanup**

```bash
git add ClaudeIsland/Services/Music/NowPlayingController.swift ClaudeIsland/UI/Views/MusicCardView.swift ClaudeIsland/UI/Views/NotchView.swift
git commit -m "fix: polish music integration behavior"
```
