# Expanded Notch Artwork-Adaptive Background Design

## Goal

Add an artwork-adaptive visual theme for the expanded notch only. When music is playing and the feature is enabled, the expanded notch background should pick up the album artwork's dominant colors to create a stronger atmosphere.

The closed notch must remain unchanged and stay black.

This feature must include a settings toggle so the user can enable or disable it dynamically.

## Scope

In scope:

- Apply artwork-driven background styling to the expanded notch shell
- Keep the closed notch black at all times
- Add a settings toggle to enable or disable the feature dynamically
- Adjust a small set of foreground colors only when needed for readability
- Reuse existing artwork-derived color data from the music subsystem

Out of scope:

- Re-theming the closed notch
- Full per-component recoloring of every subview
- Changes to the music metadata pipeline beyond reusing existing gradient data
- New artwork processing infrastructure unrelated to this expanded-notch theme

## Existing Context

The app already has the data needed for this feature:

- `MusicManager` exposes `artworkGradient`
- `NotchView` owns the expanded/closed notch shell background
- `NotchMenuView` already contains settings toggles backed by `AppSettings`

That means the feature can be implemented primarily in the notch shell and settings layer without changing the now playing adapter or the compact notch presentation.

## Approach

Use a shell-level adaptive theme:

1. Detect when the notch is in the expanded state
2. Detect when music is currently visible and the new setting is enabled
3. Replace the expanded-notch black shell background with a stronger artwork-based gradient treatment
4. Keep a subtle darkening layer to preserve readability
5. Expose a small set of foreground theme tokens so the most visible text and icon elements can adapt if needed

This gives the expanded notch a stronger visual identity without forcing a full rewrite of all inner views.

## Activation Rules

The adaptive background should be active only when all of the following are true:

- `viewModel.status == .opened`
- `musicManager.isVisible == true`
- `AppSettings.artworkAdaptiveBackgroundEnabled == true`

If any of those conditions are false, the notch shell should render exactly as it does today.

## Background Styling

The adaptive styling should be applied at the expanded-notch shell layer in `NotchView`, not only inside the music card.

Visual direction:

- Stronger than the current black shell
- Based on `musicManager.artworkGradient`
- Still grounded with a dark overlay so controls, menus, and chat remain readable
- Smoothly animated when the gradient changes with track changes

Recommended composition:

- base layer: artwork gradient
- support layer: optional radial or linear blend for more depth
- readability layer: a semi-transparent dark tint on top

The result should feel atmospheric, not neon or noisy.

## Foreground Adaptation

Use a minimal token set rather than recoloring every component independently.

Suggested tokens:

- `primaryText`
- `secondaryText`
- `separator`
- `headerIcon`

These should be derived from the perceived brightness of the artwork-driven background. The system should choose a lighter foreground set on dark gradients and a darker foreground set on very bright gradients.

This should be conservative. If an area is already readable with the default white-based foreground, no additional churn is needed.

## Affected UI Areas

The adaptive theme should influence:

- expanded-notch outer shell background
- expanded header icon/text affordances
- menu separators and menu text where readability would otherwise suffer

The compact notch should not be affected.

The music card can continue to use its own current presentation unless a small foreground adjustment is necessary for readability.

## Settings

Add a new persisted boolean setting in `AppSettings`:

- name: `artworkAdaptiveBackgroundEnabled`
- default: `true`

Add a matching toggle row in the notch settings menu.

Suggested menu label:

- `Artwork Adaptive Background`

Changing the toggle should take effect immediately without requiring an app restart.

## Data Flow

- `MusicManager` continues to own artwork-derived color extraction
- `AppSettings` owns the on/off switch
- `NotchView` decides whether the adaptive theme is active
- `NotchView` computes the shell background and foreground theme tokens
- child views consume those tokens directly or inherit them through environment-facing styling where practical

## Error Handling And Fallbacks

- No artwork or no music: render the normal black expanded-notch background
- Setting disabled: render the normal black expanded-notch background
- Unusually bright or low-contrast artwork: keep the dark overlay and switch to the safer foreground token set
- Track change while opened: animate to the new background rather than flashing

The fallback state should always be the current black theme.

## Testing

Manual verification is sufficient for the first pass:

- Expanded notch with music playing and toggle enabled
- Expanded notch with music playing and toggle disabled
- Closed notch while music is playing
- Menu page while adaptive background is active
- Chat page while adaptive background is active
- Track change while expanded
- Very bright album artwork
- Very dark album artwork

Success means:

- expanded-notch background clearly reflects the current artwork colors
- closed notch stays black
- the setting dynamically enables and disables the effect
- text and controls remain readable across menu, home, and chat content

## Risks

- Aggressive coloring may reduce readability in menu or chat surfaces if foreground adaptation is too weak
- Very long-lived open panels may reveal abrupt color changes if track transitions are not smoothed
- Because the effect is shell-level, over-styling could make the UI feel visually busy if overlays are too intense

## Success Criteria

- Expanded notch gains a stronger music-driven atmospheric background when enabled
- Closed notch remains black and visually unchanged
- The feature is dynamically controllable from settings
- Menu and chat stay readable while the expanded adaptive theme is active
