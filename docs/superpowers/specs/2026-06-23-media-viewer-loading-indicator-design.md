# Media viewer: loading indicator while the full-size image fetches

Date: 2026-06-23
Status: approved (design)
Scope: `Spud/Scenes/MediaViewer/ZoomableImageView.swift` (plus a unit test)

## Problem

Tapping a thumbnail (post list, post detail, profile) opens the full-screen
media viewer, which paints the upscaled thumbnail immediately so the user has
something to look at while the full-resolution image downloads. On a slow
connection there is **no indication that the full-size fetch is still in
flight** — the user cannot tell whether they are waiting or the full image is
already shown.

## Root cause

`ZoomableImageView` already owns a `UIActivityIndicatorView`, but `startLoading()`
only starts it when there is no placeholder:

```swift
if item.preloadedImage == nil {
    activityIndicator.startAnimating()
}
```

In the thumbnail-tap case the originating cell hands the viewer a
`preloadedImage`, so `preloadedImage != nil` and the spinner never starts. The
stop-on-`.ready` / stop-on-`.failure` paths are already correct; only the *show*
condition is wrong.

## Decision

Keep the indeterminate `UIActivityIndicatorView` (consistent with the rest of
the app). Change *when* it shows and give it a subtle backing so it reads over a
bright thumbnail. No `ImageService`, `MediaItem`, or transition changes. No
determinate progress bar.

### Behaviour

The indicator's visibility depends only on whether the **final** full-resolution
image has arrived — not on whether a placeholder is on screen — and it is shown
on a short grace delay so fast loads never flash it.

1. **Drop the placeholder gate.** Remove `if item.preloadedImage == nil`.
2. **Grace-delayed show (~0.4s).** On `startLoading()`, arm a `showIndicatorTask`
   that sleeps `gracePeriod` then shows the indicator **only if** the final image
   has not yet arrived (a new `isFinalImageLoaded` flag). `.ready` and `.failure`
   cancel that task and hide the indicator. A memory-cache hit yields `.ready`
   essentially immediately (`ImageService.fetch` short-circuits to a single
   `.ready`), so the grace task is cancelled well before 0.4s — no flash.
3. **Subtle scrim/pill.** Host the spinner in a small rounded container
   (~56pt, corner radius ~14, `black` at ~0.35 alpha) centred on the view, shown
   and hidden together with the spinner. Over the plain black background
   (no-placeholder case) it is nearly invisible — harmless and uniform.
4. **Uniform across paths.** Same behaviour for: no placeholder, thumbnail
   placeholder, and animated GIF (`fetchAnimatedImage`, often large). `deinit`
   cancels the grace task. The indicator carries an `accessibilityLabel`
   ("Loading full image") for VoiceOver.

`gracePeriod` is an injected init parameter defaulting to `.milliseconds(400)`,
so the single existing call site (`MediaViewerPageViewController.swift:21`) is
untouched and tests can vary it.

### Behaviour matrix

| Scenario | What the user sees |
|---|---|
| Full image in memory cache | Thumbnail to full image instantly, no spinner |
| Fast network | Thumbnail to full image, spinner never reaches 0.4s, no flash |
| Slow network | Upscaled thumbnail, spinner appears after ~0.4s on a subtle scrim, hides when the full image lands |
| No placeholder + slow | Black screen, spinner after ~0.4s |
| Failure | Spinner hidden, existing broken-image icon shown |

## Implementation notes

- `startLoading()` no longer calls `activityIndicator.startAnimating()` directly.
  It arms `showIndicatorTask`, which after `gracePeriod` calls a single
  decision method `presentIndicatorIfStillLoading()`.
- `presentIndicatorIfStillLoading()` shows the spinner + scrim **iff**
  `!isFinalImageLoaded`. It is the only code path that starts the spinner.
- `.ready`: set `isFinalImageLoaded = true`, cancel `showIndicatorTask`, hide the
  indicator + scrim (existing image swap unchanged).
- `.failure`: cancel `showIndicatorTask`, hide the indicator + scrim, show the
  broken-image icon when there is no image (unchanged from today).
- Scrim is a sibling subview behind the activity indicator (or the indicator is a
  subview of the scrim container), centred. Z-order: scrollView < scrim+spinner <
  errorImageView. The error icon and spinner never show simultaneously.

## Testing

Deterministic unit tests in `SpudTests` using a controllable `ImageServiceType`
fake (model on the existing `ScriptedImageService` / inline `StubImageService`
patterns). The grace timer is a thin wrapper over the directly-callable seam, so
timing is never slept on in tests.

- **No synchronous flash:** after `startLoading()` (with a `preloadedImage`), the
  indicator is not animating (the grace task has not fired). Deterministic.
- **Shows when grace fires while loading:** with an in-flight (`loadingForever` /
  `loadingThumbnail`) response, calling `presentIndicatorIfStillLoading()`
  directly starts the spinner and shows the scrim.
- **No-op after ready:** with a `.ready` response, `await` the load task, then
  `presentIndicatorIfStillLoading()` is a no-op (spinner stays hidden) — proving
  a cache hit / fast load never shows the spinner.
- **Failure:** with a `.failure` response, `await` the load task; the spinner is
  not animating and the broken-image icon is shown. If grace fired first, the
  spinner is hidden on failure.

No snapshot test — an animated spinner frame is nondeterministic.

Minimal internal test seams (the test target uses `@testable import Spud`):
`presentIndicatorIfStillLoading()`, the load task (to `await` ready/failure
cases), and a read-only "is the loading indicator visible" accessor.

## Out of scope

- Progressive-preview-replacing-a-preloaded-thumbnail (pre-existing; unchanged).
- Determinate / byte-progress indicator.
- Theme-aware (true-black) background colour for the viewer.
