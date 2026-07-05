# PeerTube as the second video host — design

- **Date:** 2026-07-05
- **Status:** approved, pending implementation plan
- **Area:** SpudDataKit video-host seam (additive host); SpudDataKitTests; docs
- **Builds on:** [2026-07-05-inline-video-host-playback-design.md](2026-07-05-inline-video-host-playback-design.md) (the streamable-first seam, now shipped)
- **Related feature docs:** [media-viewer.md](../../features/media-viewer.md), [post-thumbnails.md](../../features/post-thumbnails.md)

## Problem / goal

The video-host seam shipped with streamable as its only concrete host, but was explicitly
designed so more hosts can be added by appending one type to `VideoHostRegistry`. This adds
**PeerTube** as the second host, proving the extension point and giving federated-native
PeerTube video posts inline playback.

PeerTube is a good second host: it is common on Lemmy, it is the content's own source (talking
to the instance API honours the "source host, not a third-party aggregator" posture), and it
exercises the seam's async network-resolution path on a structurally different API than
streamable. It also validates the seam against a **heuristic** recognizer (PeerTube is
federated — no host allowlist is possible).

## Decisions (agreed during brainstorming)

1. **Second host is PeerTube.** (YouTube-via-Piped is deferred: its streams are Google CDN and
   would need proxying to honour the privacy posture — a separate, larger effort.)
2. **Recognition reuses `VideoLinkParser`** (SpudUtilKit) — the single existing PeerTube
   heuristic (`/w/<id>` and `/videos/watch/<uuid>` with `isPeerTubeId`), rather than
   duplicating it. A rare non-PeerTube `/w/<id>` post may be badged as video in the feed and,
   on tap, fall back to the browser after the resolve fails — the same graceful degradation the
   body-link preview cards already accept. Coverage over precision (the common modern PeerTube
   share URL is the short `/w/<id>` form, so dropping it would gut coverage).
3. **Lazy resolution, server-thumbnail poster** — unchanged from streamable: the feed/header
   poster is the Lemmy server `thumbnail_url`; the instance API is called only at tap time.

## Architecture

This is purely additive. Because both `PostContentDetectorService` (classification) and
`UIViewController.playVideo` (playback) resolve hosts through `VideoHostRegistry()`, adding one
host to the registry wires PeerTube into classification and playback at once — with no change
to `PostContentType.Video`, `videoPlaybackAction`, `playVideo`, `VideoResolvingOverlay`, the
five tap sites, or any feed/header rendering.

### 1. `VideoHostKind` gains a case

```swift
public enum VideoHostKind: Equatable, Sendable {
    case streamable
    case peertube
}
```

### 2. `PeerTubeVideoHost: VideoHost` — new `SpudDataKit/Services/VideoHost/PeerTubeVideoHost.swift`

Conforms to the existing `VideoHost` protocol (recognize + resolve + `kind`). Holds an
injectable `fetch: @Sendable (URL) async -> Data?` defaulting to `URLSession.shared`, exactly
like `StreamableVideoHost`.

**Name collision (must handle):** SpudUtilKit exports a public enum also named `VideoHost`
(`.youtube/.invidious/.piped/.peertube`), used by `VideoLinkParser`. This file imports
SpudUtilKit for `VideoLinkParser`, so the unqualified name `VideoHost` is ambiguous. Resolve by
qualifying the protocol conformance as `SpudDataKit.VideoHost`; the enum case `.peertube` on a
`VideoLink.host` value resolves by context. A one-line comment documents this. (Renaming
SpudUtilKit's enum is out of scope — it would be an unrelated churn across the markdown/preview
code.)

- **recognize** (sync, pure) — delegate to the existing heuristic:
  ```swift
  public func recognize(_ url: URL) -> VideoHostMatch? {
      guard let link = VideoLinkParser.parse(url), link.host == .peertube else { return nil }
      return VideoHostMatch(kind: .peertube, identifier: link.videoId, pageUrl: url)
  }
  ```
  `VideoLinkParser.parse` tries YouTube/Invidious/Piped first and only then the PeerTube shape,
  so YouTube-family URLs yield a non-`.peertube` host and are correctly not claimed by this host.

