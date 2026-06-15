# Markdown renderer — block-based rich text for post & comment bodies

Date: 2026-06-15
Status: Design approved, ready to plan

## Problem

Spud's content is rich text in Markdown, and the bar is a *great* mobile rich-text
reader. The Claude Design handoff (`Spud Markdown Rendering.html` + `md-render.jsx`
/ `md-content.jsx` / `md-spec.jsx`) specifies the target: every Markdown element
Lemmy supports, rendered in Spud's visual language, in two contexts (post body /
comment body) across light / dark / True-Black, with first-class interactions.

The current renderer cannot produce it. Today a body is rendered as **one
`NSAttributedString`** (cmark via `Down` + `addingAutolinks()`) shown in a single
view (`LinkLabel`, or the newer `BodyTextView` — a TextKit 2 `UITextView` that adds
inline image attachments). That model renders inline text, links, and inline images
well, but it **cannot** make these first-class interactive elements:

- a fenced **code block** with a language header, a **Copy** button, and horizontal
  scroll (no wrap);
- a **table** that scrolls horizontally with per-column alignment;
- a **spoiler** disclosure row that expands / collapses nested blocks;
- **audio / video** embeds with transport controls;
- an **image** with loading / failed / loaded states, a "Tap to zoom" affordance,
  and an italic alt caption;
- a **footnotes** section with `[^n]` ↔ footnote jump / return.

The design is fundamentally **block-based and interactive**. This spec defines a new
renderer built for that, developed in isolation in a dedicated test app so we can
iterate on rendering and interaction without rebuilding the whole Spud app.

## Decisions (confirmed)

- **Greenfield.** Do not anchor on `LinkLabel` or `BodyTextView`. Build the renderer
  we want; `BodyTextView` is replaced by the new component later.
- **Architecture: UIKit block composition with TextKit prose.** Parse to a block
  tree; a self-sizing container lays out one view per block. Prose blocks
  (paragraph / heading / list / quote / hr) render in a lightweight TextKit 2 text
  view (inline links / mentions / emoji / images, with selection within the run);
  structural / interactive blocks (code, table, spoiler, image, audio, video,
  footnotes) are dedicated `UIView`s with real controls and scroll views.
  - Accepted tradeoff: text selection is **per-block**, not one continuous drag
    across the whole body. (Most best-in-class clients accept this.)
  - Rejected: a single TextKit text view hosting interactive blocks via
    `NSTextAttachmentViewProvider` (disclosure / resize / horizontal-scroll-inside-
    an-attachment / button hit-testing are fiddly, and blocks are hard to isolate as
    clean components). Rejected: a SwiftUI renderer (per-`Text` selection only, many
    hosting contexts in a long comment thread need perf care, precise custom layout
    fights the framework).
- **Parser: Apple `swift-markdown` + a Lemmy-extensions pass.** `swift-markdown`
  gives a clean `Markup` tree + `MarkupVisitor` with GFM tables / strikethrough — the
  right base for building a block model (we are no longer producing a
  styler→`NSAttributedString`). A custom layered pass adds Lemmy's extensions, the
  same shape Lemmy itself uses (markdown-it + plugins).
  - Rejected: extending the `Down`/cmark fork (node tree is oriented toward
    styler→attributed-string, less ergonomic for a block model). Rejected: a
    hand-written parser (reimplements CommonMark block / nesting rules the libraries
    already get right).
- **Packaging: a new `SpudMarkdownKit` framework + a thin `MarkdownLab` app target.**
  The framework depends only on SpudUIKit (tokens) + SpudUtilKit + swift-markdown,
  with **no app dependency**. Both the Lab and Spud consume one component.
- **Scope this round: build it great in the Lab; integration is a follow-up.** The
  renderer is proven against the kitchen-sink fixture in the Lab. Wiring it into the
  real post / comment call sites (replacing `BodyTextView` / `LinkLabel`) and
  connecting real media / navigation / haptics is a separate later project.
