# Media viewer: Live Text

Date: 2026-07-31
Status: approved, not implemented

## Goal

Offer iOS's Live Text in the full-screen media viewer: when an image contains
text, the system's Live Text button appears over the photo, and tapping it lets
the user select, copy, translate, look up, and share the text — plus tap phone
numbers, addresses, and URLs baked into the image.

## Decisions

Four decisions were settled during brainstorming; the rejected alternatives are
recorded so they are not relitigated.

1. **Automatic, Photos-style — not an app-drawn toggle.** The image is analyzed
   once loaded, and the system draws its own Live Text button when text is
   found. Rejected: a `text.viewfinder` button in the glass top bar (duplicates
   a control iOS already draws, and sits in the wrong place — the system button
   is bottom-trailing over the image); always-on selection with no button
   (undiscoverable, and fights the viewer's gestures hardest).

2. **`preferredInteractionTypes = [.textSelection, .dataDetectors]`.** Rejected:
   `.automaticTextOnly` (would make a URL in a screenshot inert text rather than
   a tappable link — considered because a data-detector tap bypasses Spud's URL
   sanitizer and in-app-Safari preference with no delegate hook to intercept it,
   but the gap is narrow: it only applies to text rendered inside an image, the
   user must deliberately tap, and iOS previews the link before opening);
   `.automatic` (adds subject lift and Visual Look Up — beyond "recognize text",
   and subject lift's long-press is another gesture in a crowded viewer). Both
   remain one-line changes if wanted later.

3. **The Live Text button is part of the chrome.** It fades in and out with the
   top bar and page dots via `setSupplementaryInterfaceHidden(_:animated:)`, so
   the viewer still opens as a clean, undecorated photo and one tap reveals
   close / share / save *and* the Live Text button together. Rejected: an
   always-visible button (destroys the clean-photo state that is the point of a
   full-screen viewer); hiding it while zoomed (bespoke rule nobody expects,
   and it flickers during pinch).

4. **Analyze the full-resolution image only.** A thumbnail or degraded preview
   is never analyzed; when full-res replaces a preview, any in-flight analysis
   is cancelled and re-run on the better pixels. OCR quality is the whole point.

Additional settled behavior: animated GIFs are skipped (Live Text on a moving
image is a flat frame that stops matching what is on screen); analysis is lazy
per page in a multi-image gallery, triggered when a page becomes current, not
for every page upfront; analysis is fully on-device, so it adds no privacy
surface even for NSFW images.

## Architecture

A single new class, `LiveTextController` (`Spud/Scenes/MediaViewer/`), owns one
`ImageAnalysisInteraction` and the `ImageAnalyzer` call for one image view.
`ZoomableImageView` holds a controller and feeds it images; it gains no VisionKit
knowledge of its own. This is an app-layer UI concern — nothing goes into
`SpudDataKit`, so the layer/dependency direction is unchanged.

The analyzer sits behind a small protocol seam, `ImageTextAnalyzing`:

```swift
protocol ImageTextAnalyzing: Sendable {
    static var isSupported: Bool { get }
    func analyze(_ image: UIImage, configuration: ImageAnalyzer.Configuration) async throws -> ImageAnalysis
}
```

The seam is load-bearing rather than decorative: `ImageAnalyzer` is expected to
report unsupported on the Simulator, so without it the feature would be both
untestable in CI and invisible during development.

Attachment points:

- **`ZoomableImageView`** — creates the controller, hands it the *final* image
  (skipping animated items), and exposes `hasInteractiveItem(at:)` and
  `setLiveTextButtonHidden(_:animated:)` upward.
- **`MediaViewerPageViewController`** — gains an `isCurrentPage` flag; setting it
  true is what triggers analysis, which is what makes analysis lazy per page.
- **`MediaViewerViewController`** — sets `isCurrentPage` on initial display and
  in `didFinishAnimating`, mirrors chrome visibility onto the current page's
  button, and consults `hasInteractiveItem(at:)` in its two existing
  gesture-delegate methods.

## Data flow

`ImageService` yields `.ready(image)` → `ZoomableImageView.setImage(isFinal:
true)` → the controller stores the image → if the page is current and the item
is not animated, an analysis task starts. The result is assigned to
`interaction.analysis`, the interaction is added to the image view, and button
visibility is synced to the current chrome state.

The interaction is installed on the `UIImageView` inside the scroll view, so
text highlights zoom and pan with the image for free. The image view's frame is
set to the image's pixel size (`configureZoomScales`), so no
`contentsRect(for:)` delegate work is needed.

## Gesture arbitration

Two additions to the delegate methods already in `MediaViewerViewController`,
alongside the existing alt-text-pill rule:

- `gestureRecognizer(_:shouldReceive:)` — refuse the chrome-toggling single tap
  when the touch lands on an interactive item (live text, or the Live Text
  button itself).
- `gestureRecognizerShouldBegin(_:)` — refuse the swipe-to-dismiss pan when it
  begins on an interactive item, or while a text selection is active.

Double-tap zoom and horizontal paging are untouched.

## Error handling

Every failure mode degrades to the same outcome — no Live Text button —
silently: unsupported device, analysis throwing, cancellation, or no text found.
None is a user-facing failure; the absence of the button *is* the correct UI.
Failures log at debug level only. This does not warrant a `DiagnosticLog` event:
it is neither a durable lifecycle event nor something a user would report.

## Accessibility

`ImageAnalysisInteraction` adds its button as a subview of the view it is
installed on, and that view (`ZoomableImageView`'s `imageView`) is currently
`isAccessibilityElement = true` with the label "Image", which hides descendants
from VoiceOver. A naive attachment therefore makes the Live Text button
VoiceOver-unreachable.

Plan: when the interaction becomes active, clear `isAccessibilityElement` on the
image view and carry the image's own description on a dedicated invisible
full-frame subview, so VoiceOver traverses image-description, then Live Text
button. The `mediaViewerImage` accessibility *identifier* is unaffected, so
existing UI tests keep passing.

This is the least certain part of the design. It cannot be fully verified in the
Simulator and needs a real device with VoiceOver before the feature is called
done. If the invisible-subview approach misbehaves, the fallback is to leave the
image view as the accessibility element and surface recognized text as a custom
accessibility action instead — a worse experience, but not a broken one.

## Testing

Unit tests (SpudTests, Swift Testing, fake analyzer):

- no analysis when the analyzer reports unsupported
- no analysis for an animated item
- no analysis before the page becomes current
- analysis on the final image once the page is current
- in-flight analysis cancelled and re-run when full-res replaces a preview
- analysis cancelled when the page is no longer current
- button visibility follows the chrome's visibility

Gesture arbitration tests follow the existing `MediaViewerGlassButtonsHitTestTests`
pattern, against a fake interaction seam: the single tap is refused over an
interactive item and allowed elsewhere; the dismiss pan is refused over an
interactive item and while a selection is active.

No snapshot tests: the button is system-drawn and will not render in the
Simulator.

**On-device verification is owed and cannot be skipped.** If Live Text is
Simulator-unsupported as expected, the feature is inert there, and a green test
suite proves only that the plumbing is correct — not that text is recognized,
that the button appears where expected, or that selection coexists with paging
and swipe-to-dismiss in the hand.

## Documentation

`docs/features/media-viewer.md` gains the behavior and its Given/When/Then
scenarios; both `docs/features/README.md` index sections are updated (the
capability table and the coverage-by-area map).

## Out of scope

- Subject lift and Visual Look Up (decision 2).
- Live Text anywhere outside the full-screen media viewer — not in feed
  thumbnails, post-detail headers, or inline body images.
- Live Text on video frames.
- Any app-drawn UI for text recognition; all of it is system-supplied.
- Routing data-detector taps through Spud's URL sanitizer — VisionKit provides
  no hook for it.
