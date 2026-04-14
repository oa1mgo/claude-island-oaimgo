# Music Source Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a generic source badge below the album artwork in the expanded notch music card, showing the playback app icon and app name when a now-playing source bundle identifier is available.

**Architecture:** Keep the existing media metadata pipeline unchanged and derive a new presentation model from `PlaybackState.bundleIdentifier` inside the music feature. `MusicManager` will resolve and cache source app metadata, while `MusicCardView` will render a compact badge below the artwork without altering current transport or progress behavior.

**Tech Stack:** Swift, SwiftUI, AppKit, Combine, `xcodebuild`

---

### Task 1: Add Source Presentation State To The Music Feature

**Files:**
- Modify: `ClaudeIsland/Services/Music/MusicManager.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add a nested source model and published state to `MusicManager`**

```swift
@MainActor
final class MusicManager: ObservableObject {
    struct SourceApp: Equatable {
        let bundleIdentifier: String
        let displayName: String
        let icon: NSImage?
    }

    @Published private(set) var playbackState = PlaybackState()
    @Published private(set) var albumArt: NSImage?
    @Published private(set) var sourceApp: SourceApp?
```

- [ ] **Step 2: Add cache storage and source derivation to the playback sink**

```swift
private var sourceCache: [String: SourceApp] = [:]

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
        self?.sourceApp = self?.resolveSourceApp(for: state.bundleIdentifier)
    }
    .store(in: &cancellables)
```

- [ ] **Step 3: Add the source-resolution helpers**

```swift
private func resolveSourceApp(for bundleIdentifier: String?) -> SourceApp? {
    guard let rawBundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawBundleIdentifier.isEmpty else {
        return nil
    }

    if let cached = sourceCache[rawBundleIdentifier] {
        return cached
    }

    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawBundleIdentifier)
    let bundle = appURL.flatMap(Bundle.init(url:))
    let displayName = resolvedDisplayName(for: rawBundleIdentifier, bundle: bundle)

    guard let displayName else { return nil }

    let icon = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
    let sourceApp = SourceApp(
        bundleIdentifier: rawBundleIdentifier,
        displayName: displayName,
        icon: icon
    )

    sourceCache[rawBundleIdentifier] = sourceApp
    return sourceApp
}

private func resolvedDisplayName(for bundleIdentifier: String, bundle: Bundle?) -> String? {
    if let override = sourceNameOverrides[bundleIdentifier] {
        return override
    }

    let bundleNameKeys = [
        "CFBundleDisplayName",
        kCFBundleNameKey as String
    ]

    for key in bundleNameKeys {
        if let value = bundle?.object(forInfoDictionaryKey: key) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }

    return fallbackDisplayName(from: bundleIdentifier)
}

private func fallbackDisplayName(from bundleIdentifier: String) -> String? {
    let lastComponent = bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    let cleaned = lastComponent.replacingOccurrences(of: "-", with: " ")
    let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
}
```

- [ ] **Step 4: Add a small override table for awkward app names**

```swift
private let sourceNameOverrides: [String: String] = [
    "com.apple.Music": "Apple Music",
    "com.tencent.QQMusicMac": "QQ Music",
    "com.microsoft.edgemac": "Microsoft Edge"
]
```

- [ ] **Step 5: Build to verify the source model compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit the music source model changes**

```bash
git add ClaudeIsland/Services/Music/MusicManager.swift
git commit -m "feat: resolve music source app metadata"
```

### Task 2: Render The Source Badge Under The Artwork

**Files:**
- Modify: `ClaudeIsland/UI/Views/MusicCardView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Replace the artwork slot with an artwork-plus-source stack**

```swift
var body: some View {
    HStack(spacing: 12) {
        artworkColumn

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(primaryLineText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(secondaryLineText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                controlsRow
            }

            TimelineView(.animation(minimumInterval: musicManager.playbackState.isPlaying ? 0.2 : 1.0)) { timeline in
                let elapsedTime = displayedElapsedTime(at: timeline.date)

                ProgressView(value: progressFraction(for: elapsedTime))
                    .tint(Color.white.opacity(0.9))

                HStack {
                    Text(formatTime(elapsedTime))
                    Spacer()
                    Text(formatTime(musicManager.playbackState.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.05))
    )
}
```

- [ ] **Step 2: Add the new artwork column view and keep the current artwork button behavior**

```swift
var artworkColumn: some View {
    VStack(alignment: .center, spacing: 6) {
        artwork

        if let sourceApp = musicManager.sourceApp {
            sourceBadge(for: sourceApp)
        }
    }
    .frame(width: 56)
}

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
```

- [ ] **Step 3: Add a badge renderer for icon-plus-name and a text-only fallback**

```swift
@ViewBuilder
func sourceBadge(for sourceApp: MusicManager.SourceApp) -> some View {
    HStack(spacing: 5) {
        if let icon = sourceApp.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 13, height: 13)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }

        Text(sourceApp.displayName)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.72))
            .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.07))
    )
}
```

- [ ] **Step 4: Build to verify the updated view compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit the music card UI update**

```bash
git add ClaudeIsland/UI/Views/MusicCardView.swift
git commit -m "feat: show source badge in music card"
```

### Task 3: Verify Playback Scenarios And Polish Fallbacks

**Files:**
- Modify: `ClaudeIsland/Services/Music/MusicManager.swift`
- Modify: `ClaudeIsland/UI/Views/MusicCardView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Tighten display-name fallback formatting if manual verification reveals ugly names**

```swift
private func fallbackDisplayName(from bundleIdentifier: String) -> String? {
    let lastComponent = bundleIdentifier
        .split(separator: ".")
        .last
        .map(String.init) ?? bundleIdentifier

    let withSpaces = lastComponent
        .replacingOccurrences(of: "-", with: " ")
        .replacingOccurrences(of: "_", with: " ")

    let trimmed = withSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    return trimmed
        .split(separator: " ")
        .map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        .joined(separator: " ")
}
```

- [ ] **Step 2: Adjust badge width or spacing only if the expanded card shows clipping**

```swift
var artworkColumn: some View {
    VStack(alignment: .center, spacing: 6) {
        artwork

        if let sourceApp = musicManager.sourceApp {
            sourceBadge(for: sourceApp)
        }
    }
    .frame(width: 64)
}
```

- [ ] **Step 3: Rebuild after final polish**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify the main playback cases**

Run these checks in the built app:

- Apple Music playback shows `Apple Music` plus the Music app icon below the artwork
- QQ Music playback shows `QQ Music` plus the QQ Music app icon below the artwork
- Edge web playback shows `Microsoft Edge` plus the Edge app icon below the artwork
- A source without a resolved icon still shows a stable text badge when a name is available
- A source without a usable bundle identifier hides the badge and keeps the card aligned

Expected: the badge updates with source changes and the rest of the music card behaves exactly as before.

- [ ] **Step 5: Commit the final polish**

```bash
git add ClaudeIsland/Services/Music/MusicManager.swift ClaudeIsland/UI/Views/MusicCardView.swift
git commit -m "chore: polish music source badge fallbacks"
```