- **Fidelity.** Match the visual spec on well-formed input. We do **not** port
  markdown-it's exact grammar — on pathological input we may diverge slightly from
  lemmy-ui. Raw HTML is disabled upstream (`html:false`); literal tags render as
  plain text, never parsed.

## Current state (from codebase)

- `Spud/Utils/MarkdownRenderer.swift` — thread-safe `NSCache` of rendered bodies,
  keyed by source + a styling key, pre-warmed off-main before the diffable snapshot.
  The new renderer keeps this proven cache pattern, but caches a **block layout**
  instead of one attributed string.
- `Spud/Utils/NSAttributedString+Autolink.swift` — current inline augmentation pass
  over cmark output; precedent for our richer inline tokenizer.
- `Spud/Utils/Views/BodyTextView.swift` (on the inline-images commit line) — TextKit 2
  `UITextView` with `BodyImageAttachment` async load / reflow / row re-measure and a
  per-link / per-image accessibility container. Its inline-image attachment and
  accessibility-container ideas are reused inside `ProseBlockView`.
- `Spud/3rdparty/LinkLabel/*` — the label being superseded for bodies. Not used by
  the new renderer.
- Tokens: `SpudUIKit` dynamic `UIColor`s (semantic backgrounds + accent), resolving
  light / dark / True-Black at draw time. Brand accent is Lemmy teal `#009687`.
- Media / interaction already in Spud (reused at integration, not rebuilt): media
  viewer + `ImageService` (downsampling, animated GIF), `presentVideoPlayer`
  (AVPlayer), `Haptics`, `LemmyURLParser.classify` at tap time, `URL.spud` decoding.

## Module shape & dependencies

```
SpudMarkdownKit (new framework)
   ├─ depends on: SpudUIKit (tokens), SpudUtilKit, swift-markdown
   └─ NO app dependency  (frameworks must not import the app)

MarkdownLab (new app target)   → SpudMarkdownKit, SpudUIKit
Spud (app, later integration)  → SpudMarkdownKit
```

The renderer is pure: markdown `String` → block model → self-sizing `UIView`.
Navigation / media / haptics it cannot own are reached through a small delegate.

## Data model (the contract everything is built against)

Two Swift value-type trees — block and inline — mirroring the reference's
`Blocks` / `Inline` split.

```
enum MarkdownBlock {
    case paragraph([Inline])
    case heading(level: Int, [Inline])
    case list(ordered: Bool, start: Int?, items: [ListItem])  // ListItem = [Inline] + [MarkdownBlock]
    case quote([MarkdownBlock], depth: Int)
    case codeBlock(language: String?, code: String)
    case table(align: [Column.Align], head: [[Inline]], rows: [[[Inline]]])
    case image(BodyImageRef)            // url, alt, intrinsic ratio if known
    case audio(url: URL, …)
    case video(url: URL, poster…)
    case spoiler(title: [Inline]?, children: [MarkdownBlock])
    case footnotes([Footnote])          // n, [Inline]
    case thematicBreak
}

enum Inline {
    case text(String)                   // already smart-typographed
    case strong([Inline]) / emphasis([Inline]) / strikethrough([Inline]) / mark([Inline])
    case code(String)                   // inline code, never wraps
    case superscript([Inline]) / `subscript`([Inline])
    case link(text: [Inline], url: URL)
    case mention(name: String, instance: String, url: URL)    // @chip
    case community(name: String, instance: String, url: URL)  // !chip
    case customEmoji(shortcode: String, url: URL?) / case emoji(String)
    case footnoteRef(String)
}
```

This is the stable seam: the parser produces it, the renderer consumes it, and it is
trivially snapshot / unit-testable on its own.

## Parsing pipeline

A layered pipeline; `swift-markdown` handles CommonMark + GFM, the custom passes add
Lemmy's extensions:

