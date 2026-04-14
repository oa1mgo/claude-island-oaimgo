# Expanded Notch Artwork-Adaptive Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a strong artwork-adaptive background theme for the expanded notch, keep the closed notch black, and expose a dynamic settings toggle to control the feature.

**Architecture:** Add a persisted `AppSettings` flag and a matching menu toggle, then compute the adaptive shell styling in `NotchView` using the existing `MusicManager.artworkGradient`. Use a minimal foreground token set for readability so the expanded home, menu, and chat surfaces inherit the stronger atmosphere without a full component redesign.

**Tech Stack:** Swift, SwiftUI, AppKit, UserDefaults, `xcodebuild`

---

### Task 1: Add The Persisted Settings Toggle

**Files:**
- Modify: `ClaudeIsland/Core/Settings.swift`
- Modify: `ClaudeIsland/UI/Views/NotchMenuView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the new settings key and accessor**

```swift
private enum Keys {
    static let notificationSound = "notificationSound"
    static let claudeDirectoryName = "claudeDirectoryName"
    static let artworkAdaptiveBackgroundEnabled = "artworkAdaptiveBackgroundEnabled"
}

static var artworkAdaptiveBackgroundEnabled: Bool {
    get {
        if defaults.object(forKey: Keys.artworkAdaptiveBackgroundEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: Keys.artworkAdaptiveBackgroundEnabled)
    }
    set {
        defaults.set(newValue, forKey: Keys.artworkAdaptiveBackgroundEnabled)
    }
}
```

- [ ] **Step 2: Add menu state for the new toggle**

```swift
@State private var hooksInstalled: Bool = false
@State private var launchAtLogin: Bool = false
@State private var artworkAdaptiveBackgroundEnabled: Bool = AppSettings.artworkAdaptiveBackgroundEnabled
```

- [ ] **Step 3: Add the settings menu row**

```swift
MenuToggleRow(
    icon: "photo.fill.on.rectangle.fill",
    label: "Artwork Adaptive Background",
    isOn: artworkAdaptiveBackgroundEnabled
) {
    artworkAdaptiveBackgroundEnabled.toggle()
    AppSettings.artworkAdaptiveBackgroundEnabled = artworkAdaptiveBackgroundEnabled
}
```

- [ ] **Step 4: Refresh the toggle state when the menu opens**

```swift
private func refreshStates() {
    hooksInstalled = HookInstaller.isInstalled()
    launchAtLogin = SMAppService.mainApp.status == .enabled
    artworkAdaptiveBackgroundEnabled = AppSettings.artworkAdaptiveBackgroundEnabled
    screenSelector.refreshScreens()
}
```

- [ ] **Step 5: Build to verify the settings path compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit the settings toggle changes**

```bash
git add ClaudeIsland/Core/Settings.swift ClaudeIsland/UI/Views/NotchMenuView.swift
git commit -m "feat: add adaptive notch background setting"
```

### Task 2: Add Expanded-Shell Adaptive Background Logic

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add a small theme model and activation helpers in `NotchView`**

```swift
private struct ExpandedNotchTheme {
    let backgroundGradient: LinearGradient
    let overlayColor: Color
    let primaryText: Color
    let secondaryText: Color
    let separator: Color
    let headerIcon: Color
}