- **resolve** (async) — call the instance's REST API on the SAME host as the page URL:
  `GET https://<match.pageUrl.host>/api/v1/videos/<identifier>`. Decode the video object and
  choose a playable stream:
  1. Collect progressive mp4 candidates from top-level `files[]` **and** each
     `streamingPlaylists[].files[]` (each candidate = `{ fileUrl, resolution.id }`).
  2. If any candidates: pick the one with the highest `resolution.id`; its `fileUrl` is the
     `streamUrl`.
  3. Else if any `streamingPlaylists[].playlistUrl` (HLS `.m3u8`): use the first — `AVPlayer`
     plays HLS natively.
  4. Else throw `VideoHostResolutionError.noPlayableFile`.

  Poster: `previewPath` (or `thumbnailPath`) is instance-relative → make absolute against
  `https://<host>`; put it in `ResolvedVideo.posterUrl`. Title: `name`. A missing/garbage body
  (a 404, or a non-PeerTube host that matched the `/w/` shape) fails to decode →
  `VideoHostResolutionError.decoding`; `fetch` returning nil → `.network`. All resolution
  errors are caught by `videoPlaybackAction` and fall back to opening the page in the browser.

  Response shape (only the fields we read; all optional for tolerance):
  ```swift
  private struct Response: Decodable {
      struct Resolution: Decodable { let id: Int? }
      struct File: Decodable { let fileUrl: String?; let resolution: Resolution? }
      struct StreamingPlaylist: Decodable { let playlistUrl: String?; let files: [File]? }
      let name: String?
      let thumbnailPath: String?
      let previewPath: String?
      let files: [File]?
      let streamingPlaylists: [StreamingPlaylist]?
  }
  ```

### 3. Registry wiring — the only integration change

```swift
public init(hosts: [any VideoHost] = [StreamableVideoHost(), PeerTubeVideoHost()]) { ... }
```

### 4. Unchanged

`PostContentType.Video`, `videoPlaybackAction`, `playVideo`, `VideoResolvingOverlay`, the five
tap sites, and all rendering. HLS-only PeerTube videos play because `AVPlayer` handles `.m3u8`.
The offline-download reclassification comment ("a recognized video-host post (e.g. streamable)")
already covers PeerTube.

## Data flow

Identical to streamable: importer stores the post URL + server thumbnail → detector recognizes
via the registry (now including PeerTube) → `.video` with the page URL as `videoUrl` → feed/
header show the server poster + play badge → tap → `playVideo` re-recognizes → resolve via the
PeerTube API → play the mp4/HLS inline, or fall back to the browser on failure.

## Testing

- **SpudDataKitTests / `PeerTubeVideoHostTests`**
  - recognize: `https://tube.example/w/abc123` and `https://tube.example/videos/watch/<uuid>`
    → match with the right `identifier` and `kind == .peertube`; a YouTube URL → nil; a plain
    non-video URL → nil; a too-short `/w/<id>` (< 6, fails `isPeerTubeId`) → nil.
  - resolve via stub `fetch`: (a) top-level progressive `files` → highest-resolution `fileUrl`;
    (b) HLS-only (`streamingPlaylists[].playlistUrl`, empty `files`) → the `.m3u8` playlist URL;
    (c) files nested only under `streamingPlaylists[].files` → highest `fileUrl`; (d) relative
    `previewPath` → absolute poster; (e) `fetch` returns nil → `.network`; (f) undecodable body
    → `.decoding`; (g) decodable but no files and no playlist → `.noPlayableFile`.
- **SpudDataKitTests / `PostContentDetectorTests`**: a PeerTube URL → `.video` (through the
  default registry).
- No new tests for `videoPlaybackAction` / `playVideo` — host-agnostic, already covered.

## Docs

- `media-viewer.md`: the "recognized video hosts play inline" bullet becomes "streamable and
  PeerTube"; note PeerTube's shape-based (heuristic) recognition and that an unrecognized/private
  video falls back to the browser.
- `post-thumbnails.md`: the recognized-video-host classification rule lists PeerTube alongside
  streamable.
- `docs/features/README.md`: extend the existing media/inline-video entries (no new rows).

## Privacy

The PeerTube API is on the video's own instance (`pageUrl.host`) — the content source. No
third-party aggregator or Google is contacted. Consistent with the streamable decision and the
app's stance.

## Non-goals (YAGNI)

- No YouTube/Piped inline playback (deferred; needs privacy-preserving proxying).
- No eager poster resolution (server thumbnail only).
- No HLS bitrate/quality selection — pick the highest progressive `fileUrl`, else the first
  HLS playlist; `AVPlayer` adapts HLS itself.
- No authentication for private/internal PeerTube videos — they fail to resolve and fall back
  to the browser.
- No new hosts beyond PeerTube in this change.

## Notes / edge cases for implementation

- Build the API URL and absolute poster from `match.pageUrl.host`; the identifier is already
  URL-safe (`isPeerTubeId` = word chars + dashes).
- `fileUrl`s from the PeerTube API are absolute; only `thumbnailPath`/`previewPath` are
  instance-relative.
- The `fetch` closure does not surface HTTP status (same as streamable); a 404 body simply
  fails to decode → `.decoding`, which is the correct graceful outcome for a false-positive
  `/w/<id>` match.
