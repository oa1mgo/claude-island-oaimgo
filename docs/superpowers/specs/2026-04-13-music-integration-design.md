# ClaudeIsland Music Integration Design

## Goal

Bring the best parts of `ref/boring.notch`'s music experience into ClaudeIsland without weakening Claude session monitoring as the app's primary purpose.

The first version adds:
- a music card at the top of the expanded home panel
- a compact music activity presentation in the closed-notch state
- basic transport controls and progress display

The first version does not add:
- lyrics
- visualizers
- shuffle/repeat/favorite/volume controls
- controller preference settings
- the broader `boring.notch` coordinator and settings architecture

## Current Project Context

ClaudeIsland is structured around two clear layers:
- Claude session ingestion and state management through hooks, socket events, JSONL parsing, and `SessionStore`
- notch presentation and interaction through `NotchViewModel`, `ClaudeSessionMonitor`, and SwiftUI views

This separation is worth preserving. Music playback should not be folded into `SessionStore`, because it is not a Claude session concern and it follows a different lifecycle and data source.

## Requirements

### Functional

1. Show a music card in the expanded `instances` home view when media is available.
2. Hide the music card completely when nothing is currently playing or paused with meaningful metadata.
3. Show artwork, title, artist, playback state, elapsed time, and duration in the music card.
4. Provide `previous`, `play/pause`, and `next` controls.
5. Allow opening the source music app from the card artwork.
6. Show a compact music activity in the closed-notch state when music is active.
7. Preserve Claude activity priority:
   - permission approval overrides everything
   - Claude processing/compacting overrides music
   - music appears only when no higher-priority Claude activity is active

### Non-Functional

1. Keep the music system isolated from Claude hook/session code.
2. Reuse the project's existing UI style rather than importing `boring.notch`'s full visual system.
3. Make the first version extensible so additional controllers can be added later.
4. Avoid introducing a new settings system for music in this phase.

## Approaches Considered

### Approach A: Independent Music Subsystem

Create a dedicated music state layer with a playback model, a controller protocol, and a `MusicManager` observable object. The UI subscribes to this manager directly.

Pros:
- fits ClaudeIsland's existing separation of concerns
- easy to grow later with more controller backends
- keeps session architecture clean

Cons:
- requires a few new files instead of a quick patch

### Approach B: Minimal Direct Now Playing Service

Add a single small service that talks directly to the system now-playing source and expose a few properties to views.

Pros:
- fastest path to a demo

Cons:
- poorer boundaries
- awkward to extend later
- likely refactor cost once more sources or controls are needed

### Approach C: Fold Music Into `NotchViewModel`

Store playback state directly in the current notch UI model.

Pros:
- fewer files up front

Cons:
- mixes unrelated responsibilities
- makes the main notch model harder to reason about
- complicates testing and future extension

## Recommended Approach

Use Approach A: an independent music subsystem.

This gives ClaudeIsland a small, clean domain boundary for media playback while matching the app's existing architectural style: separate state source, narrow UI integration, minimal coupling to the rest of the app.

## Architecture

### New Domain Layer

Add a small music feature area composed of:
- `PlaybackState`: normalized playback data used by UI
- `MediaControllerProtocol`: common interface for reading state and issuing commands
- one initial controller implementation for system now-playing integration
- `MusicManager`: `ObservableObject` that owns the active controller and publishes playback state for SwiftUI

`MusicManager` is the only object views should observe directly.

### UI Integration

Integrate music at two points:

1. Expanded home panel
   - insert a `MusicCardView` at the top of `ClaudeInstancesView`
   - keep the session list below it unchanged

2. Closed-notch compact activity
   - extend `NotchView` closed-state header logic to support a music compact presentation
   - only render this when Claude-specific higher-priority activity is absent

### Activity Priority Model

Closed-notch activity priority becomes:

1. Claude permission approval
2. Claude processing or compacting
3. Music activity
4. Waiting-for-input ready state
5. Plain idle notch

