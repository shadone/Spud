# Claude Design prompt — Spud Share as Image

Paste the block below into Claude Design inside the **Spud** project. It assumes the existing
Spud files are present (`design-canvas.jsx`, `phone.jsx`, `unified-shell.jsx`,
`screens-common.jsx`, `app-kit.jsx`, `community.jsx`, `lemmy-data*.js`) and reuses their kit.
The companion feature spec is [`../features/sharing.md`](../features/sharing.md) — note that its
"Not supported" section used to read *"No share-as-image. Sharing carries the URL only"*. This
prompt is the design that reversed that line.

---

Build **Spud Share as Image** — a way to turn a Lemmy post, or a post plus a comment chain, into a
picture you can post anywhere. This extends the existing **Spud** design; match it exactly and
reuse its kit. Do **not** restyle the app or invent new tokens.

**Reuse the existing kit and language.** Use `window.SPUD` (`T` color tokens, `TabBar`, `NAV_H`,
`ACCENTS` — accent is `ACCENTS[0].hex`, the Lemmy teal), `window.KIT.NavBar`, `window.SC`
(`CommunityIcon`, `PrimaryBtn`, `GhostBtn`), and the globals `Icon`, `PhoneFrame`, `Thumb`, `Tile`,
`SAFE_TOP`. Match the app's language: dark UI, hairline `0.5px` separators, `T.mono` tabular
numerals for all stats, `c/name@instance` handles with a dimmed `@instance`, the frosted
context-menu/sheet style. Artboards are `446×1056` on a transparent board, laid out with
`DesignCanvas` / `DCSection` / `DCArtboard` / `Caption`.

**Deliver** a new component file `share-image.jsx` (an IIFE exposing `window.SHIMG = { ... }`) and a
canvas `Spud Share as Image.html` that loads the existing scripts plus `share-image.jsx` and renders
the sections below — each `DCArtboard` wrapped in a captioned `Board` with
`{ accent, n, name, who, concept }`.

## The two things being designed — keep them distinct

**1. The card** is the rendered image itself. It leaves the app. It gets viewed in Mastodon,
iMessage, Discord and Slack, often at thumbnail size, next to content that is not Spud. **It is not
a screenshot of a Spud screen and must not look like one.** It is its own designed object: no vote
buttons, no swipe hints, no tap targets, no relative timestamps, typography tuned for a static image
rather than for scrolling. Design it the way you'd design a quote card, not the way you'd design a
table row.

**2. The editor** is the Spud sheet where you configure the card before sharing it. This one *is* a
Spud screen and should feel exactly like the rest of the app.

## What the card carries

Three jobs, all real, and they pull in different directions — resolve this in the card design:

- **Showing off good content off-platform.** Must look great and stay legible small.
- **Receipts.** Capturing what someone actually said, in a form a stranger can verify.
- **Making the funny thing shareable.** Tight, punchline-forward, minimal chrome.

The toggles, grouped:

- **Content** — community + creator · stats (score, comment count) · timestamp (always absolute,
  never "3h ago") · the post's media · body treatment (full / truncate-with-fade / title-only) ·
  ancestor depth (0–N comments walking *up* from the shared comment toward the root, optionally
  topped by the post itself) · redact identities.
- **Presentation** — light or dark · canvas (backdrop and aspect: native, square, story 9:16) ·
  footer (permalink text and/or a small "via Spud" mark).
- **Output** — share sheet · Save to Photos · Copy.

**Body treatment is load-bearing, not polish.** Lemmy posts run long; without truncation a single
post renders an unshareable 8000px column. Design the truncation — the fade, and what tells the
reader there was more.

**Ancestors, not replies.** The chain always walks upward: the comment, its parent, its parent's
parent, optionally the post at the top. The shared comment is the destination and should read as
such — the ancestors above it are setup. Design how a deep chain elides its middle rather than
producing an endless column.

**Redaction is a quiet toggle, not a headline.** When on, usernames and avatars across the whole
card are obscured. It exists because fediverse norms are strongly anti-dogpiling. It should be
findable and unremarkable — Spud is not a tool built for drama.

## The guardrail

**The card never editorializes.** Text is never editable. No crop drops context. The absolute
timestamp and the permalink always survive, in every configuration, including redacted. Attribution
is what lets a beautiful card still work as a receipt — a prettified card of someone's words with no
way to check it reads as fabricated. Design the footer so this never feels like a compliance tax.

## Constraints you would not otherwise guess

- **The card's light/dark is independent of the app's theme.** Spud's theme is
  `system / light / dark / trueBlack`, and its semantic background tokens resolve against a *global*
  true-black flag rather than a per-view value. So a light card shared from a true-black app must
  still be light. Give the card its own two-surface palette rather than leaning on the app's
  background tokens. Show both in every card artboard.
