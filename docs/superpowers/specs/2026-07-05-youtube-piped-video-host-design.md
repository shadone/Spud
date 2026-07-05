# YouTube-via-Piped inline playback (video host #3) — design

- **Date:** 2026-07-05
- **Status:** approved, pending implementation plan
- **Area:** SpudDataKit video-host seam (new host + config wiring); app (`playVideo`, `AppService`); SpudDataKitTests; docs
- **Builds on:** the shipped video-host seam (streamable + PeerTube). See [2026-07-05-inline-video-host-playback-design.md](2026-07-05-inline-video-host-playback-design.md) and [2026-07-05-peertube-video-host-design.md](2026-07-05-peertube-video-host-design.md).
- **Related feature docs:** [media-viewer.md](../../features/media-viewer.md), [post-thumbnails.md](../../features/post-thumbnails.md), [external-link-handling.md](../../features/external-link-handling.md)

## Problem / goal

Watch YouTube videos inline **without the client ever contacting Google's CDN**, by resolving
the stream through the user's Piped front-end. Piped is a privacy front-end whose `/streams/<id>`
API returns an HLS master playlist and progressive streams that can be **proxied through the
Piped instance**, so `googlevideo.com` is never contacted directly. This is the highest-value
remaining host (YouTube is the most common video link on Lemmy) and was deferred from the
streamable/PeerTube work precisely for this privacy handling.

## Privacy invariant (non-negotiable)

**Never hand `AVPlayer` a `googlevideo.com` URL.** Only Piped-*proxied* streams are ever played.
If a playable, proxied stream cannot be produced, **refuse and fall back to the browser** — we
never leak the client (IP / request) to Google. The browser fallback already routes a YouTube
URL through the URL sanitizer to the user's chosen front-end.

## Decisions (agreed during brainstorming)

1. **Piped only** (not Invidious — a separate future host). Recognize `youtube.com`/`youtu.be`
   and `piped.video`.
2. **Instance selection respects the user's front-end choice.** A raw `youtube.com` link is
   resolved via Piped only when the user's selected YouTube front-end (in Privacy settings) is a
   cataloged Piped instance; a `piped.video` link uses its own catalog apiHost. Otherwise no
   inline playback — browser fallback. No new settings UI (reuses the existing front-end
   preference).
3. **Classification is preference-free (a confirmed, deliberate feed change).** Because the
   content detector lives in SpudDataKit and cannot read the `@MainActor` app-level
   `PreferencesService`, recognition cannot be gated on the preference. So **all**
   `youtube.com`/`piped.video` posts are classified `.video` (poster + play badge) for every
   user. Tapping plays inline for users with a Piped front-end; for others it briefly shows the
   resolving spinner, then opens the browser. (YouTube posts are videos, so the badge is
   reasonable; this is an accepted default change.)

## Architecture

Additive to the seam, but preference-gated, so it touches the app playback path and `AppService`
in addition to the seam.

### 1. `VideoHostKind` gains `.piped`

```swift
public enum VideoHostKind: Equatable, Sendable { case streamable; case peertube; case piped }
```

### 2. `PipedInstanceResolver` — new `SpudDataKit/Services/VideoHost/PipedInstanceResolver.swift`

Pure, sync helper (imports SpudUtilKit for `YouTubeReference`, `YouTubeFrontEndCatalog`,
`URLSanitizerConfig`):

```swift
static func apiHost(forYouTubePageURL url: URL, config: URLSanitizerConfig) -> String?
```
- Extract `YouTubeReference` from `url`.
- `sourceKind == .frontEnd(.piped)` (a `piped.video` page): return
  `YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost`.
- `sourceKind == .youtube` (canonical `youtube.com`/`youtu.be`): if
  `config.redirectToFrontEnds`, `config.setting(for: .youtube).isEnabled`, and the configured
  YouTube front-end host is a cataloged Piped instance, return that instance's `apiHost`; else
  `nil`.
- Anything else → `nil`.

