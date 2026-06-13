# Accessibility

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Voting](voting.md), [Post detail and comments](post-detail-and-comments.md), [Media viewer and inline video](media-viewer.md), [Swipe actions](swipe-actions.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud honors the system accessibility settings. Text scales with the user's Dynamic Type size; VoiceOver reads the core reading, voting, and navigation surfaces with deliberate labels rather than raw glyphs; links inside post and comment text are each exposed to VoiceOver as their own focusable element; and animations are reduced or removed when Reduce Motion is on.

## Behavior and rules

- **Dynamic Type.** Body and label text uses system text styles and scales with the user's content-size setting; most text-bearing cells and headers update live as the setting changes. Custom and monospace fonts scale too, through a font-metrics helper, so non-text-style type tracks the same setting. There is no upper clamp — text grows all the way to the largest accessibility sizes.
- **VoiceOver on core surfaces.** The feed cell, post detail header and comments, the media viewer, profiles, communities, the Inbox, account and instance lists, and the composer toolbar set explicit VoiceOver labels and traits. Voting and saving speak full, consistent phrasing — for example a score reads as "42 points, upvoted" with the full number, not the abbreviated "1.2K" shown on screen — through a shared phrasing helper, so the spoken form is consistent everywhere those controls appear.
- **Per-link accessibility in body text.** A label that renders tappable links (the `LinkLabel` used for post and comment attribution and for in-body markdown links) exposes each link range as its own accessibility element: the link text is its label, the destination URL is its value, it carries the link trait, and its frame matches the on-screen text of that link. VoiceOver users can focus and activate an individual link — for example the post creator's name in the "in <community> by <creator>" attribution — instead of the whole label being a single element.
- **Reduce Motion.** When Reduce Motion is enabled, animations are dropped rather than swapped: the media viewer's zoom transition runs at zero duration, post-detail scroll-to-row jumps without animating, and swipe-action animations are skipped. The result is the same end state without the motion.

## Scenarios

### Text scales with Dynamic Type

- **Given** I have increased the system text size
- **When** I open a feed, a post, or the Inbox
- **Then** the text is shown at the larger size
- **And** it grows further at the largest accessibility sizes, with no clamp

### VoiceOver reads a post's controls clearly

- **Given** VoiceOver is on
- **When** I focus a post's score and vote controls
- **Then** the score is read with its full number and current vote state (for example "42 points, upvoted")
- **And** the upvote, downvote, and save buttons announce their action

### VoiceOver focuses an individual link in body text

- **Given** VoiceOver is on, on a post detail with attribution text "in <community> by <creator>"
- **When** I swipe through the attribution label
- **Then** the creator link is its own focusable element with the creator's name as its label and the link trait
- **And** activating it opens that link

### Reduce Motion removes the media zoom animation

- **Given** Reduce Motion is enabled
- **When** I open an image in the media viewer
- **Then** it appears without the zoom transition animating
- **And** dismissing it likewise skips the motion

## Not supported / out of scope

- **No custom handling for Bold Text, Increase Contrast, or Reduce Transparency.** These are left to the system defaults; Spud does not adjust its own styling for them.
- **No VoiceOver focus announcements.** Spud does not post screen-changed, layout-changed, or announcement notifications, nor manage focus explicitly, beyond the per-element labels and the modal presentation behavior the system provides.
- **A few labels do not live-update on a Dynamic Type change.** Most text tracks the setting immediately, but a small number of labels take the size at creation and refresh only when their view is rebuilt.
- **Typography is not centralized.** Fonts are defined per scene rather than as shared design tokens, so Dynamic Type adoption is broad but per-scene rather than enforced in one place.
