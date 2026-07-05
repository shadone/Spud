# Alternative YouTube link wrappers — design

- Date: 2026-07-05
- Status: Draft (awaiting review)
- Area: SpudUtilKit (URL sanitizer + markdown video parsing), SpudDataKit (LinkEmbed), Spud (Preferences UI)

## Motivation

On Lemmy, YouTube videos are frequently posted through alternative privacy front-ends
rather than as canonical `youtube.com` links. The reference case is
[HexReplyBot](https://hexbear.net/comment/7274923), which replies to any YouTube post
with the same video on several front-ends:

- `https://yewtu.be/watch?v=<id>` — Invidious
- `https://inv.nadeko.net/watch?v=<id>` — Invidious
- `https://yt.artemislena.eu/watch?v=<id>` — Invidious
- `https://piped.video/watch?v=<id>` — Piped

Every one of these carries a real 11-character YouTube video id in `?v=`. Spud should
treat them as first-class YouTube videos: show a good preview, and (opt-in) let the
user normalize them to their chosen front-end.

### Current behavior and its gaps

`VideoLinkParser` already recognizes a non-YouTube `/watch?v=<yt-id>` link by *shape*
and classifies it as Invidious, resolving thumbnail + title from the link's own host.

1. **Piped degrades.** Piped shares the `/watch?v=` shape, so it is mis-classified as
   Invidious. But a Piped frontend host serves neither `/vi/<id>/hqdefault.jpg` nor
   `/oembed`, so the card shows a broken thumbnail and no title.
2. **No cross-front-end rewrite.** The front-end redirect only recognizes
   `youtube.com`/`youtu.be` as sources, so an Invidious link cannot be re-pointed to the
   user's preferred front-end (e.g. "open Invidious links in Piped").
3. **`youtu.be` rewrite is grammar-broken (latent).** `FrontEndRewriteStep` does a naive
   host-swap preserving the path, so `youtu.be/<id>` → `<frontend>/<id>` produces an
   invalid Invidious/Piped URL (they expect `/watch?v=<id>`).
4. **`/shorts/` and `/live/` are unrecognized.** No preview, not rewritable.

## Decisions (locked with the user)

1. Improve **both** the preview card and the front-end rewrite.
2. Recognize front-end hosts with a **curated catalog + shape fallback** (hybrid): a
   built-in list of known instances (tagged Invidious vs Piped, Piped carrying its API
   host), with today's `/watch?v=` shape heuristic retained as a best-effort fallback for
   unknown hosts so nothing regresses.
3. Previews are **privacy-first**: never contact Google for a front-end link. Invidious
   keeps today's per-instance oEmbed + thumbnail. **Piped is resolved via its own
   `/streams/<id>` API** (title + `thumbnailUrl`). Unknown Piped-shaped hosts (not in the
   catalog) degrade to a clean card with no thumbnail/title — still no Google.
4. **Include** YouTube's own `/shorts/<id>` and `/live/<id>` forms in the extractor.
5. Add a **`rewriteThirdPartyFrontEnds`** preference (default **off**) that gates whether
   links *already on* a third-party front-end are normalized to the user's chosen
   front-end. Canonical `youtube.com`/`youtu.be` rewriting keeps today's behavior
   regardless of this flag.

## Architecture

All new pure logic lives in **SpudUtilKit** (the lowest layer, alongside the existing
`VideoLinkParser` and `URLSanitizer`). No new cross-layer dependencies.

### 1. `YouTubeReference` — the shared id extractor (new, SpudUtilKit)

The single source of truth both features consume. Pure, side-effect free.

```
enum YouTubeFrontEndKind { case invidious, piped }

struct YouTubeReference: Equatable, Sendable {
    let videoId: String            // canonical 11-char YouTube id
    let sourceHost: String         // lowercased host it was found on
    let sourceKind: SourceKind     // .youtube | .frontEnd(YouTubeFrontEndKind) | .frontEndShape
    let timestampSeconds: Int?     // parsed &t= / #t= where present, for rewrite
}

enum YouTubeReference.SourceKind: Equatable, Sendable {
    case youtube                             // youtube.com family or youtu.be
    case frontEnd(YouTubeFrontEndKind)       // host is in YouTubeFrontEndCatalog
    case frontEndShape                       // unknown host, matched by /watch?v= shape only
}

extension YouTubeReference {
    static func extract(from url: URL) -> YouTubeReference?
}
```

`extract` recognizes, in order:

- YouTube family (`youtube.com`, `www.`/`m.`/`music.youtube.com`, `youtube-nocookie.com`):
  `/watch?v=<id>`, `/embed/<id>`, `/shorts/<id>`, `/live/<id>`, `/v/<id>`.
- `youtu.be/<id>` (sole path segment).
- `redirect.invidious.io` `/watch?v=` and `/embed/<id>` → `.youtube` (existing special case).
- A host present in `YouTubeFrontEndCatalog`: `/watch?v=<id>` or `/embed/<id>`,
  producing `.frontEnd(kind)`.
- Any other host with `/watch?v=<11-char-id>` → `.frontEndShape` (Invidious best-effort,
  matching today's behavior).

Id validation is the existing rule: exactly 11 chars of `[A-Za-z0-9_-]`.

### 2. `YouTubeFrontEndCatalog` — curated instances (new, SpudUtilKit)

```
struct YouTubeFrontEndInstance: Sendable {
    let host: String                  // lowercased frontend host, e.g. "piped.video"
    let kind: YouTubeFrontEndKind
    let apiHost: String?              // Piped API host (kind == .piped only), e.g. "pipedapi.…"
}

enum YouTubeFrontEndCatalog {
    static let instances: [YouTubeFrontEndInstance]
    static func instance(forHost host: String) -> YouTubeFrontEndInstance?   // strips www./m.
}
```

Seed (built-in; not user-editable in v1 — like `FrontEndCatalog`'s default hosts, this
list rots and is maintained in code):

- Invidious: `yewtu.be`, `inv.nadeko.net`, `yt.artemislena.eu` (+ room for common others).
- Piped: `piped.video` with its published API host.

The exact Piped `apiHost` values are seeded during implementation from the official
Piped instances list (each instance publishes its API URL; it is **not** derivable from
the frontend host). Documented as maintenance-prone.

### 3. Preview: `VideoLinkParser` + `VideoLink` + `LinkEmbedService`

- `VideoHost` gains `case piped`.
- `VideoLink` replaces the bare `oEmbedURL: URL?` with an explicit metadata source so the
  fetcher knows how to decode:

  ```
  enum VideoLink.MetadataSource: Equatable, Sendable {
      case oEmbed(URL)          // YouTube, Invidious, PeerTube (existing decode)
      case pipedStreams(URL)    // https://<apiHost>/streams/<id>
      case none
  }
  ```

- `VideoLinkParser.parse` delegates YouTube/front-end recognition to `YouTubeReference`:
  - `.youtube` and `redirect.invidious.io` → `.youtube`, thumbnail `i.ytimg.com`,
    `.oEmbed(youtube.com/oembed?url=canonicalWatch)` (unchanged).
  - `.frontEnd(.invidious)` and `.frontEndShape` → `.invidious`, thumbnail
    `<host>/vi/<id>/hqdefault.jpg`, `.oEmbed(<host>/oembed?url=…)` (unchanged behavior).
  - `.frontEnd(.piped)` → `.piped`, thumbnail `nil` (comes from the API response),
    `.pipedStreams(<apiHost>/streams/<id>)`.
  - Unknown Piped-shaped hosts do not exist as a concept — a host is only "Piped" if it is
    in the catalog. Piped-looking-but-uncataloged hosts fall to `.frontEndShape`
    (Invidious best-effort); if their `/oembed` fails the card degrades cleanly (no Google).
  - PeerTube unchanged.
- `LinkEmbedService.embed(for:)` switches on `MetadataSource`:
  - `.oEmbed(url)` → existing `OEmbedResponse` decode.
  - `.pipedStreams(url)` → decode Piped's `{ "title", "thumbnailUrl" }`; use both.
  - `.none` → derived thumbnail only.
  The existing `fetchLinkEmbeds` preference still gates all network fetches.

### 4. Rewrite: `FrontEndRewriteStep` (SpudUtilKit)

Add a YouTube-specific branch ahead of the generic host-swap loop. Other services
(Twitter/Reddit/Imgur) keep the generic host-swap (their front-ends share the source's
path grammar).

```
if config.redirectToFrontEnds, youtube setting isEnabled & host non-empty,
   let ref = YouTubeReference.extract(from: url):
     // .youtube always eligible; front-end sources only when the new flag is on.
     let eligible = (ref.sourceKind == .youtube) || config.rewriteThirdPartyFrontEnds
     if eligible:
         return https://<youtubeSetting.host>/watch?v=<ref.videoId>[&t=<seconds>]
```

- Grammar-correct for every combination (fixes gap #3): id is extracted and re-emitted as
  `/watch?v=`, which canonical YouTube, Invidious, and Piped all accept.
- `rewriteThirdPartyFrontEnds` off → only `.youtube` sources rewrite (today's scope).
- Idempotent: a link already on the chosen host rebuilds to itself.
- Subordinate to the existing gates (`isEnabled`, `redirectToFrontEnds`, youtube service
  enabled) — the new flag never rewrites on its own.

### 5. Config: `URLSanitizerConfig` (SpudUtilKit)

- Add `var rewriteThirdPartyFrontEnds: Bool`, default `false` in `.default` and the
  memberwise `init`.
- **Backward-compatible decode:** the config is synthesized `Codable` and persisted as
  JSON via `@UserDefaultsBacked`; a new non-optional key would fail to decode configs
  written before this change and silently reset the user's other settings. Add a custom
  `init(from:)` (or `decodeIfPresent ?? false` for this key) so old JSON still loads.
  Covered by a migration/decoding test.

### 6. Preferences UI: `PreferencesPrivacyView` + `PreferencesViewModel` (Spud)

- Add a `Toggle` in the **Front-ends** section, below "Redirect to Front-ends":
  *"Rewrite Third-Party Front-ends"* with footer *"Also re-point links that are already on
  a front-end (e.g. open Invidious links in your chosen front-end)."*
- Disabled unless `redirectToFrontEnds` is on (it has no effect otherwise).
- `PreferencesViewModel` gains `updateRewriteThirdPartyFrontEnds(_:)` mirroring the
  existing `updateRedirectToFrontEnds` pattern.

## Data flow

**Preview** (unchanged surface): body markdown → `commentLinkPreviews` / header →
`VideoLinkParser.parse` (now via `YouTubeReference`) → `.video` card →
`LinkEmbedService.embed` resolves title/thumbnail per `MetadataSource` → `LinkPreviewCardFactory`.

**Rewrite** (on tap / open): `URLSanitizer.sanitize` pipeline → `FrontEndRewriteStep`
YouTube branch extracts id and rebuilds on the chosen host → open-mode logic.

The two surfaces are independent: the preview parses the URL *as posted*; the rewrite acts
on the *outbound* URL when the user opens it. No ordering coupling.

## Privacy invariants

- A front-end link (Invidious/Piped/uncataloged front-end shape) never triggers a request
  to Google (`i.ytimg.com`, `youtube.com`). Invidious → its own instance; Piped → its own
  API; uncataloged → best-effort Invidious oEmbed or graceful degrade.
- Canonical `youtube.com`/`youtu.be` previews keep contacting Google as today (no change).
- All preview fetches remain gated by the existing `fetchLinkEmbeds` (“Load Link
  Previews”) preference.

## Edge cases

- `?v=` present but id not 11 valid chars → not a video link (unchanged).
- `youtu.be/<id>/extra` → rejected (id must be the sole segment, unchanged).
- Timestamp: parse `t`/`start` query or `#t=` fragment to seconds; re-emit as `&t=<sec>`
  on rewrite. If absent, omit.
- `/embed/<id>` on a front-end host → recognized; rewrite normalizes to `/watch?v=`.
- Chosen youtube front-end host is itself Piped while resolving a preview: preview uses the
  *posted* link's host/kind, independent of the rewrite target — no interaction.

## Testing

- `YouTubeReferenceTests` (SpudUtilKit): every form (watch/embed/shorts/live/v, youtu.be,
  Invidious catalog host, Piped catalog host, uncataloged shape, redirect.invidious.io),
  timestamp parsing, and negatives (short id, non-video paths).
- `VideoLinkParserTests`: extend for Piped classification (`.piped`, `.pipedStreams` URL,
  nil derived thumbnail) and that Invidious/YouTube outputs are unchanged.
- `FrontEndRewriteStepTests`: `youtu.be` → chosen host `/watch?v=` (grammar fix);
  Invidious → Piped and Piped → Invidious gated by `rewriteThirdPartyFrontEnds`; canonical
  YouTube unaffected by the flag; idempotence; disabled-when-gates-off.
- `URLSanitizerConfig` decode test: old JSON without the key loads with the flag `false`
  and preserves other fields.
- `LinkEmbedServiceTests`: Piped `/streams` decode via the injected `fetch` stub yields
  title + thumbnail; failure degrades cleanly.

## Documentation

- `docs/features/external-link-handling.md`: update the "Redirect to Front-ends" and "Load
  Link Previews" descriptions to cover Piped and cross-front-end rewrite; add Given/When/Then
  scenarios (Piped preview enriched; Invidious→Piped rewrite when the toggle is on; toggle
  off leaves front-end links unchanged).
- `docs/features/README.md`: reconcile the capability table + by-area map if wording changes.

## Non-goals / out of scope

- User-editable recognition catalog (the *target* host stays editable via `FrontEndConfig`;
  the recognition list is built-in for v1).
- Piped preview for uncataloged Piped instances (no derivable API host → graceful degrade).
- Resolving previews through a proxy Invidious instance (considered; rejected in favor of
  Piped's own API per the locked privacy decision).
- Non-YouTube services (Twitter/Reddit/Imgur) — untouched; keep host-swap.
