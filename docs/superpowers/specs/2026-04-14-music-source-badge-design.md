# Music Source Badge Design

## Goal

Add a source badge to the expanded notch music card. The badge should appear below the album artwork and show the now playing app icon plus the app name.

This should work for any media source that exposes a valid `bundleIdentifier` through the existing now playing pipeline. QQ Music, Apple Music, and Microsoft Edge should be covered automatically by the general solution rather than by one-off UI branches.

## Scope

In scope:

- Show the playback source app below the album artwork in the expanded music card
- Resolve the source app name from the current playback `bundleIdentifier`
- Resolve the source app icon from the installed app bundle when possible
- Keep the existing title, artist, album, progress, and transport controls behavior unchanged
- Gracefully hide or degrade the source badge when metadata is missing

Out of scope:

- Compact notch music activity changes
- New media metadata collection beyond the existing `bundleIdentifier`
- Adding bundled image assets for specific apps
- Per-app custom branding beyond a small display-name override table if needed

## Existing Context

The project already carries the source app identity through the music stack:

- `NowPlayingController` builds `PlaybackState.bundleIdentifier`
- `MusicManager` already derives UI-facing state from `PlaybackState`
- `MusicCardView` renders the expanded music card

That means the feature can be implemented without changing the adapter protocol or the now playing transport commands.

## Approach

Use a mixed resolution strategy:

1. Default to dynamic app lookup from `bundleIdentifier`
2. Optionally apply a small override table for display names where the installed bundle name is awkward
3. Hide the source badge when no trustworthy source can be derived

This keeps the feature generic for all supported apps while allowing polish for common cases.

## Data Model Changes

Add a lightweight source presentation model in the music UI layer, derived from `PlaybackState.bundleIdentifier`.

Proposed fields:

- `bundleIdentifier: String`
- `displayName: String`
- `icon: NSImage?`

This model should be computed in `MusicManager`, not in the view, so the lookup and fallback logic stay centralized and testable.

## Source Resolution

Given a `bundleIdentifier`, resolve source metadata in this order:

1. Ask `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` for the installed app URL
2. If found, read the bundle display name using `Bundle(url:)`
3. If found, read the app icon using `NSWorkspace.shared.icon(forFile:)`
4. If name resolution fails, fall back to:
   - `CFBundleDisplayName`
   - `CFBundleName`
   - last bundle identifier component
5. If app URL lookup fails entirely, still expose a text-only source using the best fallback name

If the bundle identifier is empty or missing, no source badge should be shown.

## UI Changes

Update the left side of the expanded `MusicCardView`:

- Replace the single artwork block with a vertical stack
- Keep the artwork at the current visual size
- Add a compact source badge directly underneath

Badge layout:

- 12-14pt app icon on the left
- app name on the right
- single line, truncated if necessary
- subtle rounded background matching the current card style
- lower visual emphasis than the song title

If the source icon is unavailable, render the badge with text only. If the source name is unavailable, do not render the badge.

## Behavior

- Clicking the album artwork should keep opening the source app, as it does today
- The new source badge itself does not need its own tap target in the first version
- Source display should update whenever `playbackState.bundleIdentifier` changes
- Browser-based playback sources such as Edge should display the browser app as the source because that is the app emitting now playing metadata

## Error Handling

- Missing bundle identifier: no badge
- Bundle identifier found but app URL lookup fails: show text fallback if possible
- Icon lookup fails: show text-only badge
- Name lookup fails: derive a readable fallback from the bundle identifier

The card must remain stable and should never collapse or misalign because source metadata is absent.

## Testing

Manual verification is sufficient for the first pass:

- Apple Music playing local or streaming media
- QQ Music playing media
- Edge playing media from a web player
- Unknown or missing source metadata case
- Pause/resume and track changes without layout jitter

Code-level verification should include at least focused tests for source-name fallback formatting if the existing test setup makes that practical. If the project has no lightweight unit-test path for this layer, keep the logic small and verify manually.

## Implementation Notes

- Prefer putting source lookup logic in `MusicManager` or a tiny helper owned by the music feature
- Avoid doing expensive app lookup work repeatedly inside SwiftUI view recomputation
- Cache or reuse resolved source metadata keyed by bundle identifier if repeated lookups become noticeable
- Keep the badge styling aligned with the current black/glass visual language of the notch

## Risks

- Some apps may expose unexpected bundle identifiers or transient parent-app identifiers
- Browser playback will identify the browser, not the website, which is acceptable for this feature
- Bundle display names may vary by localization; this is acceptable because it reflects the installed app

## Success Criteria

- Expanded music card shows a source badge below artwork when playback source is known
- The badge uses the installed app icon when available
- The feature works generically across media apps and browsers, including QQ Music, Apple Music, and Edge
- The layout remains visually stable when source data is unavailable
