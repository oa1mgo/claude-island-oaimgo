# Codex Hooks Integration Design

Date: 2026-04-14
Branch: `codex/codex-hooks-integration`

## Goal

Integrate Codex sessions into ClaudeIsland so active Codex work can appear in the same top-notch UI and session list as Claude sessions.

The first version should be intentionally conservative:

- Reuse the existing session UI and state pipeline
- Support Codex as a second provider
- Depend only on Codex hooks that are currently practical to consume
- Avoid overpromising fine-grained state that Codex hooks cannot reliably provide today

## Non-Goals

The first version will not implement:

- Codex permission approval flows
- tmux approval round-tripping for Codex
- Complete non-Bash tool tracking
- MCP/Web/Search/Write tool state tracking
- Full subagent tree visualization for Codex
- A separate Codex-only page or mode in the UI

## Product Shape

Codex sessions will appear in the existing session list beside Claude sessions.

Each session will carry a provider label:

- `claude`
- `codex`

The notch will continue to use the existing compact/opened layouts. Codex sessions will participate in the same top-level activity model, but only with a weaker state vocabulary than Claude.

## Architecture

### Reuse Existing Pipeline

The current Claude flow is:

`hook/socket input -> SessionStore -> SessionState/SessionPhase -> ClaudeSessionMonitor -> SwiftUI`

Codex should join this pipeline rather than creating a parallel UI state tree.

### Provider-Aware Sessions

`SessionState` gains a provider field. This allows the same store and views to render mixed session sources while preserving a single source of truth.

Suggested enum:

```swift
enum SessionProvider: String, Equatable, Sendable {
    case claude
    case codex
}
```

### Codex Adapter Layer

A thin Codex adapter will translate Codex hooks events into store-friendly events.

This adapter exists to:

- normalize Codex hook payloads
- keep Codex-specific parsing separate from Claude hooks
- avoid polluting existing Claude hook handling with provider-specific conditions

## State Model

### Supported Codex States in V1

Codex hooks can practically support these UI states in V1:

- session started
- user submitted a prompt
- Bash tool execution started
- Bash tool execution finished
- session/turn stopped

These map to a minimal session phase subset:

- `.idle`
- `.processing`

`waitingForInput` may be inferred later, but should not be introduced in V1 because the available hooks do not yet guarantee a stable mapping.

### Unsupported Codex States in V1

These should not be inferred in the first release:

- waiting for approval
- compacting
- detailed multi-tool runtime state beyond Bash
- active subagent tree
- fine-grained terminal/tool permission state

## Event Mapping

### SessionStart

On Codex `SessionStart`:

- create a new session if missing
- set `provider = .codex`
- record `sessionId`, `cwd`, `createdAt`, `lastActivity`
- initialize `phase = .idle`

### UserPromptSubmit

On Codex `UserPromptSubmit`:

- update `lastActivity`
- update lightweight conversation summary fields when payload permits
- keep phase unchanged unless a later tool event moves the session into processing

This event is primarily used to mark recency and surface Codex sessions in the list.

### PreToolUse

For V1, only `Bash` should influence runtime state.

On Codex `PreToolUse` for `Bash`:

- mark session `phase = .processing`
- create a placeholder tool item
- track that the active runtime work belongs to Codex/Bash

Non-Bash tool events may be recorded later, but should not drive the notch state in V1.

### PostToolUse

On Codex `PostToolUse` for `Bash`:

- complete the placeholder Bash tool item
- clear any in-progress Bash runtime marker
- if nothing else is active, return session to `.idle`

### Stop

On Codex `Stop`:

- mark the session as no longer processing
- clear dangling in-progress Bash markers
- set `phase = .idle`

This acts as the turn/session cleanup signal for V1.

## UI Behavior

### Session List

Codex sessions appear in the existing combined list.

They should be visually distinguishable with a provider indicator, but not visually split into a separate page.

Recommended V1 treatment:

- provider badge or label near the title/subtitle
- reuse existing row layout and activity affordances

### Compact Notch

Codex sessions may trigger the existing processing presentation when a Codex Bash tool is active.

V1 should not introduce a separate Codex-specific compact animation language. The current processing indication is sufficient until Codex state coverage improves.

### Opened Notch

Opened UI should continue to show the mixed session list.

Codex rows should behave like Claude rows where possible, with the understanding that Codex V1 state will be coarser.

## Data Source Strategy

V1 should prefer Codex hooks as the primary runtime signal.

Local Codex files such as:

- `~/.codex/session_index.jsonl`
- `~/.codex/sessions/**/*.jsonl`
- `~/.codex/state_*.sqlite`

are useful as supporting references, but should not be treated as the main runtime state source for this feature.

Reason:

- they are better suited to history/index reconstruction
- they do not cleanly express live runtime state with the same confidence as hooks

## Implementation Boundaries

Expected work areas:

- add provider metadata to the session model
- add Codex hook payload modeling and adapter logic
- feed Codex events into `SessionStore`
- update session list UI to show provider identity
- keep Claude behavior unchanged

Avoid in V1:

- refactoring the entire store into a provider abstraction hierarchy
- merging Claude and Codex payload models prematurely
- introducing speculative state inference from Codex history files

## Risks

### Experimental Hook Surface

Codex hooks are still under development, so payload shape or behavior may change.

Mitigation:

- keep Codex parsing isolated
- degrade gracefully to missing state rather than incorrect state

### Over-Inference

Codex does not currently expose the same complete runtime lifecycle as Claude Code.

Mitigation:

- only map states that are directly supported by hooks
- leave unsupported states absent instead of guessed

### UI Semantics Drift

A Claude-first phase model can imply more precision than Codex actually has.

Mitigation:

- use only `.idle` and `.processing` for Codex in V1
- attach provider labeling so users understand mixed backends are present

## Success Criteria

V1 is successful if:

- Codex sessions appear in the existing session list
- Codex sessions are distinguishable from Claude sessions
- Codex `SessionStart` creates visible sessions
- Codex Bash execution drives the existing processing UI
- Codex `Stop` reliably clears processing state
- Claude behavior remains unchanged