1. **Pre-process raw source** — lift out what swift-markdown can't see: `::: spoiler
   <title>` containers and `[^n]: …` footnote *definitions*. Record them; leave clean
   CommonMark behind.
2. **Parse** with swift-markdown → `Markup` tree (paragraphs, headings, lists, nested
   quotes, fenced code, tables, images, links, emphasis / strong / strikethrough,
   thematic breaks, inline code).
3. **Walk** the tree with a `MarkupVisitor` → the `MarkdownBlock` tree.
4. **Inline tokenizer** over each `Text` run → the `Inline` model: `==mark==`,
   `^sup^`, `~sub~`, `@user@inst`, `!community@inst`, `:emoji:` / `::custom::`,
   `[^n]` refs, plus **smart typography** (curly quotes, en/em dashes, ellipsis,
   ©/™/® — cmark / markdown-it do this; swift-markdown does not, so we do).
5. **Media detection** — an image / link whose URL has an audio / video extension
   becomes an `audio` / `video` block (Lemmy renders body media links as players); a
   plain image becomes an `image` block.
6. **Re-attach** spoiler containers and the footnotes section.

The kitchen-sink markdown from `md-content.jsx` is the golden parser fixture.

## Rendering layer

Single entry point: `MarkdownBodyView`, a self-sizing `UIView` owning a vertical
block container that dispatches each block to a dedicated view.

| Block | View | Notes |
|---|---|---|
| paragraph / heading / list / quote / hr | `ProseBlockView` (TextKit 2 text view) | Contiguous text-ish blocks coalesce into one cached attributed string + text view; inline links / mentions / emoji / images render here, selection works within the run. Quote adds the tinted bar + nesting inset; list draws markers. |
| code | `CodeBlockView` | header (lang + Copy) over a horizontal `UIScrollView`; never wraps. Copy = `UIPasteboard` + `UIImpactFeedbackGenerator` (no app dep). |
| table | `TableBlockView` | `UIScrollView` wrapper, per-column alignment, tinted header; comment context forces `minWidth` so it scrolls under the rail. |
| spoiler | `SpoilerBlockView` | disclosure row; expands / collapses nested blocks; resize → `onContentSizeChange`. |
| image | `ImageBlockView` | aspect-ratio box with loading / failed / loaded states, "Tap to zoom" chip, italic alt caption. |
| audio / video | `AudioBlockView` / `VideoBlockView` | transport / poster + play. In the Lab these are placeholder-rendered (fake waveform, poster tile); real `ImageService` / `AVPlayer` wiring is integration-time. |
| footnotes | `FootnotesBlockView` | section header + ordered items with ↩ return; `[^n]` ↔ footnote jump is internal scroll within the body. |

The inline layer renders inside `ProseBlockView` as one `NSAttributedString` (links /
mentions / communities carry their destination `URL`; custom emoji + body images are
`NSTextAttachment`s, reusing the `BodyImageAttachment` idea). Parse + render run
off-main and cache in an `NSCache` keyed by source + sizing — the proven
`MarkdownRenderer` pattern, producing a block layout instead of one string.

## Context, sizing & theming

- **Context** — `post` (generous: 16.5pt body, H1 29pt, 15pt block gap) vs `comment`
  (dense: 14.5pt, 9pt gap), exactly the reference's `scale('post'|'comment')`. One
  enum drives every block's metrics.
- **Sizing** — built from Dynamic Type + the app's text-scale (−3…+6) + density
  (−1pt compact), honoring the Display preferences.
- **Theming** — SpudUIKit dynamic `UIColor` tokens (brand teal accent `#009687`); no
  re-render on theme / True-Black switch.
- **iPad / landscape** — the renderer is width-driven and self-sizing, so it works in
  the split view with no special-casing.

## Interaction delegate

Small surface; the host wires the rest. Copy, footnote jump / return, and spoiler
toggle are internal.

