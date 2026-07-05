# Inline video-host playback (streamable first) — design

- **Date:** 2026-07-05
- **Status:** approved, pending implementation plan
- **Area:** SpudDataKit content detection + app-side playback; SpudSnapshotTests; docs
- **Related feature docs:** [media-viewer.md](../../features/media-viewer.md), [post-thumbnails.md](../../features/post-thumbnails.md), [external-link-handling.md](../../features/external-link-handling.md)

## Problem

A Lemmy post whose URL points at a video-host **page** — e.g. `https://streamable.com/67295820` —
currently opens in the browser. Spud only recognizes video by file extension
(`.mp4` / `.mov` / `.m4v`), so a streamable URL (an HTML page, not a video file) falls
through `PostContentDetectorService` to `.externalLink` and is routed to Safari/the system
browser by `AppService.open(url:)`.

The playback infrastructure already exists: `presentVideoPlayer(url:)`
(`Spud/.../UIViewController+VideoPlayer.swift`) wraps `AVPlayerViewController` and is already
used for direct-file video posts. The gap is **resolution** — turning a host page URL into a
directly-playable stream URL — not playback.

Streamable is a good first host because it exposes a public API
(`GET https://api.streamable.com/videos/{shortcode}`) that returns a direct H.264/AAC `mp4`
URL plus a poster and title, and that mp4 plays natively in AVFoundation. This is unlike
YouTube (no clean direct-stream API), which is why the existing `VideoLinkParser` /
`YouTubeReference` layer only produces enriched previews that still open externally.

## Decisions (agreed during brainstorming)

1. **Scope: a generalized, reusable "resolvable video host" layer**, with **streamable as the
   only concrete host in v1**. The seam is designed so adding a host later is a small, isolated
   addition (append one type). We do NOT implement additional hosts now (YAGNI).
2. **Resolution is lazy.** The feed/detail poster comes from Lemmy's server-provided
   `thumbnail_url` (free, no network). Streamable's API is called only at **tap time** to
   resolve the stream URL — no per-feed-row network calls, no eager poster resolution.
3. **Surfaces: post-as-video only** — a post whose URL is a streamable link becomes a `.video`
   post in the feed and the post-detail header, and plays inline on tap. Streamable links
   embedded in post/comment **body text** are out of scope for v1.

## Architecture

Five pieces. The key structural choice is separating **synchronous recognition** (used by the
pure, sync content detector) from **asynchronous resolution** (the network call, done at play
time).

### 1. Recognition + resolution seam — `SpudDataKit/Services/VideoHost/` (new)

- `VideoHostKind` — enum; `.streamable` for now. The extension point.
- `VideoHostMatch: Equatable, Sendable` — `{ kind: VideoHostKind, identifier: String, pageUrl: URL }`.
  `identifier` is the host-specific handle (streamable shortcode). Value type so it can ride
  inside `PostContentType` (which must stay `Equatable`).
- `ResolvedVideo: Equatable, Sendable` — `{ streamUrl: URL, posterUrl: URL?, title: String? }`.
- `VideoHostRecognizing` — **sync, pure**: `func recognize(_ url: URL) -> VideoHostMatch?`.
- `VideoHostResolving` — **async**: `func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo`.
- `VideoHostRegistry` — implements both protocols by iterating an ordered list of concrete
  hosts; `recognize` returns the first match, `resolve` dispatches on `match.kind`. Adding a
  host = appending one conformer. A shared default instance is exposed for production use.
