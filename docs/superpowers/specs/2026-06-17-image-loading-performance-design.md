# Image-loading performance: adopt Nuke behind `ImageServiceType`

**Date:** 2026-06-17
**Status:** Design approved, ready for implementation planning
**Scope:** `SpudDataKit/Services/Image/` and its consumers

## Goal

Make image loading feel instant across every surface of Spud, in service of a
"GREAT, snappy app". Four levers, mapped to the surfaces where they pay off:

| Lever | Surface it helps |
|---|---|
| Persistent disk cache | Warm app relaunch (today caches are memory-only, so relaunch re-downloads everything) |
| Memory accounting fix + pressure eviction | Memory footprint / jetsam on older devices |
| Progressive (incremental) decode | Full-size viewer, post-detail header (big images, currently wait for the whole download) |
| Prefetch dedup/coalescing | Feed scroll (already well-tuned; benefits indirectly) |

## Decisions (locked during brainstorming)

1. **Phased, biggest-win-first.** One design doc, three independently-shippable phases.
2. **Adopt Nuke** (`kean/Nuke`) as the loading/decoding/caching **engine**.
3. **Keep the `ImageServiceType` protocol** and its `AsyncStream<ImageLoadingState>`
   surface. Nuke lives *inside* `ImageService`. No call site changes; the
   `StaticImageService` snapshot-test fake is preserved.
4. **Lightweight signposts** (`os_signpost` / `OSSignposter`) for TTFP and decode,
   always-on, inspected in Instruments. No in-app metrics overlay.

## Current state (baseline)

`ImageService` (`@unchecked Sendable` class) wraps a single `URLSession`
(default config + custom `AppUserAgent` User-Agent) and four `NSCache`s:
`memoryCache` (full decoded), `animatedCache`, `downsampledCache` (keyed by
url + pixel size), `animatedDataCache` (raw GIF bytes). All **in-memory only**.

Public surface (`ImageServiceType`): `fetch(url, thumbnail:)`,
`fetch(url, downsampleTo:)`, `fetchAnimatedImage(url)`, `animatedImageData(url)`,
`imageSize(for:)`. All the streaming methods emit `.loading(thumbnail:)` then
`.ready(image)` / `.failure`.

Strengths already in place: eager off-main decode (`byPreparingForDisplay()`,
`CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceShouldCacheImmediately`),
a thumbnail-race in `fetch(url, thumbnail:)` to paint a low-res preview first,
feed downsample + `UITableViewDataSourcePrefetching` warming the same cache key,
per-cell cancellation, and (just added) a quiet-exit cancellation guard.

Gaps this design closes:
- **No disk cache** and **no URLCache tuning** → warm relaunch re-downloads + re-decodes.
- **No streaming/incremental decode** → the viewer waits for the entire download.
- **Memory accounting bug**: `NSCache` cost is set to `width * height` with a
  "1 byte/pixel" comment, but a decoded `UIImage` is ~4 bytes/pixel, so the
  1 GB `totalCostLimit` actually permits ~4 GB of bitmaps — jetsam territory.

## Architecture

`ImageService` becomes a thin **adapter** over a configured Nuke `ImagePipeline`.
The four `NSCache`s and the hand-rolled fetch/decode are deleted. The class still
conforms to `ImageServiceType` and still returns `AsyncStream<ImageLoadingState>`,
translating Nuke's loading into our event model.

Because the protocol is unchanged:
- All ~18 call sites are untouched.
- `StaticImageService` (the snapshot fake) is untouched → the entire snapshot
  suite remains the primary safety net.

Levers delivered by configuring the pipeline:
- **Disk cache** → Nuke `DataCache`.
- **Memory + eviction** → Nuke `ImageCache` sizes by real bitmap bytes and
  auto-purges on `UIApplication.didReceiveMemoryWarningNotification` and on
  background. The buggy hand-rolled cost accounting is removed entirely.
- **Progressive decode** → `isProgressiveDecodingEnabled` + mapping scans to `.loading`.
- **Prefetch** → Nuke coalesces identical in-flight requests, so the existing
  prefetch tasks (which call `fetch(downsampleTo:)`) dedupe against the cell's
  real fetch automatically. An `ImagePrefetcher` is an optional Phase 3 upgrade.

## Pipeline configuration

Built once in `ImageService.init`:

- **DataLoader** with a custom `URLSessionConfiguration` carrying the
  `AppUserAgent` User-Agent header (preserves the nginx/Cloudflare denylist
  workaround). Wrapped so a non-200 response runs the existing
  `logFailedResponse` diagnostic (Cloudflare-edge vs Lemmy vs pict-rs forensics)
  before the error surfaces.
- **`ImageCache`** (memory, decoded) — Nuke default, sizes by actual decoded
  bytes, self-trims to a fraction of device RAM, auto-evicts on memory pressure.
- **`DataCache`** (disk, encoded) — the new persistence layer.
  `dataCachePolicy = .storeAll` so the **processed (64pt) feed thumbnail** is
  stored encoded on disk, not just the original. Warm relaunch reads the small
  thumbnail straight off disk instead of re-downloading + re-resizing the full
  image. Budget ~200 MB (tunable in Phase 3).

### Multi-process decision