```
protocol MarkdownBodyDelegate: AnyObject {
    func markdownBody(_:didTapLink url: URL)             // links, autolinks, @mention, !community
                                                         //   (host classifies via LemmyURLParser, honors in-app/Safari pref)
    func markdownBody(_:didTapImage:altText:sourceRect:) // → media viewer / zoom
    func markdownBody(_:didTapVideo url: URL)            // → AVPlayer
    func markdownBody(_:didTapAudio url: URL)            // → inline play
    func markdownBodyDidChangeContentSize(_:)            // spoiler expand / image load → host re-measures the row
}
```

The Lab supplies a logging / no-op delegate.

## The Lab

`MarkdownLab` reproduces the reference gallery: the kitchen-sink **post** and
**comment thread** (ported from `md-content.jsx`) rendered in **post / comment ×
light / dark / True-Black**, with a control bar to flip context / theme / text-scale
/ density live, plus an "edit raw markdown" pane to paste arbitrary input. This is
the fast iteration loop — no Spud build, no navigation.

## Testing

- **Parser unit tests** — kitchen-sink markdown → expected block model; edge cases
  (long unbroken URLs, empty spoiler title, nested quotes, wide tables, malformed /
  missing footnotes, unknown emoji shortcodes, raw HTML as literal text).
- **Snapshot tests** — each block view in isolation (device-independent, pinned
  scale) + the full kitchen-sink post / comment in light / dark. Reuses Spud's
  existing snapshot infrastructure.
- **Accessibility** — VoiceOver children per link / mention / image, disclosure
  traits on spoilers (carried over from `BodyTextView`'s approach).

## Edge cases (from the design's redlines)

- **Mentions vs links vs communities** — all brand teal, but shape separates them:
  links are inline underlined text; mentions / communities are tinted chips with a
  leading glyph (@ vs people). The full federated handle including `@instance` is
  kept and wraps rather than truncating.
- **Long unbroken URLs & code** — prose URLs use break-all to wrap inside the column;
  code never wraps (fenced + inline code scroll horizontally) so indentation and a
  copy-pasteable line stay intact.
- **Tables wider than the screen** — the table wrapper is the only horizontally-
  scrolling region; in a comment it gets a `minWidth` so it scrolls under the depth
  rail rather than crushing columns. No reflow to stacked cards — alignment is the
  point of a table.
- **Images loading / failed** — loading shows a sized placeholder (intrinsic aspect
  if known) so there's no layout jump; failed shows a quiet plate with a broken-image
  glyph and an "Open in browser" escape hatch. Alt text renders as caption either way.
- **Empty spoiler title** — fall back to a muted italic "Spoiler" placeholder so the
  affordance still reads as expandable and VoiceOver has something to announce.
- **Deeply nested comments** — heavy blocks compress rather than collapse: an H1
  keeps its token but a lower size ceiling; code / tables scroll; embeds shrink to
  comment scale. The depth rail always keeps the leading edge.

## Phasing

1. Framework + Lab scaffold; block / inline model; parser (swift-markdown + Lemmy
   passes) + parser tests.
2. `ProseBlockView` + full inline rendering; Lab renders the text-only kitchen sink.
3. Structural / interactive blocks: code, table, spoiler, footnotes.
4. Media blocks: image (states / zoom / caption), audio, video (placeholder media in
   the Lab).
5. Snapshot suite (kitchen-sink + edge cases); polish.
6. *(Separate later project)* Integration — replace `BodyTextView` / `LinkLabel` at
   post + comment body call sites; wire real media / navigation / haptics.

## Out of scope (this round)

- Integrating the renderer into real Spud screens (phase 6, a separate project).
- The composer's Write / Preview using this engine (candidate follow-up once proven).
- Cross-block continuous text selection.
- Exact markdown-it grammar parity on pathological input.
- Server-synced rendering preferences.
</content>
</invoke>
