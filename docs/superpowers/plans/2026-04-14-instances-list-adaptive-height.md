# Instances List Adaptive Height Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the expanded instances list size itself to content when short, then cap at roughly `MusicCardView + 4.5 * InstanceRow` and scroll internally when longer.

**Architecture:** Keep the change local to `ClaudeInstancesView` by introducing lightweight view-local measurement for the music card, a representative row, and the list content. Compute the effective list height from those measurements and apply it only to the list container so empty state, chat, and menu behavior stay unchanged.

**Tech Stack:** SwiftUI, Swift, Xcode build verification

---

## File Map

- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Modify: `docs/superpowers/specs/2026-04-14-instances-list-adaptive-height-design.md` only if implementation reveals a spec mismatch
- Verify: `ClaudeIsland.xcodeproj` build for scheme `ClaudeIsland`

### Task 1: Add Focused Layout Helpers

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`

- [ ] **Step 1: Write the failing test target in code shape**

Add pure helper surface in `ClaudeInstancesView.swift` before using it from the view, so the behavior is explicit and reviewable:

```swift
private enum InstancesListLayout {
    static let targetVisibleRows: CGFloat = 4.5

    static func maxListHeight(
        musicCardHeight: CGFloat,
        rowHeight: CGFloat,
        showsMusicCard: Bool
    ) -> CGFloat {
        let visibleRowsHeight = rowHeight * targetVisibleRows
        return showsMusicCard ? musicCardHeight + visibleRowsHeight : visibleRowsHeight
    }

    static func appliedListHeight(
        contentHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        min(contentHeight, maxHeight)
    }
}
```

Expected initial state: no call sites use this helper yet, so the feature is still missing.

- [ ] **Step 2: Verify the feature still fails conceptually**

Inspect the current `body` and confirm the existing list still renders as:

```swift
private var instancesList: some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 2) {
            // rows
        }
        .padding(.vertical, 4)
    }
    .scrollBounceBehavior(.basedOnSize)
}
```

Expected: no `frame(height:)`, no measured height state, and no adaptive cap yet.

- [ ] **Step 3: Write minimal helper implementation**

Keep the helper pure and minimal. Do not add new models, environment keys, or global settings. Keep the exact API:

```swift
private enum InstancesListLayout {
    static let targetVisibleRows: CGFloat = 4.5

    static func maxListHeight(
        musicCardHeight: CGFloat,
        rowHeight: CGFloat,
        showsMusicCard: Bool
    ) -> CGFloat {
        let visibleRowsHeight = max(0, rowHeight) * targetVisibleRows
        let musicHeight = showsMusicCard ? max(0, musicCardHeight) : 0
        return musicHeight + visibleRowsHeight
    }

    static func appliedListHeight(
        contentHeight: CGFloat,
        maxHeight: CGFloat
    ) -> CGFloat {
        min(max(0, contentHeight), max(0, maxHeight))
    }
}
```

- [ ] **Step 4: Run a syntax-only verification pass**

Run:

```bash
swiftc -typecheck ClaudeIsland/UI/Views/ClaudeInstancesView.swift
```

Expected: this may fail because the file depends on app-wide types not visible in isolation. If it does, capture that and continue to full-project build verification later instead of inventing more changes.

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "refactor: add instances list layout helpers"
```

### Task 2: Measure Real Heights And Apply The Adaptive Cap

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`

- [ ] **Step 1: Write the failing UI integration shape**

Add the state needed for measurement before wiring the final layout:

```swift
@State private var musicCardHeight: CGFloat = 0
@State private var instanceRowHeight: CGFloat = 0
@State private var listContentHeight: CGFloat = 0
```

Add computed properties:

```swift
private var showsMusicCard: Bool { musicManager.isVisible }

private var maxInstancesListHeight: CGFloat {
    InstancesListLayout.maxListHeight(
        musicCardHeight: musicCardHeight,
        rowHeight: instanceRowHeight,
        showsMusicCard: showsMusicCard
    )
}