- `StreamableVideoHost` — the one concrete host:
  - **recognize:** host is `streamable.com` or `www.streamable.com`; path is a single
    shortcode segment `/{shortcode}`, or the embed forms `/e/{shortcode}` and `/o/{shortcode}`.
    Shortcode is alphanumeric. Tolerates trailing slash and query string. Returns
    `VideoHostMatch(.streamable, identifier: shortcode, pageUrl: originalURL)`; returns `nil`
    for the bare host, multi-segment paths, or other hosts.
  - **resolve:** `GET https://api.streamable.com/videos/{shortcode}`; decode
    `{ status, title, thumbnail_url, files: { "mp4": { url }, "mp4-mobile": { url } } }`.
    Require ready `status` (streamable uses `2` for ready). Prefer `files.mp4.url`, fall back
    to `files["mp4-mobile"].url`. Normalize protocol-relative URLs (`//cdn…` → `https://cdn…`).
    Missing/removed video (HTTP 404) and not-ready status throw a typed error. The network call
    goes through an injectable session/transport so tests can stub the JSON without hitting the
    network.

### 2. Content classification — `PostContentType` + `PostContentDetectorService`

`PostContentType.Video` today assumes `videoUrl` is directly playable. Make the playback
source explicit so a resolvable host page is distinguishable from a direct file:

```swift
public struct Video: Equatable {
    public enum Source: Equatable {
        case direct(url: URL)                   // existing: an mp4/mov/m4v file, played as-is
        case resolvable(match: VideoHostMatch)  // new: a host page, resolved to a stream at play time
    }
    public let source: Source
    public let thumbnailUrl: URL?               // server-provided poster (Lemmy thumbnail_url)
}
```

`PostContentDetectorService` gains an injected `VideoHostRecognizing` (default: the shared
`VideoHostRegistry`). Detection order becomes: image extensions → direct-video extensions →
**host recognition** → external link. A `streamable.com/{shortcode}` URL becomes
`.video(.resolvable)`; a direct `.mp4` stays `.video(.direct)`; everything else is unchanged.

Touched by the `Source` change: existing readers of `Video.videoUrl` (the post-list view model's
`.video` mapping and the direct-play call sites). These are mechanical updates to read
`video.source`.

### 3. Playback flow — one shared app-side helper (DRY)

Extend `UIViewController+VideoPlayer.swift` with a single helper both the post list and the
post-detail header call, so the resolve/loading/fallback logic exists once:

- `.direct(url)` → `presentVideoPlayer(url:)` immediately (unchanged behavior).
- `.resolvable(match)`:
  1. Show a lightweight loading indicator (streamable resolution is typically sub-second).
  2. `try await resolver.resolve(match)` off the main actor.
  3. **Success** → `presentVideoPlayer(url: resolved.streamUrl)` (the existing system player:
     scrubber, full-screen, AirPlay, PiP).
  4. **Failure or offline** → `await appService.open(url: match.pageUrl)`, which falls through
     to the existing `OpenLinkStrategy` (Safari / system browser / offline-with-no-archive
     toast). So the worst case is exactly today's behavior — the user is never stuck.
  5. Cancel the in-flight resolve if the user navigates away before it completes.

### 4. Post-list + detail wiring

`PostListPostViewModel` already maps `.video` to its `Thumbnail.video(posterUrl:videoUrl:)`
display case (poster + centered play indicator). It uses `video.thumbnailUrl` for the poster
(the server thumbnail) for both `.direct` and `.resolvable`. The tap handler routes through the
shared helper in (3) instead of calling `presentVideoPlayer(url:)` directly, so a resolvable
post resolves-then-plays while a direct post plays immediately. The post-detail header uses the
same helper.

### 5. Poster

No host API call is needed for the poster: Lemmy's server fetches OpenGraph metadata for
streamable links and stores `thumbnail_url`, which the feed row and header already display. A
streamable post with no server thumbnail shows the existing "play indicator over placeholder"
treatment (same as a direct video post lacking a poster). We do not resolve streamable's own
`thumbnail_url` in v1.

## Data flow (end to end)

1. Importer stores the post with `url = https://streamable.com/67295820` and the server
   `thumbnail_url`.
2. `PostContentDetectorService.contentTypeForUrl` → `.video(.resolvable(match))`, `thumbnailUrl`
   = server thumbnail.
