# Codex Hooks Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-pass Codex hooks integration that surfaces Codex sessions in ClaudeIsland's existing session list and processing UI without disturbing the current Claude path.

**Architecture:** Reuse the current `SessionStore -> SessionState -> ClaudeSessionMonitor -> SwiftUI` pipeline and add Codex as a second hook-backed provider. Introduce provider metadata, a Codex hook payload model plus adapter, and a conservative state mapping that only drives `.idle` and `.processing` from supported Codex events.

**Tech Stack:** Swift, SwiftUI, Combine, Foundation, existing Unix socket/hook infrastructure, Codex experimental hooks

---

## File Map

### Existing files to modify

- `ClaudeIsland/Models/SessionState.swift`
  - Add provider metadata to sessions.
- `ClaudeIsland/Services/Hooks/HookSocketServer.swift`
  - Add Codex hook payload modeling or shared hook abstractions if needed.
- `ClaudeIsland/Services/State/SessionStore.swift`
  - Accept provider-aware events and add Codex event handling.
- `ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift`
  - Start Codex hook monitoring alongside Claude monitoring.
- `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
  - Show provider identity in the session list.
- `ClaudeIsland/UI/Views/NotchView.swift`
  - Ensure mixed-provider sessions participate in existing processing UI without Claude-only assumptions.
- `ClaudeIsland/App/AppDelegate.swift`
  - Start any Codex-related hook setup if lifecycle entry is needed there.

### New files to create

- `ClaudeIsland/Services/Hooks/CodexHookModels.swift`
  - Codex hook payloads and normalization helpers.
- `ClaudeIsland/Services/Hooks/CodexHookAdapter.swift`
  - Maps Codex hook events to store-friendly events.
- `ClaudeIsland/Services/Hooks/CodexHookInstaller.swift`
  - Installs or updates Codex hook configuration in `~/.codex/config.toml`.
- `ClaudeIsland/Models/SessionProvider.swift`
  - Shared provider enum.

### Verification targets

- Build: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
- Config sanity: inspect generated `~/.codex/config.toml`
- Runtime sanity: verify Codex sessions appear in the combined list and Bash activity drives processing state

---

### Task 1: Add Provider Metadata To Sessions

**Files:**
- Create: `ClaudeIsland/Models/SessionProvider.swift`
- Modify: `ClaudeIsland/Models/SessionState.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add the provider enum**

```swift
import Foundation

enum SessionProvider: String, Equatable, Sendable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}
```

- [ ] **Step 2: Add provider to `SessionState`**

Add a stored property near the identity metadata and extend the initializer:

```swift
let provider: SessionProvider
```

```swift
nonisolated init(
    provider: SessionProvider = .claude,
    sessionId: String,
    cwd: String,
    ...
) {
    self.provider = provider
    self.sessionId = sessionId
    ...
}
```

- [ ] **Step 3: Run the build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: build succeeds with no new provider-related errors

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/Models/SessionProvider.swift ClaudeIsland/Models/SessionState.swift
git commit -m "feat: add session provider metadata"
```

### Task 2: Model Codex Hook Payloads And Normalize Runtime Signals

**Files:**
- Create: `ClaudeIsland/Services/Hooks/CodexHookModels.swift`
- Create: `ClaudeIsland/Services/Hooks/CodexHookAdapter.swift`
- Modify: `ClaudeIsland/Services/Hooks/HookSocketServer.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add Codex hook payload models**

Create a minimal payload model that supports only the events needed in V1:

```swift
import Foundation

struct CodexHookEnvelope: Codable, Sendable {
    let event: String
    let sessionId: String?
    let cwd: String?
    let toolName: String?
    let prompt: String?
    let rawPayload: [String: String]
}
```

Add convenience helpers:

```swift
var normalizedEventName: String { ... }
var isBashTool: Bool { ... }
```

- [ ] **Step 2: Add the adapter**

Create a translator with a narrow output surface:

```swift
enum CodexSessionEvent: Sendable {
    case sessionStart(sessionId: String, cwd: String)
    case userPromptSubmit(sessionId: String, cwd: String, prompt: String?)
    case preBashTool(sessionId: String, cwd: String, toolName: String)
    case postBashTool(sessionId: String, cwd: String, toolName: String)
    case stop(sessionId: String, cwd: String)
}
```

```swift
enum CodexHookAdapter {
    static func adapt(_ envelope: CodexHookEnvelope) -> CodexSessionEvent? { ... }
}
```

The adapter should:

- accept `SessionStart`
- accept `UserPromptSubmit`
- accept `PreToolUse` only when the tool is Bash
- accept `PostToolUse` only when the tool is Bash
- accept `Stop`
- return `nil` for unsupported events

- [ ] **Step 3: Thread Codex decoding through hook intake**

In `HookSocketServer.swift`, add a decoding path that can detect and decode Codex hook JSON separately from Claude hook JSON. Keep the Claude path unchanged.

Add a new callback type if needed:

```swift
typealias CodexHookEventHandler = @Sendable (CodexSessionEvent) -> Void
```

- [ ] **Step 4: Run the build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: build succeeds and both Claude and Codex hook models compile cleanly

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/Services/Hooks/CodexHookModels.swift ClaudeIsland/Services/Hooks/CodexHookAdapter.swift ClaudeIsland/Services/Hooks/HookSocketServer.swift
git commit -m "feat: add codex hook payload adapter"
```

### Task 3: Feed Codex Events Into `SessionStore`

**Files:**
- Modify: `ClaudeIsland/Services/State/SessionStore.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add provider-aware store events**

Extend the store event surface with Codex-specific cases:

