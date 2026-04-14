# Music Source Badge Clickthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the music source badge below the artwork open the source app when clicked, matching the artwork click behavior.

**Architecture:** Keep the current `MusicManager.openSourceApp()` behavior as the single launch path and change only `MusicCardView` interaction wiring. The source badge remains visually identical and becomes a plain-styled button wrapping the existing badge content.

**Tech Stack:** Swift, SwiftUI, AppKit, `xcodebuild`

---

### Task 1: Make The Source Badge Clickable

**Files:**
- Modify: `ClaudeIsland/UI/Views/MusicCardView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Wrap the source badge content in the existing open-source action**

```swift
@ViewBuilder
var sourceBadge: some View {
    if let sourceApp = musicManager.sourceApp {
        Button(action: musicManager.openSourceApp) {
            HStack(spacing: 5) {
                if let icon = sourceApp.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Text(sourceApp.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to verify the interaction change compiles**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual interaction check**

Verify in the running app:

- Clicking the album artwork still opens the source app
- Clicking the source badge text opens the same source app
- Clicking the source badge icon opens the same source app
- The badge keeps its current visual style and layout

Expected: artwork and source badge both launch the same app without layout regressions.