3. Feed row / detail header render the video treatment (server poster + play indicator). No
   network beyond the thumbnail image load.
4. User taps → shared helper shows a spinner → `VideoHostRegistry.resolve(match)` →
   `StreamableVideoHost` GETs the streamable API → `ResolvedVideo(streamUrl:…)`.
5. Success → `AVPlayerViewController` plays the mp4 inline. Failure/offline → `open(url:)`
   opens the streamable page per the existing link strategy.

## Error handling / fallback

- API 404 / removed video, not-ready status, decode failure, network error, offline: the
  resolve throws; the helper falls back to `AppService.open(url: pageUrl)`. No new error UI —
  it degrades to the current external-link behavior.
- Neither `mp4` nor `mp4-mobile` present in the response → treat as unresolvable → fallback.

## Testing

- **SpudDataKitTests**
  - `StreamableVideoHost.recognize`: URL-shape matrix — `streamable.com/abc`,
    `www.streamable.com/abc`, `/e/abc`, `/o/abc`, trailing slash, query string (positive);
    bare host, `streamable.com/abc/def`, non-streamable host (nil).
  - `StreamableVideoHost.resolve` with a stub transport: ready + `mp4`; protocol-relative URL
    normalization; `mp4-mobile` fallback when `mp4` absent; HTTP 404 / not-ready / neither file
    → typed error.
  - `PostContentDetectorService`: streamable URL → `.video(.resolvable)`; `.mp4` → `.video(.direct)`;
    ordinary link → `.externalLink`; image cases unchanged (regression guard). Inject a fake or
    the real registry.
- **Playback coordinator logic:** extract the resolve→play-vs-fallback decision into a testable
  function; drive it with a fake resolver — success routes to the player URL, failure routes to
  the `open(url:)` fallback. (The `AVPlayerViewController` presentation itself is not
  unit-tested.)
- **SpudSnapshotTests:** a post-list row and a post-detail header for a `.video(.resolvable)`
  post render the video treatment from the server thumbnail (deterministic, no network — reuse
  the existing video-post snapshot pattern and `deterministicPhone`).

## Docs to update (per the three-tier doc discipline)

- `docs/features/media-viewer.md` — "Inline video is a system-player hand-off" gains
  resolvable-host (streamable) behavior + a "Play a streamable video inline" scenario and a
  "resolution failure falls back to the browser" note.
- `docs/features/post-thumbnails.md` — the "Video post" rule: a post is now classified video
  either by playable file extension **or** by a recognized video host (streamable).
- `docs/features/external-link-handling.md` — note streamable is no longer browser-by-default;
  browser is now the fallback when inline resolution fails.
- `docs/features/README.md` — capability table + "Feature coverage by area" map.

## Privacy

`api.streamable.com` is the content's **source host**. Calling it is consistent with the
existing posture of talking to the source rather than a third-party aggregator or Google (same
spirit as the Piped-via-its-own-API handling). No new third-party data leakage is introduced.

## Non-goals (YAGNI)

- No eager poster resolution (server thumbnail only).
- No streamable links inside post/comment body text.
- No additional concrete hosts — the seam ships with streamable only.
- No offline caching/archiving of resolved streams.
- No custom player UI — reuse `AVPlayerViewController`.
- No user setting to toggle inline playback (default on; the browser fallback is the only
  escape hatch, reached on resolution failure).

## Notes / minor edge cases for implementation

- Prefer full `mp4` over `mp4-mobile`; picking by network conditions is deferred (YAGNI).
- If streamable ever returns only HLS (`m3u8`) for a given video, AVPlayer can play it too;
  v1 uses the `mp4`/`mp4-mobile` fields and falls back to the browser if neither is present.
- Streamable is not in the `FrontEndCatalog`, so the URL sanitizer does not rewrite it; the
  recognized `pageUrl` is the original post URL.