This preserves ClaudeIsland's core mission while still making music feel alive in the notch.

## UI Design

### Expanded Music Card

The card should match the current black/glass-minimal ClaudeIsland aesthetic:
- dark surface
- compact spacing
- rounded corners aligned with existing row treatment
- monochrome secondary text with restrained accent color

Contents:
- artwork on the left
- title and artist stacked in the center
- small progress row with elapsed and duration
- transport buttons on the right or bottom-right

Behavior:
- hidden when no relevant playback data exists
- title truncates cleanly in compact widths
- artwork click opens the source app if bundle identifier is known
- play/pause reflects current playback state immediately

### Closed-Notch Music Activity

The compact music activity should feel like an optional live activity, not a mode switch.

Contents:
- small artwork thumbnail or music symbol on the left
- short title/artist summary in the center
- play-state indicator on the right

Behavior:
- appears only when music is active and Claude has no higher-priority compact activity
- should not expand the notch more aggressively than existing compact activity behavior
- should animate with the current closed-state activity transitions rather than introducing a separate animation system

## Data Flow

1. The music controller observes the system now-playing source.
2. The controller emits normalized `PlaybackState` values.
3. `MusicManager` receives those values and publishes simplified UI-facing state.
4. `ClaudeInstancesView` uses the manager to decide whether to show the expanded card.
5. `NotchView` uses the same manager plus existing Claude activity checks to decide whether the closed-notch music activity is visible.

Claude session events, JSONL parsing, and tmux behavior remain unchanged.

## Error Handling

1. If the music controller cannot read media state, the UI should simply hide music surfaces instead of showing an error.
2. If artwork is missing, fall back to a system music icon or app icon.
3. If a transport action fails, keep UI state consistent with the next observed playback update instead of forcing speculative state.
4. If the active source app cannot be opened, fail silently.

## Testing Strategy

The first implementation should validate these paths:
- no music state: home panel and closed notch remain unchanged
- playing music with metadata: music card and compact activity both appear when Claude is idle
- Claude processing: compact music activity is suppressed
- Claude waiting for approval: approval indicator suppresses music
- transport buttons call the manager/controller actions
- missing artwork falls back safely

Because this project currently has little or no automated test scaffolding, initial verification will likely be a mix of targeted logic coverage where feasible and manual verification in the running app. The implementation plan should identify the most isolated units that can realistically be tested first.

## File Boundaries

Expected new files:
- `ClaudeIsland/Models/PlaybackState.swift`
- `ClaudeIsland/Services/Music/MediaControllerProtocol.swift`
- `ClaudeIsland/Services/Music/MusicManager.swift`
- `ClaudeIsland/Services/Music/NowPlayingController.swift`
- `ClaudeIsland/UI/Views/MusicCardView.swift`
- `ClaudeIsland/UI/Components/CompactMusicActivityView.swift`

Expected modified files:
- `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`
- `ClaudeIsland/UI/Views/NotchView.swift`
- `ClaudeIsland.xcodeproj/project.pbxproj`

These boundaries keep the feature local and avoid leaking music concerns into Claude session management.

## Risks And Mitigations

### Risk: Private or fragile media APIs

Mitigation:
- start with the smallest controller implementation that fits the current app target
- isolate it behind `MediaControllerProtocol`

### Risk: Closed-notch UI crowding

Mitigation:
- honor the explicit activity priority model
- keep compact music presentation brief and lower-priority

### Risk: Bringing in too much `boring.notch` complexity

Mitigation:
- copy patterns, not the entire architecture
- defer settings, lyrics, visualizer, and advanced controls

## Success Criteria

The feature is successful when:
- music appears in the home panel as a polished card
- closed-notch music activity appears only when no higher-priority Claude activity is active
- Claude processing and approval states still win visually
- the code lands as an isolated music subsystem rather than an ad hoc patch