- **Accent is a fourth theme axis.** Spud has a 9-swatch accent palette. Open question worth
  answering in the design: does the card follow the user's accent, or is a shared image
  accent-neutral so it reads the same from everyone? Argue a position.
- **NSFW media renders spoilered by default**, with an explicit reveal in the editor. Never
  auto-reveal.
- **Alt text ships with the image.** Spud's stated bar is that accessibility is part of "done".
  The share payload carries auto-generated alt text describing the card, alongside the permalink URL
  so recipients can click through. Show where the user sees and can edit it.
- **Dynamic Type and iPad.** The editor is a Spud screen and inherits both. The card is a fixed
  artifact and does not — decide and show what the card does when the user runs large text.

## Explore the editor's IA — 2 to 3 options, then recommend

Do **not** settle on one. Produce distinct options and argue for one:

- **Presets + escape hatch** — a row of named starting points (e.g. Standard, Compact, Redacted,
  Story) with a Customize path underneath.
- **Panel of switches** — preview on top, a grouped list of every toggle below.
- **Direct manipulation** — no switch list; you tap elements *in the preview* to turn them off. Tap
  the avatar and it blurs, tap the stats and they vanish, drag the chain's top edge to set depth.

My lean is direct manipulation, because the knobs map one-to-one onto things visibly on the card and
a switch list makes you translate between the two. But it is a lean, not a spec — if a preset row
gets people to a good image faster, make that case. Whatever wins must survive the editor opening
with the user's last-used settings already applied, so the common path is open, glance, share.

**Naming.** One action, `Share as Image…`, everywhere. Spud enforces terminology consistency — do
not introduce a second verb ("Create Image", "Make Picture") anywhere in the UI copy.

## Data realism

Use fields the app actually has. A post: title, optional body markdown, optional image, community
(`c/technology@lemmy.world`), creator (`u/name@instance`), score, comment count, absolute
timestamp, permalink. A comment: body, creator, score, timestamp, depth. Make the sample content
carry its weight — the chain artboards need a chain that's actually funny or actually damning, not
lorem. Show a long post that genuinely needs truncating.

Produce these artboards, grouped into sections:

### Section — The card
- **Card anatomy.** The full card with every element on, light and dark side by side, elements
  labelled. This is the reference artboard.
- **Content variants.** Title-only, truncated-with-fade, and full-body, each with and without the
  post's media. Show what a wide image does to the card's proportions.
- **Chain card.** Post on top, ancestors below it, the shared comment as the destination. A second
  variant with a deep chain that elides its middle.
- **Redacted.** The same chain card with identities obscured, showing that the timestamp and
  permalink survive.
- **Canvas options.** One card shown on native, square, and story 9:16 backdrops — what fills the
  extra space, and what the card does when the aspect fights its natural shape.
- **In the wild.** The card as it actually lands: at thumbnail size in a message list, and full
  size next to non-Spud content. This is the artboard that proves it works.

### Section — The editor (options)
- **Option A / B / C.** One artboard each, same content configured identically, so they're
  comparable. Each shows the live preview plus its control model.
- **Recommendation.** A caption arguing which one wins and why.

### Section — Entry and output
- **Entry points.** The post context menu with `Share as Image…` in its share group (alongside the
  existing Share, Reply, Cross-post), and the post-detail overflow menu.
- **Handoff.** The system share sheet receiving the image, with the permalink and alt text along
  for the ride.

### Section — Edges
- **Long post.** The truncation working on a genuinely long body.
- **NSFW.** Spoilered by default, plus the reveal control.
- **Media still loading.** What the preview shows before the post's image has arrived.
- **iPad.** The editor in the regular size class — Spud treats iPad as first-class, not a stretched
  iPhone.

Keep everything on-brand: teal accent, dark app surfaces, hairline rows, mono numerals,
friendly-but-refined. No emojis in UI copy. Captions should explain the sharing intent — what job
each artboard serves and which of the three purposes it's optimizing for.

---

## Notes for whoever runs this

- The card/editor split is the most important thing in this prompt. The failure mode is Claude
  Design producing a card that looks like a screenshot of a Spud post cell — which is the option we
  explicitly rejected, because a designed card serves two of the three jobs better.
- The editor IA is deliberately left open (three options + a recommendation). The rest of the prompt
  is more prescriptive because the toggle set is settled product scope, not a layout question.
- The true-black note is a real trap in the code, not a hypothetical: `Theme.background` and friends
  read the global `ThemeManager.usesTrueBlackBackgrounds`, so a card that reuses the app's
  background tokens will silently render black for true-black users no matter what the light/dark
  toggle says.
- Implementation is greenfield — there is no render-view-to-image code in the app today, and the
  only existing "share a `UIImage`" path is the media viewer's private `presentActivity(items:)`,
  which is a DRY cleanup that pairs naturally with this work.
- The implementation spec comes *after* this design returns; don't write it from this prompt alone.