```swift
case codexSessionStarted(sessionId: String, cwd: String)
case codexPromptSubmitted(sessionId: String, cwd: String, prompt: String?)
case codexBashStarted(sessionId: String, cwd: String, toolName: String)
case codexBashFinished(sessionId: String, cwd: String, toolName: String)
case codexStopped(sessionId: String, cwd: String)
```

- [ ] **Step 2: Add Codex state mutation helpers**

Implement narrow helpers such as:

```swift
private func processCodexSessionStart(sessionId: String, cwd: String) { ... }
private func processCodexPromptSubmitted(sessionId: String, cwd: String, prompt: String?) { ... }
private func processCodexBashStarted(sessionId: String, cwd: String, toolName: String) { ... }
private func processCodexBashFinished(sessionId: String, cwd: String, toolName: String) { ... }
private func processCodexStop(sessionId: String, cwd: String) { ... }
```

Behavior requirements:

- create missing sessions with `provider: .codex`
- map only to `.idle` and `.processing`
- use a synthetic tool id when needed, for example `"codex-bash-\(timestampMillis)"`
- update `lastActivity`
- preserve existing Claude code paths unchanged

- [ ] **Step 3: Reuse existing tool/chat item structures conservatively**

When Codex Bash starts, create a placeholder tool item using the existing `ToolCallItem` shape with:

```swift
name: toolName
status: .running
```

When Bash finishes, mark that item `.success` and return the session to `.idle`.

- [ ] **Step 4: Run the build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: build succeeds and `SessionStore` handles provider-aware Codex events

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/Services/State/SessionStore.swift
git commit -m "feat: map codex hook events into session store"
```

### Task 4: Start Codex Monitoring Alongside Claude Monitoring

**Files:**
- Modify: `ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift`
- Modify: `ClaudeIsland/App/AppDelegate.swift`
- Create: `ClaudeIsland/Services/Hooks/CodexHookInstaller.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add a Codex hook installer**

Create an installer responsible for enabling Codex hooks in `~/.codex/config.toml` and merging the app's hook command into config without overwriting unrelated user settings.

The implementation should:

- ensure `[features] codex_hooks = true`
- install only the V1 events:
  - `SessionStart`
  - `UserPromptSubmit`
  - `PreToolUse`
  - `PostToolUse`
  - `Stop`
- point them at the app's hook bridge command/script

- [ ] **Step 2: Start Codex installation on app launch**

In `AppDelegate.swift`, add:

```swift
CodexHookInstaller.installIfNeeded()
```

Place it near the existing hook installer so startup behavior stays understandable.

- [ ] **Step 3: Wire Codex hook callbacks into the monitor**

In `ClaudeSessionMonitor.startMonitoring()`, register the Codex hook callback and translate each adapted event into the new `SessionStore` events.

Use this shape:

```swift
Task {
    await SessionStore.shared.process(.codexSessionStarted(...))
}
```

Repeat for prompt submit, Bash start/finish, and stop.

- [ ] **Step 4: Run the build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: build succeeds and app startup compiles with both Claude and Codex monitoring paths

- [ ] **Step 5: Commit**

```bash
git add ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift ClaudeIsland/App/AppDelegate.swift ClaudeIsland/Services/Hooks/CodexHookInstaller.swift
git commit -m "feat: start codex hook monitoring"
```

### Task 5: Show Provider Identity In The Existing UI

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`
- Test: `xcodebuild -scheme ClaudeIsland -configuration Debug build`

- [ ] **Step 1: Add a provider badge to session rows**

In `ClaudeInstancesView.swift`, add a compact provider label using existing visual language:

```swift
Text(session.provider.displayName)
    .font(.system(size: 9, weight: .semibold))
    .foregroundColor(.white.opacity(0.55))
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(Color.white.opacity(0.06))
    .clipShape(Capsule())
```

- [ ] **Step 2: Ensure mixed-provider sessions drive existing top-level activity**

In `NotchView.swift`, audit any Claude-only assumptions in processing detection and ensure provider-neutral sessions can still participate in:

- list ordering
- pending/processing checks
- compact processing presentation

Do not introduce a separate Codex-specific compact animation in V1.

- [ ] **Step 3: Run the build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: build succeeds and the provider label compiles cleanly into the existing list UI

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift ClaudeIsland/UI/Views/NotchView.swift
git commit -m "feat: label codex sessions in ui"
```

### Task 6: Validate The End-To-End V1 Behavior

**Files:**
- Verify only; no planned code changes

- [ ] **Step 1: Verify build**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Verify Codex hook configuration**

Inspect: `~/.codex/config.toml`
Expected:

- `[features]`
- `codex_hooks = true`
- configured commands for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`

- [ ] **Step 3: Manual runtime verification**

Run a Codex session that triggers:

- session start
- prompt submit
- a Bash tool call
- stop

Expected:

- a Codex session appears in the existing list
- its row shows the provider label
- Bash activity drives `.processing`
- stop returns the session to `.idle`
- existing Claude sessions still behave exactly as before

- [ ] **Step 4: Commit final validation note if code changed during verification**

If verification exposed and fixed a bug:

```bash
git add <fixed-files>
git commit -m "fix: stabilize codex hooks integration"
```

If no code changed, skip commit.

---

## Self-Review

### Spec coverage

Covered spec requirements:

- provider metadata
- shared pipeline reuse
- conservative Codex event mapping
- mixed session list
- existing processing UI reuse
- no speculative file-based runtime inference

No intentional coverage gaps remain for V1.

### Placeholder scan

The plan avoids `TODO`/`TBD` placeholders and names all target files explicitly.

### Type consistency

Plan type names are internally consistent:

- `SessionProvider`
- `CodexHookEnvelope`
- `CodexSessionEvent`
- store-level `codex...` event cases

No later task depends on a differently named type introduced earlier.
