# Instances Empty State Compact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `instances` page visibly shorter when there are no sessions, while preserving the current empty-state copy and leaving populated-list behavior unchanged.

**Architecture:** Split the change across two focused layers. `NotchViewModel` will provide a dynamic opened height for the `instances` page based on whether sessions exist and whether the music card is visible. `ClaudeInstancesView` will keep the empty-state copy but render it as a compact centered block instead of an infinite-height filler.

**Tech Stack:** SwiftUI, Swift, Xcode build verification

---

## File Map

- Modify: `ClaudeIsland/Core/NotchViewModel.swift`
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Verify: `ClaudeIsland.xcodeproj` build for scheme `ClaudeIsland`

### Task 1: Add Dynamic `instances` Opened Height

**Files:**
- Modify: `ClaudeIsland/Core/NotchViewModel.swift`

- [ ] **Step 1: Write the failing layout target in code shape**

Capture the current behavior:

```swift
case .instances:
    return CGSize(
        width: min(screenRect.width * 0.4, 480),
        height: 320
    )
```

Expected: `instances` always opens at `320`, regardless of whether the page is empty.

- [ ] **Step 2: Verify there is no current empty-state-aware height path**

Confirm there is no helper or published state describing whether the instances page is empty or whether music should contribute to `openedSize`.

Expected: absent before implementation.

- [ ] **Step 3: Write the minimal implementation**

Add a small, explicit height model in `NotchViewModel` for the `instances` page only.

Target shape:

```swift
@Published var instancesPageHasSessions: Bool = false
@Published var instancesPageShowsMusic: Bool = false
```

```swift
private enum InstancesPageLayout {
    static let defaultHeight: CGFloat = 320
    static let emptyStateHeight: CGFloat = 172
    static let emptyStateWithMusicHeight: CGFloat = 304
}
```

Update `openedSize`:

```swift
case .instances:
    let height: CGFloat
    if instancesPageHasSessions {
        height = InstancesPageLayout.defaultHeight
    } else if instancesPageShowsMusic {
        height = InstancesPageLayout.emptyStateWithMusicHeight
    } else {
        height = InstancesPageLayout.emptyStateHeight
    }

    return CGSize(
        width: min(screenRect.width * 0.4, 480),
        height: height
    )
```

Keep this scoped to `instances`. Do not change `chat` or `menu`.

- [ ] **Step 4: Run build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/Core/NotchViewModel.swift
git commit -m "feat: add dynamic instances page height"
```

### Task 2: Feed Empty-State Inputs Into `NotchViewModel`

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`

- [ ] **Step 1: Write the failing integration target in code shape**

Confirm `ClaudeInstancesView` currently does not synchronize empty-state facts back to `viewModel`.

Expected: no `.onAppear`, `.onChange`, or direct assignment to `viewModel.instancesPageHasSessions` / `viewModel.instancesPageShowsMusic`.

- [ ] **Step 2: Verify no current binding exists**

Search for these properties in the file before implementation:

```swift
viewModel.instancesPageHasSessions
viewModel.instancesPageShowsMusic
```

Expected: absent before implementation.

- [ ] **Step 3: Write the minimal implementation**

Add a small sync helper in `ClaudeInstancesView`:

```swift
private func syncInstancesLayoutState() {
    viewModel.instancesPageHasSessions = !sessionMonitor.instances.isEmpty
    viewModel.instancesPageShowsMusic = showsMusicCard
}
```

Call it from:

```swift
.onAppear {
    syncInstancesLayoutState()
}
.onChange(of: sessionMonitor.instances.isEmpty) { _, _ in
    syncInstancesLayoutState()
}
.onChange(of: musicManager.isVisible) { _, _ in
    syncInstancesLayoutState()
}
```

Do not disturb the existing measured list-height logic for populated lists.

- [ ] **Step 4: Run build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: sync instances layout state to notch view model"
```

### Task 3: Make The Empty State Itself Compact

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`

- [ ] **Step 1: Write the failing empty-state target in code shape**

Capture the current empty state:

```swift
private var emptyState: some View {
    VStack(spacing: 8) {
        Text("No sessions")
        Text("Run claude in terminal")
        Text("or start a codex session")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

Expected: content still stretches vertically.

- [ ] **Step 2: Verify the compact container is not yet present**

Confirm no bounded empty-state height constant is present in `ClaudeInstancesView.swift`.

Expected: absent before implementation.

- [ ] **Step 3: Write the minimal implementation**

Extend the existing local layout enum:

```swift
static let emptyStateContentHeight: CGFloat = 136
```

Replace the empty state with a centered bounded block while preserving the copy:

```swift
private var emptyState: some View {
    VStack(spacing: 0) {
        Spacer(minLength: 0)

        VStack(spacing: 10) {
            Text("No sessions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.48))

            Text("Run claude in terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.28))

            Text("or start a codex session")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.20))
        }
        .frame(
            maxWidth: .infinity,
            minHeight: InstancesListLayout.emptyStateContentHeight,
            maxHeight: InstancesListLayout.emptyStateContentHeight
        )

        Spacer(minLength: 0)
    }
}
```

Do not add buttons, icons, or new copy.

- [ ] **Step 4: Run build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: compact instances empty state content"
```

### Task 4: Validate The Final Behavior

**Files:**
- Modify: `ClaudeIsland/Core/NotchViewModel.swift` or `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` only if verification finds mismatch

- [ ] **Step 1: Manually verify empty-state height without music**

Check:

```text
Case A: no music + no sessions
Expected: the entire instances panel is visibly shorter than before, and the empty copy is compact
```

- [ ] **Step 2: Manually verify empty-state height with music**

Check:

```text
Case B: music visible + no sessions
Expected: panel height reads as music card + compact empty state, with no large dead zone
```

- [ ] **Step 3: Manually verify populated-list behavior**

Check:

```text
Case C: sessions present
Expected: the page returns to the normal instances height and preserves the existing adaptive/scrolling list behavior
```

- [ ] **Step 4: Make only minimal numeric tuning if needed**

If the visual balance is off, tune only these bounded constants:

```swift
InstancesPageLayout.emptyStateHeight
InstancesPageLayout.emptyStateWithMusicHeight
InstancesListLayout.emptyStateContentHeight
```

Do not expand scope beyond these files.

- [ ] **Step 5: Re-run build verification**

Run:

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build
```

Expected: `BUILD SUCCEEDED`

## Self-Review

- Spec coverage: the plan now changes both the outer `instances` panel height and the inner empty-state content so the page truly becomes shorter.
- Placeholder scan: no `TODO`, `TBD`, or deferred steps remain.
- Type consistency: `instancesPageHasSessions`, `instancesPageShowsMusic`, `InstancesPageLayout`, and `InstancesListLayout.emptyStateContentHeight` are used consistently.
