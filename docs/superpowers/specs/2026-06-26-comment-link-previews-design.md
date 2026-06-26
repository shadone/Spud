# Comment & body link previews — rich video embeds + anchor text

- **Date:** 2026-06-26
- **Status:** design (approved scope; pending spec review)
- **Surfaces:** comment bodies, post bodies (text posts), post-detail header link card

## Problem

A markdown link inside a comment or post body renders today as a bare preview
card (`LinkPreviewView`) showing only the URL's **host + path** and a chevron —
no anchor text, no title, no thumbnail. For video links (YouTube, Invidious,
PeerTube) this is especially poor: the reported case is a comment with a YouTube
and an Invidious link that show "nothing — no thumbnail, no title."

Lemmy provides embed metadata (`urlEmbedTitle`, `urlEmbedDescription`,
`thumbnailUrl`) **only for a post's own URL**, never for links inside bodies. The
app does no client-side metadata fetching today. Separately, the post-detail
header's link card *does* receive that server embed data but doesn't display the
title/thumbnail either.

## Goals

1. **Anchor text on every card (the Apollo touch).** For `[Foobar](https://…)`,
   show "Foobar" so the reader sees where the link came from. Local, always — no
   network, independent of any preference.
2. **Rich video previews.** For YouTube / Invidious / PeerTube links, show a
   thumbnail (with a ▶ play badge) and the real video **title**.
3. **Enrich the post-header link card** to display the Lemmy-provided title +
   thumbnail it already receives (currently shows only host + path).
4. **A Settings toggle** ("Load link previews", default **on**) gating all
   *client-initiated* fetching for in-body link cards.

## Non-goals

- **Inline video playback.** YouTube/Invidious/PeerTube have no native stream we
  can hand to `AVPlayer`. Tapping a link keeps its current behavior — honoring the
  external-link preference (in-app Safari / system browser / open-in-app).
- **Generic OpenGraph / LinkPresentation metadata for arbitrary (non-video)
  links.** Those stay local: anchor text + host + a type badge. The embed service
  interface is shaped so a generic OG path could be added later behind the same
  toggle, but it is out of scope now.
- **Changing tap / navigation routing** of any link.

## The preference (the gate)

- New `PreferencesService.fetchLinkEmbeds: Bool`, default `true`, exposed as an
  `AsyncStream<Bool>` like the other preferences (so views re-render on change).
- A Settings toggle "Load link previews" with a one-line footer explaining it
  fetches thumbnails and titles for links (and can be turned off for privacy / to
  save data). Placed alongside the existing **Links** settings (External link
  handling) — the natural home for link behavior.
- **Off → fully local.** In-body link cards show anchor text + host + a type
  badge only; **zero third-party contact** for the card (no oEmbed call, no
  thumbnail image load).
- **On →** in-body video links additionally load a thumbnail + title.
- The **post-header card is unaffected by the toggle**: its title/thumbnail come
  from Lemmy's response (no client fetch), so it always shows them.

## Architecture

Five units, each independently testable:

### 1. `VideoLinkParser` (pure; SpudUtilKit)

`static func parse(_ url: URL) -> VideoLink?` returning
`VideoLink { host: VideoHost, videoId: String, thumbnailURL: URL?, oEmbedURL: URL? }`,
where `VideoHost` is `.youtube | .invidious | .peertube`.

Detection rules:

- **YouTube** (definitive): hosts `youtube.com`, `www.youtube.com`,
  `m.youtube.com`, `music.youtube.com`, `youtube-nocookie.com` → `videoId` from
  the `v` query item; host `youtu.be` → `videoId` from the first path segment.
  `thumbnailURL = https://i.ytimg.com/vi/<id>/hqdefault.jpg` (derived locally).
  `oEmbedURL = https://www.youtube.com/oembed?url=<encoded>&format=json`.
- **Invidious** (heuristic): any non-YouTube host whose path is `/watch` with a
  YouTube-shaped `v=<11-char id>` query. `thumbnailURL =
  https://<host>/vi/<id>/hqdefault.jpg` (Invidious proxies YT thumbnails).
  `oEmbedURL = https://<host>/oembed?url=<encoded>&format=json`.
- **PeerTube** (heuristic): path `/w/<shortId>` or `/videos/watch/<uuid>`. No
  reliably-derivable thumbnail URL, so `thumbnailURL = nil` (the thumbnail comes
  from oEmbed). `oEmbedURL = https://<host>/services/oembed?url=<encoded>&format=json`.
- Anything else → `nil`.

Heuristic false positives (a non-video site matching the Invidious/PeerTube
shape) are harmless: the oEmbed call simply 404s / returns non-JSON and the card
degrades to anchor text + host (see error handling).

### 2. `LinkEmbed` model + `LinkEmbedService` (SpudDataKit)

- `struct LinkEmbed { let kind: Kind; let title: String?; let thumbnailURL: URL? }`,
  `Kind = .video | .generic`.
- `protocol LinkEmbedServiceType { func embed(for url: URL) async -> LinkEmbed? }`.
- Implementation:
  - Returns `nil` immediately when `fetchLinkEmbeds` is off, or the URL is not a
    recognized video link.
  - For a video link: take the locally-derived `thumbnailURL` (YouTube/Invidious),
    fetch oEmbed for the `title` (and, for PeerTube, the `thumbnail_url`).
  - **Cache** results in an in-memory `NSCache` keyed by absolute URL, plus a
    short negative-result cache so a failed fetch isn't retried on every
    re-render. (No disk cache in v1 — titles are cheap to refetch across launches.)
  - oEmbed fetch: a `URLSession` GET with a short timeout, no cookies/credentials,
    decoding `{ title, thumbnail_url }`. Network/JSON failure → return a
    `LinkEmbed` carrying just the derived thumbnail (YouTube/Invidious) or `nil`
    (PeerTube).