private var isAdaptiveBackgroundEnabled: Bool {
    viewModel.status == .opened &&
    musicManager.isVisible &&
    AppSettings.artworkAdaptiveBackgroundEnabled
}
```

- [ ] **Step 2: Derive the expanded theme from `musicManager.artworkGradient`**

```swift
private var expandedNotchTheme: ExpandedNotchTheme {
    let colors = musicManager.artworkGradient.map(Color.init(nsColor:))
    let brightness = perceivedBrightness(for: musicManager.artworkGradient)
    let useDarkForeground = brightness > 0.72

    return ExpandedNotchTheme(
        backgroundGradient: LinearGradient(
            colors: colors + [colors.last ?? Color.black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        overlayColor: useDarkForeground ? Color.black.opacity(0.18) : Color.black.opacity(0.36),
        primaryText: useDarkForeground ? Color.black.opacity(0.82) : Color.white.opacity(0.96),
        secondaryText: useDarkForeground ? Color.black.opacity(0.58) : Color.white.opacity(0.62),
        separator: useDarkForeground ? Color.black.opacity(0.12) : Color.white.opacity(0.10),
        headerIcon: useDarkForeground ? Color.black.opacity(0.56) : Color.white.opacity(0.5)
    )
}
```

- [ ] **Step 3: Add helper functions for background brightness**

```swift
private func perceivedBrightness(for colors: [NSColor]) -> CGFloat {
    let samples = colors.compactMap { $0.usingColorSpace(.deviceRGB) }
    guard !samples.isEmpty else { return 0 }

    let total = samples.reduce(CGFloat.zero) { partialResult, color in
        partialResult + ((color.redComponent * 0.299) + (color.greenComponent * 0.587) + (color.blueComponent * 0.114))
    }

    return total / CGFloat(samples.count)
}
```

- [ ] **Step 4: Replace the expanded-shell black background with a conditional themed background**

```swift
.background {
    if isAdaptiveBackgroundEnabled {
        ZStack {
            expandedNotchTheme.backgroundGradient

            RadialGradient(
                colors: [
                    expandedNotchTheme.primaryText.opacity(0.08),
                    .clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: notchSize.width * 0.9
            )

            expandedNotchTheme.overlayColor
        }
    } else {
        Color.black
    }
}
```

- [ ] **Step 5: Keep the closed-notch top overlay black and only theme the expanded shell**

```swift
.overlay(alignment: .top) {
    Rectangle()
        .fill(viewModel.status == .opened && isAdaptiveBackgroundEnabled ? expandedNotchTheme.overlayColor : .black)
        .frame(height: 1)
        .padding(.horizontal, topCornerRadius)
}
```

- [ ] **Step 6: Build to verify the shell background compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit the adaptive shell background**

```bash
git add ClaudeIsland/UI/Views/NotchView.swift
git commit -m "feat: add expanded notch artwork background"
```

### Task 3: Thread Minimal Foreground Tokens Through Expanded Views

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`
- Modify: `ClaudeIsland/UI/Views/NotchMenuView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Expose the token values from `NotchView` to content**

```swift
private var expandedPrimaryTextColor: Color {
    isAdaptiveBackgroundEnabled ? expandedNotchTheme.primaryText : .white
}

private var expandedSecondaryTextColor: Color {
    isAdaptiveBackgroundEnabled ? expandedNotchTheme.secondaryText : .white.opacity(0.4)
}

private var expandedSeparatorColor: Color {
    isAdaptiveBackgroundEnabled ? expandedNotchTheme.separator : .white.opacity(0.08)
}

private var expandedHeaderIconColor: Color {
    isAdaptiveBackgroundEnabled ? expandedNotchTheme.headerIcon : .white.opacity(0.4)
}
```

- [ ] **Step 2: Apply the adaptive header icon color in `NotchView`**

```swift
Image(systemName: viewModel.contentType == .menu ? "xmark" : "line.3.horizontal")
    .font(.system(size: 11, weight: .medium))
    .foregroundColor(expandedHeaderIconColor)
    .frame(width: 22, height: 22)
    .contentShape(Rectangle())
```

- [ ] **Step 3: Pass adaptive colors into the expanded content**

```swift
Group {
    switch viewModel.contentType {
    case .instances:
        ClaudeInstancesView(
            sessionMonitor: sessionMonitor,
            viewModel: viewModel,
            musicManager: musicManager
        )
    case .menu:
        NotchMenuView(
            viewModel: viewModel,
            primaryTextColor: expandedPrimaryTextColor,
            secondaryTextColor: expandedSecondaryTextColor,
            separatorColor: expandedSeparatorColor
        )
    case .chat(let session):
        ChatView(
            sessionId: session.sessionId,
            initialSession: session,
            sessionMonitor: sessionMonitor,
            viewModel: viewModel
        )
    }
}
```

- [ ] **Step 4: Add color parameters to `NotchMenuView` and use them for text and separators**

```swift
struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let separatorColor: Color
```

```swift
Divider()
    .background(separatorColor)
    .padding(.vertical, 4)
```

Where the menu currently hardcodes white-based label colors, swap to the passed token values.

- [ ] **Step 5: Build to verify the token threading compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual verification**

Verify in the running app:

- Expanded home panel shows a strong artwork-driven shell background when music is playing and the toggle is on
- Closed notch remains black even while music is playing
- Turning the toggle off immediately restores the normal black expanded background
- Menu remains readable on both bright and dark album artwork
- Chat remains readable on both bright and dark album artwork
- Track changes animate to the new background rather than flashing abruptly

Expected: strong atmospheric background in expanded state, unchanged compact notch, readable content, and dynamic toggle behavior.

- [ ] **Step 7: Commit the foreground token integration**

```bash
git add ClaudeIsland/UI/Views/NotchView.swift ClaudeIsland/UI/Views/NotchMenuView.swift
git commit -m "feat: adapt expanded notch foreground for artwork theme"
```