Nuke's `DataCache` is thread-safe but **not** designed for multiple processes
writing the same directory. The app, widget, and share extension are separate
processes. Therefore **each process gets its own `DataCache` rooted in its own
`NSCachesDirectory`** — *not* a shared App-Group cache. This mirrors the current
model (each process already builds its own in-memory `ImageService`), avoids
cross-process corruption, and costs only that the widget re-downloads its handful
of images. A shared App-Group image cache is **explicitly deferred** (would need
a multi-process-safe store; not worth the risk now).

## Per-method mapping (behavior preserved)

| `ImageServiceType` method | Nuke implementation | Preserved behavior |
|---|---|---|
| `fetch(url, downsampleTo:)` | `ImageRequest` with a resize processor; stream to `.ready` | Same downsample target → same cache key the prefetch warms; coalescing dedupes prefetch vs cell |
| `fetch(url, thumbnail:)` | Full-image request; seed `.loading(thumbnail:)` from the thumbnail URL's cached image; progressive scans added in Phase 2 | The "paint something first" story; enriched by progressive decode |
| `fetchAnimatedImage(url)` | Fetch original data via Nuke (now disk-cached), decode with the existing `AnimatedImageDecoder` | GIF playback unchanged; animated path keeps its own decoder |
| `animatedImageData(url)` | Read original bytes from Nuke's data cache (or fetch) | Save/share still gets the original animated bytes |
| `imageSize(for:)` | Keep the small `knownImageSizes` side table, populated from decode results | Post-detail header still reserves layout from the thumbnail's size |

### Error & cancellation mapping

Nuke errors map to `ImageLoadingError` and yield `.failure` + `alertService`,
exactly as today. Nuke request cancellation surfaces as `CancellationError`,
which the existing `Error.isImageLoadingCancellation` guard already treats as a
quiet exit — so the no-spurious-alert behavior carries over unchanged.

## Progressive decode (Phase 2)

Enable `isProgressiveDecodingEnabled` on the pipeline. In `fetch(url, thumbnail:)`,
consume the image task's progressive previews: each scan → `.loading(thumbnail:
partialImage)`, final → `.ready`. Non-progressive sources (PNG, baseline JPEG)
emit no scans, so behavior falls back to the seeded thumbnail + final ready
(identical to today). Only the full-image path opts in; the 64pt feed downsample
does not need it. One pipeline for now; split into separate pipelines only if
profiling shows progressive work adding measurable thumbnail overhead.

## Instrumentation (signposts)

A dedicated `OSSignposter` on the app subsystem (`Bundle.main.bundleIdentifier`,
the same subsystem `Logger.imageService` uses), category `"ImageLoading"`.
Interval signposts around:
- request-begin → first pixel (`.loading` or `.ready`) — TTFP
- decode duration

tagged by surface (downsample / full / animated) via signpost name or metadata.
Also enable Nuke's built-in pipeline signposts. Always-on (os_signpost is
production-safe). Lands in **Phase 1** so the disk-cache win is measurable rather
than assumed.

## Testing

- **Snapshot suite** (`StaticImageService` fake) — unchanged, primary safety net.
- **New unit tests** using a stub `DataLoading` conformance (Nuke's public
  protocol) feeding canned bytes:
  - downsample request → `.ready`
  - non-200 → `ImageLoadingError` + diagnostic logged
  - cancellation → quiet exit (no `alertService` call, no `.failure`)
  - User-Agent header present on the data loader's session config
  - `DataCache` rooted in the per-process Caches dir
  - animated path returns original bytes for share
- Headless build/test keeps `-skipPackagePluginValidation -skipMacroValidation`.

## Phases (each independently shippable)

### Phase 1 — Foundation swap (the big one)
Add Nuke via `project.yml` (XcodeGen), `make project`. Build the configured
`ImagePipeline` (custom-UA DataLoader, per-process disk `DataCache`, Nuke
`ImageCache`). Re-implement every `ImageServiceType` method on it, preserving
all behaviors above. Wire signposts. Delete the four `NSCache`s and the buggy
cost accounting.
**Delivers:** warm relaunch, feed scroll, memory.

### Phase 2 — Progressive decode
Enable progressive decoding; map scans to `.loading(thumbnail:)` in
`fetch(url, thumbnail:)`.
**Delivers:** full-size viewer, post-detail header TTFP.

### Phase 3 — Tuning
Validate TTFP per surface via signposts, tune cache budgets, optionally adopt
`ImagePrefetcher` for lower-priority warm-up.
**Delivers:** polish across all surfaces.

## Risks / open items

- **Nuke × Swift 6 strict concurrency**: SpudDataKit is Swift 6 language mode —
  pin a Sendable-clean Nuke release; use `@preconcurrency import Nuke` if the
  pinned version still warns.
- **First remote SPM dependency** alongside local `LemmyKit`: `project.yml` gains
  a `packages:` remote entry + target dependency; `Package.resolved` will now
  pin Nuke. Headless builds keep the plugin/macro skip flags.
- **Exact Nuke symbols** (progressive previews API, resize processor name,
  `DataCache` init) verified against the pinned version during planning — the
  spec is deliberately conceptual here.
- **Animated GIF**: confirm `AnimatedImageDecoder` still decodes Nuke-fetched
  `Data` (it is just bytes, so expected fine) and that share/save bytes survive.
- **Shared App-Group cache** deferred (multi-process write safety).
- **`isProgressiveDecodingEnabled` is pipeline-wide** — split pipelines only if
  profiling shows thumbnail overhead.