- The thumbnail image itself is loaded by the **existing `ImageService`**, not by
  this service (which only resolves the thumbnail *URL* + title).

### 3. `CommentLinkPreview` extension

Add `anchorText: String?` and `kind: LinkPreviewKind` (`.video | .generic`) to the
existing `CommentLinkPreview`. `commentLinkPreviews(limit:)` extracts the anchor
text by rendering the `MarkdownInline.link(text:)` subtree to a plain string, and
classifies via `VideoLinkParser.parse(url) != nil`.

### 4. `LinkPreviewView` enhancement (existing component)

New layout, degrading cleanly:

```
┌───────────────────────────────────────┐
│ [▶ thumb]  <title or anchor text>      │
│            <anchor text> · <host>   ›  │
└───────────────────────────────────────┘
```

- Leading thumbnail (square), with a ▶ overlay badge when `kind == .video`;
  hidden entirely when there is no thumbnail.
- Primary line: the fetched **title**, or the **anchor text** if no title.
- Secondary line: "anchor text · host" (or just host when anchor text equals the
  URL, e.g. a bare autolink).
- A `configure(...)` that takes anchor text + host + an optional resolved
  `LinkEmbed`; the hosting cell loads the thumbnail asynchronously via
  `ImageService` and refreshes the title when the embed resolves.

### 5. Cell / header integration

- **Comment bodies** (`PostDetailCommentCell`): the existing
  `linkPreviewsStackView` / `configureLinkPreviews` path — render each card
  immediately with anchor text + host. When `fetchLinkEmbeds` is on and the link
  is a video, kick `LinkEmbedService.embed(for:)` in a task, updating the card with
  thumbnail + title when it resolves. Cell reuse must cancel / ignore stale results
  (token per configure).
- **Post bodies** (text posts, in the header cell): reuse the *same*
  `commentLinkPreviews(limit:)` extraction and `LinkPreviewView`. The header cell
  must host a link-previews stack below its body the way the comment cell does — if
  it doesn't already, add one (same view, same async-fill logic). This is the
  "nearly free" part: shared extraction + card, new wiring in one more cell.
- **Post-header link card** (`PostDetailHeaderViewModel` + the header's
  `LinkPreviewView`): render the already-present `row.urlEmbedTitle` and
  `row.thumbnailUrl`. No `VideoLinkParser` / `LinkEmbedService` involvement — pure
  server data, always shown.

## Data flow (comment YouTube link, toggle on)

1. Parse body → `CommentLinkPreview { anchorText: "Foobar", url, kind: .video }`.
2. Cell renders the card: "Foobar / youtube.com", placeholder thumbnail slot.
3. Cell calls `LinkEmbedService.embed(for: url)` → derives
   `i.ytimg.com/vi/<id>/hqdefault.jpg`, fetches oEmbed → `title: "Rick Astley — …"`.
4. Card updates: thumbnail (▶) + title "Rick Astley — …" + secondary
   "Foobar · youtube.com". Subsequent renders hit the cache (instant).

## Error handling

- oEmbed failure / timeout / non-JSON → keep anchor text + host; show the derived
  thumbnail if it loaded (YouTube/Invidious), otherwise none. No spinner blocks
  the card; enrichment is progressive.
- Negative results are cached (short TTL) to avoid refetch storms while scrolling.
- A `nil`/invalid thumbnail image load fails silently (no broken-image tile),
  reusing `ImageService`'s existing behavior.

## Testing

- **`VideoLinkParser`** (pure unit): YouTube variants (`watch?v=`, `youtu.be`,
  `-nocookie`, `m.`), Invidious `watch?v=`, PeerTube `/w/` and `/videos/watch/`,
  and negatives (plain link, image, `/c/.../p/...`); assert host kind, video id,
  derived thumbnail URL, and oEmbed URL.
- **`LinkEmbedService`** (injected fetcher): oEmbed JSON → title/thumbnail;
  failure → graceful fallback; preference-off → returns nil without fetching;
  cache hit → no second fetch.
- **Anchor-text extraction**: `[Foobar](url)` → "Foobar"; nested emphasis inside
  the anchor flattens to text; a bare autolink → anchor text equals the URL.
- **`LinkPreviewView`** snapshots: anchor-only (toggle off / generic link),
  video-rich (thumbnail + title + anchor + host), and the header card with server
  embed (title + thumbnail).
- **Preference gating**: with `fetchLinkEmbeds` off, the cell builds no embed task
  (no fetch) and the card stays local.

## Risks / open notes

- **Invidious / PeerTube detection is heuristic** (shape-based, no instance
  allowlist). Mitigated by graceful oEmbed fallback — a false positive yields a
  bare card, never a wrong title.
- **oEmbed + thumbnail contact the video host** (Google's CDN for YouTube
  thumbnails). This is gated by the toggle and consistent with Spud already
  loading third-party images for inline media. Off = no contact.
- **Per-comment cap** stays at the existing 3 previews; embed fetches only fire
  for the (≤3) visible video links.
