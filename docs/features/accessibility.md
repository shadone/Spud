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
- **Reduce Motion keeps progress information, drops the sweep.** The offline-download pill's progress ring is the one case where the motion *is* the data. With Reduce Motion on, the ring still redraws at each new percentage — it simply snaps to the new arc length instead of sweeping there over a quarter of a second. Nothing about how much is done is lost; only the travel between values is.
- **Contrast wins over tinting on the floating jump button.** The post-detail "Next new" floating button is not tinted with the accent color. On the Liquid Glass prominent material the label's color is derived from the button's own fill, so an accent-filled capsule renders washed-out light-on-light text — measured as low as 1.55:1 against the fill on some accents, well under the 4.5:1 the standard asks for normal-size text. It uses a high-contrast neutral fill instead, which measures ~16:1 for every one of the nine accents in both Light and Dark, and the state it signals is carried by the word "new" rather than by color alone.
- **Chrome over a fixed-dark backdrop stays legible in Light.** Two surfaces sit on a permanently dark stage whatever the app appearance — the media viewer and the Share as Image editor. Their translucent bars are pinned to a dark appearance so their text and glyphs keep contrast against that stage; in Light appearance the bar reads dark while the rest of the screen stays light.
- **A glyph on a filled accent surface is never the accent itself.** Anywhere the accent is used as a solid fill — the filled vote capsule, the comment score pill, the collapsed "N new" badge, and the swipe-action tracks — the glyph on top is white and stays white whatever accent is chosen. The swipe tracks were the exception until it was measured: their arrows had no colour of their own, so they inherited the accent and were drawn in exactly the fill colour behind them, which meant the Upvote arrow did not appear at all on any of the nine accents in either appearance.
- **The accent has two values: one for surfaces, one for text.** The nine accent swatches are tuned to look right as a *fill*, and several of them are far too light to be read as *text* on the app's Light backgrounds — Orange, Green and Teal measured around 2.2:1 and even the default Lemmy teal only reached 3.7:1, against the 4.5:1 the standard asks for normal-size text. So the accent now resolves to two values. Wherever it fills a surface — the vote capsule, the swipe-action tracks, a prominent button, a Subscribe pill, a Toggle, a chat bubble, the low-alpha washes behind badges — it is unchanged, still the vivid swatch. Wherever it is drawn *as* content — accent-coloured labels, badge and chip text, links and mentions in post and comment bodies, meaningful glyphs — it uses a darkened variant in Light and, where needed, a lightened one in Dark. The correction is computed from the swatch rather than hand-picked, along an axis that leaves the hue untouched, so the picker's swatch still predicts what the app looks like: Orange text reads as a deep orange, not as a different colour. Every one of the nine accents clears 4.5:1 in both appearances, including where the text sits on a wash of its own accent.
- **Known shortfall: white on the three brightest accent fills.** Orange, Green and Teal are light enough that white text and glyphs *on those accent fills* land around 1.9:1 to 2.3:1 rather than the 3:1 the standard asks. This is a property of the palette, and it is a fill problem, not a text one — darkening the fill was tried and rejected because it turns the Orange swatch brown and the Green one olive, which is a worse outcome for a colour the user picked by eye. The affordances themselves never depend on that contrast alone: the vote state is also carried structurally (a filled capsule, a dog-ear fold, a pill), and the swipe tracks are identified by position and motion.
- **Known shortfall: accent-tinted system controls.** Some controls take the accent by inheriting the window tint rather than naming a colour — navigation-bar buttons, plain and bordered buttons that set no foreground of their own, Toggles, alert buttons, the search bar's Cancel. Those still draw in the vivid accent, so their labels have the same Light-mode shortfall the accent-coloured *text* above no longer has. They are not corrected because the only lever is the window tint itself, and that same tint is what fills the Toggles, the prominent buttons and the chat bubbles — moving it would darken every one of those fills, which is the trade rejected above.
- **The "Low-res preview" pill reads the same in Light and Dark.** The small translucent pill shown over an image when only the cached thumbnail could be loaded — tappable to retry on a post's header, informational in the media viewer — draws white text and glyphs, so it too is pinned to a dark appearance rather than following the app's. Measured over backdrops from a bright photo to a near-black one it stays between 6.9:1 and 14.5:1 for its label, and 6.4:1 to 13:1 for its glyphs, identically in both appearances. Over a very dark photo the pill's outline itself fades into the picture (about 1.7:1) and only the text is visible — accepted, because the text is at its *most* legible exactly there, and because outlining the pill strongly enough to show against near-black would put a visible stroke around it over every other photo too.

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

### The low-res preview pill stays legible whatever the appearance

- **Given** the app appearance is Light, on a post whose full-size image could not be loaded
- **When** the header shows the "Low-res preview · tap to retry" pill over the cached thumbnail
- **Then** the pill reads as dark translucent glass with white text, exactly as it does in Dark appearance
- **And** the same holds for the media viewer's "Showing low-resolution preview" pill

### Accent-coloured text stays readable on every accent

- **Given** Settings → Appearance with the accent set to Orange, Green or Teal, in Light appearance
- **When** I look at an accent-coloured label — a link in a post body, an "OP" badge, the "N new since your last visit" banner, a Discover chip, the "RECOMMENDED" pill
- **Then** the text is drawn in a darker shade of that same accent and is comfortably readable
- **And** the accent swatch in the picker, the vote capsule, the swipe-action tracks and every filled button are unchanged — still the vivid colour I picked

### Accent-coloured text stays readable in Dark too

- **Given** the accent is set to Lemmy, Blue, Indigo, Purple, Pink or Red, in Dark appearance
- **When** I look at the same accent-coloured labels and badges
- **Then** the text is drawn in a lighter shade of that accent, so it clears the same bar against the dark surfaces and the accent washes behind those badges

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

### Reduce Motion snaps the offline-download ring instead of sweeping it

- **Given** Reduce Motion is enabled, and a feed is downloading for offline browsing
- **When** the download's progress advances
- **Then** the status pill's ring still shows the new proportion completed
- **And** it changes to it directly, without the arc animating around

## Not supported / out of scope

- **No custom handling for Bold Text, Increase Contrast, or Reduce Transparency.** These are left to the system defaults; Spud does not adjust its own styling for them. Two caveats on how far that has been checked: **Increase Contrast has not been verified per surface** — the argument that the stock glass and system colors adapt on their own is reasoning, not evidence, and the capture is still owed. **Reduce Transparency could not be toggled live** on the test environment; instead every translucent surface in the app was audited statically and all of them use the adaptive system material family (no fixed non-adaptive blur styles anywhere), which is what lets the system substitute an opaque treatment — but that substitution has not been observed running.
- **No VoiceOver focus announcements.** Spud does not post screen-changed, layout-changed, or announcement notifications, nor manage focus explicitly, beyond the per-element labels and the modal presentation behavior the system provides.
- **A few labels do not live-update on a Dynamic Type change.** Most text tracks the setting immediately, but a small number of labels take the size at creation and refresh only when their view is rebuilt.
- **Typography is not centralized.** Fonts are defined per scene rather than as shared design tokens, so Dynamic Type adoption is broad but per-scene rather than enforced in one place.