### 3. `PipedVideoHost: SpudDataKit.VideoHost` — new `PipedVideoHost.swift`

Same name-collision caveat as `PeerTubeVideoHost`: the file imports SpudUtilKit (which exports a
`VideoHost` enum), so the conformance is qualified `SpudDataKit.VideoHost`. Holds an injectable
`fetch` and a **Sendable config value snapshot**:

```swift
public struct PipedVideoHost: SpudDataKit.VideoHost {
    public let kind: VideoHostKind = .piped
    private let fetch: @Sendable (URL) async -> Data?
    private let config: URLSanitizerConfig     // Sendable snapshot; used only in resolve
    public init(fetch: @escaping @Sendable (URL) async -> Data? = { … URLSession.shared … },
                config: URLSanitizerConfig = .default) { … }
}
```

- **recognize** (preference-free): extract `YouTubeReference`; for `sourceKind` `.youtube` or
  `.frontEnd(.piped)` return `VideoHostMatch(kind: .piped, identifier: ref.videoId, pageUrl: url)`;
  for `.frontEnd(.invidious)` / `.frontEndShape` return `nil`.
- **resolve** (preference-aware, privacy-safe):
  1. `apiHost = PipedInstanceResolver.apiHost(forYouTubePageURL: match.pageUrl, config: config)`;
     `nil` → throw `.unresolvable` (→ browser fallback).
  2. `GET https://<apiHost>/streams/<videoId>`; `fetch` nil → `.network`; undecodable → `.decoding`.
  3. **Stream tiering** (`playableStreamUrl`): (a) if `hls` present → use it directly (Piped
     already proxies the HLS playlist; adaptive; AVPlayer-native — livestreams and some VOD);
     (b) else the best **progressive muxed** stream (`videoOnly == false`, highest `bitrate`)
     **rewritten through `proxyUrl`** via `PipedProxy.rewrite`; if there is no `proxyUrl` to
     proxy with, throw `.noPlayableFile` (never emit a raw googlevideo URL); (c) else (only
     adaptive video-only + audio-only) → `.noPlayableFile`.
  4. `ResolvedVideo(streamUrl:, posterUrl: thumbnailUrl, title:)`.

  Decoded `Response` (only what we use): `title`, `thumbnailUrl`, `hls`, `proxyUrl`,
  `videoStreams: [{ url, videoOnly, bitrate }]` (all optional).

### 4. `PipedProxy.rewrite` — proxy a googlevideo stream URL through the Piped instance

```swift
static func rewrite(streamURL: String, proxyPrefix: String) -> URL?
```
Take the stream URL (a googlevideo `/videoplayback?…`), swap its scheme+host+port to the Piped
`proxyUrl`'s, keep the path and query, and append `&host=<original-host>` (the standard Piped
proxy convention). The result always points at the proxy host, never the original — upholding
the privacy invariant even defensively. Returns `nil` if either URL can't be parsed. (The plan
pins the exact rewrite against a real Piped `/streams` response.)

### 5. Wiring

- **`VideoHostRegistry`**: keep `init(hosts:)` for tests; add the production default
  `init(pipedConfig: URLSanitizerConfig = .default)` that builds
  `[StreamableVideoHost(), PeerTubeVideoHost(), PipedVideoHost(config: pipedConfig)]`. `VideoHostRegistry()`
  resolves to this, so the detector's registry includes the Piped host (recognition is
  preference-free; its `.default` config is never used because the detector never resolves).
- **`playVideo`**: build the registry with the live config —
  `VideoHostRegistry(pipedConfig: appService.urlSanitizerConfig)`. `playVideo` is `@MainActor`,
  so it reads the config synchronously on the main actor and passes the resulting **Sendable
  value** into the host; `resolve` (nonisolated async) then reads the snapshot with no cross-actor
  hop.
- **`AppServiceType`**: add `var urlSanitizerConfig: URLSanitizerConfig { get }` (`@MainActor`);
  `AppService` returns `preferencesService.urlSanitizerConfig` (it already holds
  `preferencesService`).

