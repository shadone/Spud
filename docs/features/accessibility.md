# Accessibility

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Voting](voting.md), [Post detail and comments](post-detail-and-comments.md), [Media viewer and inline video](media-viewer.md), [Swipe actions](swipe-actions.md), [App chrome and materials](app-chrome-and-materials.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud honors the system accessibility settings. Text scales with the user's Dynamic Type size; VoiceOver reads the core reading, voting, and navigation surfaces with deliberate labels rather than raw glyphs; links inside post and comment text are each exposed to VoiceOver as their own focusable element; and animations are reduced or removed when Reduce Motion is on.

## Behavior and rules

- **Dynamic Type.** Body and label text uses system text styles and scales with the user's content-size setting; most text-bearing cells and headers update live as the setting changes. Custom and monospace fonts scale too, through a font-metrics helper, so non-text-style type tracks the same setting. There is no upper clamp — text grows all the way to the largest accessibility sizes.
- **VoiceOver on core surfaces.** The feed cell, post detail header and comments, the media viewer, profiles, communities, the Inbox, account and instance lists, and the composer toolbar set explicit VoiceOver labels and traits. Voting and saving speak full, consistent phrasing — for example a score reads as "42 points, upvoted" with the full number, not the abbreviated "1.2K" shown on screen — through a shared phrasing helper, so the spoken form is consistent everywhere those controls appear. The active vote control (upvote or downvote button) gains the `.selected` trait when you have voted in that direction, so VoiceOver announces the current vote state on focus. The post-list dog-ear fold (shown when vote buttons are hidden) is decorative and excluded from the accessibility tree.
- **Per-link accessibility in body text.** A label that renders tappable links (the `LinkLabel` used for post and comment attribution and for in-body markdown links) exposes each link range as its own accessibility element: the link text is its label, the destination URL is its value, it carries the link trait, and its frame matches the on-screen text of that link. VoiceOver users can focus and activate an individual link — for example the post creator's name in the "in <community> by <creator>" attribution — instead of the whole label being a single element.
- **Icon-only bar buttons are labeled.** Navigation-bar buttons that show only a glyph — the feed's sort, filter, new-post and feed-switcher buttons, the community sort button, Discover's and the Communities tab's sort buttons, the site-list and onboarding back buttons, the instance screen's share button, and the Share as Image alt-text sheet's compose control — each carry an explicit VoiceOver label naming the action, rather than being read as the raw symbol name. The composer's and New post's submit buttons also announce their in-flight state while a send is running.
- **Reduce Motion.** When Reduce Motion is enabled, animations are dropped or swapped for cross-fades rather than playing in full: the media viewer's zoom transition runs at zero duration, post-detail scroll-to-row jumps without animating, swipe-action animations are skipped, the voted-state fill cross-fades in rather than springing in (scale 0.9 → 1.0), and toasts and the offline-download progress pill appear and disappear without their slide-and-fade. The result is the same end state without the motion.
- **Contrast wins over tinting on the floating jump button.** The post-detail "Next new" floating button is not tinted with the accent color. On the Liquid Glass prominent material the label's color is derived from the button's own fill, so an accent-filled capsule renders washed-out light-on-light text — measured as low as 1.55:1 against the fill on some accents, well under the 4.5:1 the standard asks for normal-size text. It uses a high-contrast neutral fill instead, which measures ~16:1 for every one of the nine accents in both Light and Dark, and the state it signals is carried by the word "new" rather than by color alone.
- **Chrome over a fixed-dark backdrop stays legible in Light.** Two surfaces sit on a permanently dark stage whatever the app appearance — the media viewer and the Share as Image editor. Their translucent bars are pinned to a dark appearance so their text and glyphs keep contrast against that stage; in Light appearance the bar reads dark while the rest of the screen stays light.

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

### VoiceOver announces the active vote via the selected trait

- **Given** VoiceOver is on, and I have upvoted a post
- **When** I focus the upvote button
- **Then** VoiceOver reads it as selected (the `.selected` trait is set), indicating my current vote direction
- **And** focusing the downvote button reads as not selected

### VoiceOver names an icon-only navigation-bar button

- **Given** VoiceOver is on, in a feed
- **When** I focus the sort button in the navigation bar
- **Then** it is announced by what it does rather than by its symbol
- **And** the same holds for the filter, new-post, and feed-switcher buttons beside it

### Reduce Motion removes the media zoom animation

- **Given** Reduce Motion is enabled
- **When** I open an image in the media viewer
- **Then** it appears without the zoom transition animating
- **And** dismissing it likewise skips the motion

### Reduce Motion cross-fades the voted-state fill

- **Given** Reduce Motion is enabled
- **When** I upvote a post or comment
- **Then** the filled capsule appears via a cross-fade instead of a scale spring
- **And** removing the vote likewise cross-fades the fill away

## Not supported / out of scope

- **No custom handling for Bold Text, Increase Contrast, or Reduce Transparency.** These are left to the system defaults; Spud does not adjust its own styling for them. Two caveats on how far that has been checked: **Increase Contrast has not been verified per surface** — the argument that the stock glass and system colors adapt on their own is reasoning, not evidence, and the capture is still owed. **Reduce Transparency could not be toggled live** on the test environment; instead every translucent surface in the app was audited statically and all of them use the adaptive system material family (no fixed non-adaptive blur styles anywhere), which is what lets the system substitute an opaque treatment — but that substitution has not been observed running.
- **One animation still ignores Reduce Motion.** The offline-download progress pill's progress ring animates its fill unconditionally. The pill's own appearance and dismissal do honor the setting; only the ring inside it does not.
- **No VoiceOver focus announcements.** Spud does not post screen-changed, layout-changed, or announcement notifications, nor manage focus explicitly, beyond the per-element labels and the modal presentation behavior the system provides.
- **A few labels do not live-update on a Dynamic Type change.** Most text tracks the setting immediately, but a small number of labels take the size at creation and refresh only when their view is rebuilt.
- **Typography is not centralized.** Fonts are defined per scene rather than as shared design tokens, so Dynamic Type adoption is broad but per-scene rather than enforced in one place.
