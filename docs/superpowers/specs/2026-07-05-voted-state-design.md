# Voted-state visual treatment — design spec

**Source:** Claude Design project "Spud" → `Spud Voted State - Final.html`
(project `83e2a7e8-035e-4330-84ed-edf951e9d29c`).
**Status:** Approved by user (2026-07-05), ready for implementation.

## Problem

Today a vote is signalled only by a **hue change**: the vote arrow and the score
tint to the accent (up) or periwinkle (down). Scanning a fast feed you can't tell
which posts you've already voted on, and the same weak signal repeats in the
post-detail header and on every comment. Voted state must read as a **whole-item,
structural** state — legible at a glance and in monochrome (color-blind-safe),
with up clearly distinct from down.

## The idea: one language, two modes

Voted state is carried by **one object per layout mode — never both at once**:

1. **Vote pill (primary).** When the trailing vote arrows are shown (the default,
   `PreferencesService.showVoteButtons == true`), the chosen arrow becomes a
   **solid filled capsule** — the accent/periwinkle token as the fill, a **white
   glyph** on top — while the other arrow stays a hairline/tertiary outline. This
   is a real weight change (fill vs outline), not a hue swap, so it survives a
   glance and monochrome. The signal lives **inside the control**, so it never
   collides with depth rails, the fresh-comment wash, distinguished/OP, or saved.

2. **Dog-ear fold (arrows-hidden mode).** When the user turns vote buttons off
   (gesture voting), there is no control to restyle, so a **folded corner** in the
   trailing edge carries the state instead: **up folds from the top corner, down
   from the bottom corner**, each with a small debossed arrow. Orientation encodes
   direction before color does. No background wash, so it never touches the rails
   or the teal fresh/distinguished states.

The **same setting** (`showVoteButtons`) picks which cue is shown, so a row never
stacks the pill and the fold together.

## Per surface

- **Post list cell** — adapts to the setting: pill when arrows shown, fold when
  hidden. (The subtitle score keeps its existing vote-colored arrow as incidental
  reinforcement; only the trailing control/corner changes.)
- **Post-detail header** — pill only. The header's upvote/downvote button goes
  **solid** (filled capsule, white glyph) when active. No fold, no wash.
- **Comments** — pill only. Each comment's inline **score becomes a filled
  mini-pill** (white arrow + white number on the token) when voted; neutral stays
  the current tertiary arrow+number. Coexists cleanly with the fresh-comment teal
  wash, distinguished/OP, saved bookmark, "NEW" pill, and the colored depth rails.

## Colors — reuse the existing tokens (adaptation)

The mock uses up = teal `#009687`, down = indigo `#5b57e0`. **The app already
implements the up side of this system**; we reuse its accent token there and
**adopt the mock's indigo for down**, changing the single existing downvote token:

- **Up** = `GeneralAppearance.upvoteButtonActiveColor` → `ThemeManager.currentAccentColor`
  (the user's accent; default Lemmy teal ≈ `#009687`). Accent-aware by design; unchanged.
- **Down** = `GeneralAppearance.downvoteButtonActiveColor` → `GeneralAppearance.downColor`,
  **changed from periwinkle `#7c8df0` to the mock's indigo `#5b57e0`** (RGB ≈ 0.357,
  0.341, 0.878). This is the single source for every downvote surface, so the deeper
  indigo propagates app-wide (score arrows, swipe actions, header/comment/list) — a
  deliberate, user-approved change, not just the new capsule.
- **Filled-capsule glyph/number** = white (`.white`), sized for contrast on both tokens.
- **Neutral / inactive** = `.tertiaryLabel` (unchanged).

## Behavior spec

- **Motion (commit).** The fill springs in, scale `0.9 → 1.0` (~180 ms), and the
  opposite arrow dims to its hairline. A light haptic fires (the app already fires
  the vote haptic on enqueue — do not add a second one; the animation piggybacks).
- **Motion (undo).** The fill scales out; the glyph returns to tertiary.
- **Reduce Motion.** Cross-fade the fill instead of scaling; no peel/spring. Gate
  on `UIAccessibility.isReduceMotionEnabled`.
- **Accessibility.** Fill weight + arrow shape carry the state; hue is
  reinforcement only. The active control gains the `.selected` trait; VoiceOver
  labels/score phrasing keep using `VoteAccessibility`. Each arrow keeps a ≥44 pt
  hit area; the fold is decorative (`isAccessibilityElement = false`), not a target.
- **Dynamic Type.** The capsule tracks the glyph/label metrics and grows with text
  size; the fold is fixed geometry.
- **Compact / performance.** Modes never stack. Pure layer work (background fill +
  a `CAShapeLayer`/clip corner for the fold) — no per-cell canvas or shadow work in
  the scroll path.

## Out of scope

- No change to the vote **mechanics** (optimistic outbox, swipe/context-menu
  voting, sign-in gate) — this is presentation only.
- No new user setting; the treatment is driven entirely by the existing
  `showVoteButtons` preference.
- The downvote token IS changed (periwinkle → indigo `#5b57e0`) app-wide — the one
  intentional color change, made at the single `GeneralAppearance.downColor` source.
