# Share as Image

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Sharing](sharing.md), [Post detail and comments](post-detail-and-comments.md), [NSFW content visibility and blur](nsfw-content.md), [Cross-posting](cross-posting.md)

## What it does

Turns a post, or a comment together with its ancestor chain, into a designed, shareable
image card — configured in an editor sheet and handed to the system share sheet, Photos,
or the pasteboard, alongside the content's permalink. The card is its own designed object
with a fixed look: it is not a screenshot of a Spud screen, and it never changes with the
device's theme, accent color, or text-size setting.

## Behavior and rules

- **The card, not a screenshot.** The card has its own fixed two-surface palette (light and
  dark) that is completely independent of the app's theme (System / Light / Dark / True
  Black) and accent color. Its only brand color is a fixed Lemmy teal, used for the score
  glyph, the "Read the full post on Lemmy" link, the shared comment's rail, and the "via
  Spud" mark — never the app's user-chosen accent.
- **Two card kinds.** A post card carries the community, creator, title, media, body, stats,
  and an absolute timestamp. A comment card carries the shared comment plus its ancestor
  chain, walking upward from the comment toward the post root; an optional post-context
  header (community + title only, no media) can sit above the chain. The shared comment is
  visually emphasized (a teal rail, a "SHARED" tag, its own timestamp) as the destination of
  the chain.
- **Deep chains elide the middle.** More than four visible ancestors collapse to the closest
  two, a "N more replies" divider, and the farthest two from the shared comment — the chain
  never renders as an endless column.
- **Body treatments.** A post's body renders in full, is clamped to a fixed height with a
  bottom fade and a "Read the full post on Lemmy →" link (only when the body actually
  overflows that height), or is omitted entirely (title only).
- **Media, including wide images.** A post's image renders at a normal or a relaxed
  (shorter) height for a wide (wider-than-4:3) image. Wide-aspect detection needs the
  image's pixel dimensions, which are only known when sharing from post detail (the post
  header or a comment's post-context header) — a share started from the feed or Search post
  menu always uses the normal height, since those rows don't carry image dimensions.
  Comment-chain cards never show the post's media at all, even when their optional
  post-context header is on.
- **NSFW media is spoilered by default**, with a Core Image blur and a "Sensitive content"
  overlay, and a per-card "Reveal for this card" pill in the editor. A reveal applies only to
  the card currently being edited — it is never saved to the last-used settings and never
  auto-applied to a future share, even of the exact same post.
- **Redact identities** replaces every person shown on the card — a post's creator, and
  every author in a comment chain — with a striped placeholder circle and a "u/•••••••"
  handle. The community is never redacted; it's treated as the card's public context, not a
  private identity.
- **Stats toggle.** The score/comment-count row can be hidden; when it is, the absolute
  timestamp still renders alone, right-aligned.
- **Canvas.** Native (the exported image is exactly the card, roughly 1116px wide at its
  fixed 372pt design width), Square (1080×1080, card centered on a decorative backdrop), or
  Story (1080×1920, same backdrop). The card is scaled down to fit the backdrop's padding
  but never enlarged past its native size.
- **Attribution footer.** A hairline divider, the permalink, and a "via [glyph] Spud" mark —
  the glyph is a simple fixed teal mark, not a bundled wordmark asset (see "Not supported").

### Guardrails

- **Card text is never editable.** Every string on the card (title, body, handles, counts)
  comes from the source post/comment; there is no text field on the card itself.
- **The absolute timestamp and the permalink render in every configuration.** No toggle can
  remove either one — not the stats toggle (which hides only the score/comment cluster, not
  the timestamp), not redaction, not any canvas or appearance choice. Only the "via Spud"
  mark next to the permalink is toggleable.
- **Alt text travels with the shared file.** Choosing Share renders a PNG with the
  auto-generated (or user-edited) description embedded as image metadata (the PNG
  description field and an IPTC caption), and shares it alongside the permalink as a second
  share-sheet item — so a recipient, or assistive technology reading the file, gets both a
  description and a way to click through. Save to Photos writes only the rendered image (no
  embedded metadata, no permalink). Copy places the rendered image and the permalink on the
  pasteboard as two representations of one item, but — unlike Share — does not embed the alt
  text in the copied image bytes.

### The editor

- **Direct manipulation.** The editor presents a live, scaled preview of the card on a fixed
  dark stage. Tapping an element on the preview toggles it directly: the community lockup
  toggles the whole community-and-creator header; the creator/author lockup toggles
  redaction; the media block toggles the image; the body toggles through full → truncated →
  title-only → full; the stats row toggles the score/comment cluster; the footer toggles the
  "via Spud" mark; a chain card's post-context header toggles on/off the same way. A toggled-off
  section stays visible but dimmed in the editor (never fully removed) so there's always
  something to tap to restore it — the export never includes a dimmed section, only what's
  genuinely enabled.
- **Tray.** Below the preview: Light/Dark appearance, Native/Square/Story canvas, a chain-depth
  stepper (comment cards only, showing "Depth N" with − / + controls clamped to the ancestors
  actually available), and an Alt Text button.