### 6. Unchanged

`PostContentType.Video`, `videoPlaybackAction`, `VideoResolvingOverlay`, the five tap sites, and
feed/header rendering. HLS + livestreams play because `AVPlayer` handles `.m3u8`. The
offline-download reclassification comment ("a recognized video-host post (e.g. streamable)")
already covers Piped.

## Data flow

Importer stores the YouTube post URL + server thumbnail → detector (registry incl. Piped)
classifies `.video` (preference-free) → feed/header show the video treatment → tap → `playVideo`
reads the live config, builds a preference-aware registry → `PipedVideoHost.resolve`: if the
user's front-end is Piped (or the link is `piped.video`), fetch `/streams`, pick the proxied
stream, play inline; otherwise (or on any failure) fall back to the browser.

## Testing (SpudDataKitTests)

- **`PipedInstanceResolver`**: `piped.video` → catalog apiHost; `youtube.com` + config with a
  Piped YouTube front-end enabled → that apiHost; `youtube.com` + Invidious front-end → nil;
  `youtube.com` + `redirectToFrontEnds` off → nil.
- **`PipedProxy.rewrite`**: a googlevideo `/videoplayback?…` + proxyPrefix → a URL on the proxy
  host with the path/query preserved and `host=<googlevideo-host>` appended; **assert the result
  host is the proxy, never googlevideo**.
- **`PipedVideoHost.recognize`**: `youtube.com`, `youtu.be`, `piped.video` → match with the
  right `videoId`; an Invidious URL → nil; a non-YouTube URL → nil.
- **`PipedVideoHost.resolve`** via stub fetch + injected config: `hls` present → the hls URL;
  hls absent + progressive muxed + `proxyUrl` → the **proxied** URL (assert proxy host); no
  `proxyUrl` → `.noPlayableFile`; only adaptive (`videoOnly == true`) → `.noPlayableFile`;
  config with no Piped front-end → `.unresolvable`; nil fetch → `.network`; undecodable →
  `.decoding`.
- **`PostContentDetectorTests`**: a `youtube.com` URL → `.video`.

No new tests for `videoPlaybackAction` / `playVideo` (host-agnostic). No new snapshot (renders
through the identical `.video` path).

## Docs

`media-viewer.md` (YouTube-via-Piped plays inline when the user's front-end is a Piped instance;
livestreams supported; privacy note — never contacts Google; browser fallback otherwise),
`post-thumbnails.md` (recognized-host list adds YouTube/Piped, with the note that the badge shows
for all YouTube posts but inline playback is front-end-gated), `external-link-handling.md`
(YouTube inline vs browser), README index.

## Privacy

Reinforces the app's stance: the Piped instance is the user's chosen privacy front-end; streams
are proxied through it; `googlevideo.com` is never contacted. Metadata (`/streams`) is likewise
fetched from the Piped instance, never Google (consistent with the existing preview handling).

## Non-goals (YAGNI)

- No Invidious inline (separate host, separate API).
- No new settings UI — reuses the existing YouTube front-end preference.
- No DASH; no muxing separate adaptive video-only + audio-only streams (rely on `hls` for
  adaptive quality; progressive-muxed otherwise).
- No quality/bitrate picker (pick highest progressive; `hls` self-adapts).
- No playing a raw googlevideo URL under any circumstance (privacy invariant).

## Notes / edge cases for implementation

- The default YouTube front-end is Invidious (`yewtu.be`) and `redirectToFrontEnds` may be off,
  so out-of-the-box a raw `youtube.com` link resolves to `nil` apiHost → browser. `piped.video`
  links always resolve inline (their apiHost is in the catalog).
- The only cataloged Piped instance is `piped.video` (apiHost `pipedapi.kavin.rocks`), which the
  memory notes has 502'd — resolution failure degrades to the browser, as designed.
- `hls` is reliably present for livestreams and enabled on some VOD instances; typical VOD uses
  the proxied progressive path.