private var appliedInstancesListHeight: CGFloat? {
    guard instanceRowHeight > 0, listContentHeight > 0 else { return nil }
    return InstancesListLayout.appliedListHeight(
        contentHeight: listContentHeight,
        maxHeight: maxInstancesListHeight
    )
}
```

Expected initial state: after adding state only, the list still has no cap and the feature still fails.

- [ ] **Step 2: Verify the list still has no adaptive height yet**

Confirm `instancesList` is still missing the height application:

```swift
.frame(height: appliedInstancesListHeight)
```

Expected: absent before the implementation step.

- [ ] **Step 3: Write the minimal view implementation**

Update `ClaudeInstancesView` to:

1. Measure `MusicCardView` only when visible
2. Measure the first rendered `InstanceRow` as the representative row height
3. Measure the `LazyVStack` content height
4. Apply the capped height to the `ScrollView`

Use a small local geometry-preference helper in the same file, for example:

```swift
private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}
```

Apply it with these constraints:

```swift
if musicManager.isVisible {
    MusicCardView(musicManager: musicManager)
        .measureHeight { musicCardHeight = $0 }
}
```

```swift
LazyVStack(spacing: 2) {
    ForEach(Array(sortedInstances.enumerated()), id: \.element.stableId) { index, session in
        InstanceRow(/* existing closures */)
            .id(session.stableId)
            .measureHeight { height in
                if index == 0 {
                    instanceRowHeight = height
                }
            }
    }
}
.padding(.vertical, 4)
.measureHeight { listContentHeight = $0 }
```

```swift
ScrollView(.vertical, showsIndicators: false) {
    // content
}
.frame(height: appliedInstancesListHeight)
.scrollBounceBehavior(.basedOnSize)
```

Preserve current sorting, row behavior, and empty state logic. Do not touch `ChatView` or `NotchView`.

- [ ] **Step 4: Run focused build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: add adaptive height for instances list"
```

### Task 3: Validate Behavior And Clean Up

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` only if verification reveals issues

- [ ] **Step 1: Manually verify the short-list behavior**

Open the expanded notch instances page and check:

```text
Case A: no music card + 1-4 sessions
Expected: list height shrinks to content, panel no longer feels like a fixed-height list region
```

```text
Case B: music card visible + 1-4 sessions
Expected: panel height equals music card plus a small number of rows, with no unnecessary empty list area
```

- [ ] **Step 2: Manually verify the capped-scroll behavior**

Check:

```text
Case C: no music card + 5 or more sessions
Expected: list starts scrolling at about 4.5 visible rows
```

```text
Case D: music card visible + many sessions
Expected: list starts scrolling at about music card + 4.5 visible rows
```

- [ ] **Step 3: Fix any measured-height edge cases minimally**

Only if verification shows glitches, make one of these bounded fixes in `ClaudeInstancesView.swift`:

```swift
private var appliedInstancesListHeight: CGFloat? {
    guard instanceRowHeight > 0, listContentHeight > 0 else { return nil }

    let maxHeight = maxInstancesListHeight
    guard maxHeight > 0 else { return nil }

    return InstancesListLayout.appliedListHeight(
        contentHeight: listContentHeight,
        maxHeight: maxHeight
    )
}
```

Or reset stale measurements when music visibility changes:

```swift
.onChange(of: musicManager.isVisible) { _, isVisible in
    if !isVisible {
        musicCardHeight = 0
    }
}
```

Do not add broader refactors unless the verification proves they are necessary.

- [ ] **Step 4: Re-run build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "fix: polish instances list adaptive height behavior"
```

## Self-Review

- Spec coverage: the plan covers the capped threshold, real-height measurement, no-music fallback, and preserving empty/chat/menu behavior.
- Placeholder scan: no `TODO`, `TBD`, or deferred implementation markers remain.
- Type consistency: helper names use `InstancesListLayout`, `maxInstancesListHeight`, and `appliedInstancesListHeight` consistently across tasks.