- **Alt text.** A separate sheet shows the current description (auto-generated, or a prior
  edit) in an editable text field, with an "Auto" button that restores the auto-generated
  text. A manual edit applies only to the card being shared right now and is never persisted.
- **Output.** Share (system share sheet), Save to Photos, and Copy. Copy places a single
  pasteboard item carrying both the image and the permalink as separate representations, not
  two pasteboard items.
- **Last-used settings restored on open.** The editor opens with whatever configuration was
  last used — appearance, canvas, toggles, chain depth — so the common path is open, glance,
  share. The one exception is the NSFW reveal, which always resets to spoilered on a fresh
  open, matching the "never auto-revealed" guardrail above.
- **Dynamic Type.** The editor's own chrome (tray labels, buttons, the alt-text sheet) scales
  with the device's text size. The card preview itself does not — its typography is fixed, by
  design, so a shared image looks the same regardless of the sharer's text-size setting.
- **VoiceOver.** Every direct-manipulation region is its own accessibility element with a
  label naming what it is, a value reporting its current state, and a hint describing what a
  double-tap does — every toggle is reachable without needing to see the preview.

### Entry points

"Share as Image" appears immediately after "Share" everywhere the app already offers Share:

- The post long-press context menu, on both the feed and Search's post results.
- The post-detail overflow ("•••") menu.
- The post-detail header's own context menu.
- A comment's context menu in post detail, which builds the chain from that comment's
  ancestors.

If no shareable URL can be formed for the post or comment (mirroring the plain Share
action's same condition), a warning haptic fires and the editor never opens.

## Scenarios

### Share a post as image

- **Given** an open post
- **When** I choose "Share as Image" from its context menu or the post-detail overflow menu
- **Then** the editor opens with a live preview of the post card, using my last-used
  configuration
- **And** choosing Share, Save to Photos, or Copy produces the card with the post's
  permalink attached

### Share a comment with ancestors

- **Given** a comment with two or more ancestors above it in the thread
- **When** I choose "Share as Image" from the comment's context menu
- **Then** the editor opens with a comment-chain card showing the shared comment as the
  destination (teal rail, "SHARED" tag, its own timestamp) with its ancestors above it,
  walking up toward the post
- **And** a chain longer than four ancestors elides its middle behind a "N more replies"
  divider

### Redact identities

- **Given** the share-as-image editor open on a post or comment card
- **When** I tap the creator (or, on a chain card, any author lockup)
- **Then** every person on the card is replaced with a striped placeholder and a
  "u/•••••••" handle
- **And** the community lockup is unaffected — it is never redacted

### NSFW stays spoilered

- **Given** a post flagged NSFW with an image
- **When** I open "Share as Image" for it
- **Then** the image renders blurred with a "Sensitive content" overlay by default
- **And** tapping the "Reveal for this card" pill unblurs it for this card only
- **And** closing and reopening the editor for the same post shows it spoilered again

### Permalink survives every configuration

- **Given** the share-as-image editor open
- **When** I toggle any combination of appearance, stats, media, body treatment, redaction,
  or the "via Spud" mark
- **Then** the footer's permalink and the card's absolute timestamp remain visible
  throughout — no toggle removes either one

### Last-used settings restored

- **Given** I previously configured a card (e.g. dark appearance, Square canvas, stats
  hidden) and shared it
- **When** I open "Share as Image" again for a different post
- **Then** the editor opens with the same appearance, canvas, and toggle choices
- **And** any NSFW reveal from the previous session does not carry over — the new card
  opens spoilered

### Entry from each surface

- **Given** I am on the feed, Search results, an open post, or a comment
- **When** I look for "Share as Image"
- **Then** it appears immediately after "Share" in that surface's menu (feed and Search post
  context menus, post-detail overflow menu, post-detail header menu, and a comment's context
  menu)
- **And** if no URL can be formed for the content, a warning haptic fires and nothing opens

## Not supported / out of scope

- **Search's comment rows have no "Share as Image."** Search has no comment tree loaded in
  memory, so there is no ancestor chain to build; rather than ship a chain-less, degraded
  variant there, the action is omitted from Search's comment context menu.
- **The "via Spud" mark is a simple fixed teal glyph**, not a rendering of the app's real
  wordmark — Spud has no bundled wordmark asset today.
- **On-device validation of Photos-save and the share-sheet handoff is pending** — the
  export, PNG-metadata, and pasteboard paths are covered by unit and snapshot tests, but a
  live device run of Save to Photos and the system share sheet handing the file to another
  app has not yet been done.

## Deviations from the design deck

- The menu action is titled "Share as Image", without the design deck's trailing ellipsis —
  matching the app's existing "Share" and "Cross-post" entries, none of which carry one.
- Chain depth is controlled by a stepper (− / + with a "Depth N" label), not the deck's drag
  gesture on the chain's top edge — accessible via VoiceOver and honest about the exact
  ancestor count, at the cost of a slightly less direct interaction.
- The design deck's footer permalink toggle was not implemented — the permalink is
  hard-always-on, per the "permalink survives every configuration" guardrail; only the "via
  Spud" mark toggles.
