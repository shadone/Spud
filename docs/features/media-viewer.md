# Media viewer and inline video

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Configurable swipe actions](swipe-actions.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Tapping an image in a feed or a post opens a full-screen viewer you can pinch- and
double-tap-zoom, pan, and swipe down to dismiss. Multi-image posts page side to side with
dots, and a tap toggles a top bar with close, share, and save-to-Photos controls. Animated
GIFs play, and save or share with their animation intact. Tapping a playable video
(mp4 / mov / m4v) opens the system video player inline; formats the device can't play
(such as webm) open in the browser instead.

## Behavior and rules

- **Full-screen, cross-dissolve presentation.** The viewer is presented modally over the
  current screen with a cross-dissolve fade (`MediaViewerTransition`); the status bar is
  hidden while it is up. Reduce Motion collapses the fade to an instant cut.
- **Zoom.** Each image fits aspect-fit at minimum zoom. Pinch zooms; double-tap toggles
  between fitted and zoomed (centred on the tapped point); a second double-tap returns to
  fit. Maximum zoom is at least 3x the fitted size and never below the image's native
  resolution. The image stays centred while it is smaller than the screen.
- **Pan.** When zoomed in, dragging pans the image within the scroll view. When not zoomed,
  a downward drag is claimed by swipe-to-dismiss instead.
- **Swipe down to dismiss.** A downward, mostly-vertical drag (only when the image isn't
  zoomed) drags the image with your finger and fades the black backdrop proportionally to
  how far you've dragged. Releasing past a distance or velocity threshold carries the image
  off-screen and dismisses; a shorter drag springs back into place.
- **Auto-hiding bar.** A single tap toggles a blurred top bar (close / share / save) and,
  for multi-image posts, the page dots. The bar hides automatically while you drag to
  dismiss.
- **Gallery paging.** A post with more than one image pages horizontally; page dots show
  position and current page, and are hidden for a single image.
- **Alt text.** When a media item carries alt text, an "Image description" pill appears above the page dots; tapping it opens a sheet showing the full description. The pill fades with the chrome and is absent for items without alt text. (VoiceOver: the pill is actionable.)
- **Instant first frame.** When the originating cell or header already has the image (or a
  thumbnail) loaded, the viewer paints it immediately, then loads full resolution behind it
  — a thumbnail is shown first and replaced by the full image when it arrives.
- **Low-resolution-preview indicator.** When the full-resolution image *fails* to load but a
  preview (the thumbnail shown as the first frame) is on screen, the viewer keeps the preview
  and shows a non-blocking "Showing low-resolution preview" pill rather than replacing it with
  the broken-image icon — so an offline or failed full-res load still shows the thumbnail with a
  clear note that it's degraded. The pill is informational only (no tap / retry), and it fades
  with the rest of the chrome when you tap to hide the bar. The broken-image icon still appears
  when there is nothing to show at all (no preview to fall back to). (VoiceOver: the pill reads
  "Showing low-resolution preview" with a hint that the full-resolution image is unavailable.)
- **Animated GIFs play.** A GIF (detected from the `.gif` extension) is decoded frame-by-frame
  (`AnimatedImageDecoder`) and played in the viewer, not shown as a flat frame.
- **Save and share preserve animation.** For a still image, share offers the decoded image
  and save writes it to Photos. For an animated GIF, both use the original GIF bytes
  (`ImageService.animatedImageData`, written to a temporary `.gif` for sharing) so the
  recipient or the Photos library gets the animation, not a flattened frame.
- **Save asks for permission once.** Save requests add-only Photos access if undetermined;
  if denied it shows an alert offering to open Settings. Success and failure are confirmed
  with haptics.
- **Inline video is a system-player hand-off.** Tapping a playable video presents
  `AVPlayerViewController` and starts playback; the system player supplies the scrubber,
  full-screen, AirPlay, and Picture-in-Picture controls. Only AVFoundation-playable
  containers (mp4 / mov / m4v) are treated as video.
- **Recognized video hosts play inline.** A post whose link is a recognized video-host page
  (streamable.com, a PeerTube instance, or a loops.video short) is treated as a video post: it
  shows the video treatment in the feed and the post-detail header (using the server-provided
  thumbnail as its poster), and tapping it resolves the host page to its stream and plays it
  inline in the system player. A brief spinner is shown while it resolves. PeerTube is recognized
  by URL shape (it is federated, with no host list), so a rare non-PeerTube link may be treated as
  a video and, on tap, fall back to the browser when the instance API does not confirm it.
  loops.video (`loops.video/v/<shortcode>`, the Pixelfed team's short-video platform) resolves
  through loops.video's own public API — no proxy, first-party like streamable and PeerTube;
  a still-processing loops video (no stream yet) falls back to the browser.
  YouTube links (`youtube.com`/`youtu.be`/`piped.video`) play inline **through the user's
  Piped front-end** — the stream is fetched from the Piped instance and served via its proxy,
  so Google's servers are never contacted. This works only when the user's YouTube front-end
  (Privacy settings) is a Piped instance; otherwise the post opens in the browser. Livestreams
  are supported (HLS).
- **Host resolution failure falls back to the browser.** If a recognized host cannot be
  resolved to a playable stream (offline, removed video, or an API error), tapping opens the
  original page with the normal link flow (in-app Safari, the system browser, or the offline
  toast) instead of a dead player.
- **Unplayable video falls back to the browser.** A link whose extension AVFoundation can't
  decode (such as webm or mkv) is classified as an external link, not a video, so it opens
  in the browser rather than a dead player.
- **NSFW privacy screen.** When any item in the viewer is NSFW, the viewer registers as sensitive content for the duration of its presentation, so the screen is hidden in the app-switcher snapshot and from screen captures.

## Scenarios

### Open an image full-screen

- **Given** a post with an image, in a feed or in the post detail
- **When** I tap the image
- **Then** it opens full-screen over a black backdrop with a fade-in
- **And** a single tap toggles the close / share / save bar

### A full-res image that can't load shows a low-res-preview pill

- **Given** an image I have already seen as a thumbnail, opened full-screen while the full-resolution image can't load (e.g. offline)
- **Then** the viewer keeps showing the thumbnail with a "Showing low-resolution preview" pill, not the broken-image icon
- **And** the pill fades away with the rest of the chrome when I tap to hide the bar

### Pinch and double-tap to zoom

- **Given** an image open in the viewer
- **When** I double-tap it
- **Then** it zooms in centred on the tapped point
- **And** double-tapping again returns it to fit; pinch zooms freely between

### Pan a zoomed image

- **Given** an image zoomed past its fitted size
- **When** I drag it
- **Then** the image pans within the frame instead of dismissing

### Swipe down to dismiss

- **Given** an un-zoomed image in the viewer
- **When** I drag down and release past the threshold
- **Then** the image rides off-screen, the backdrop fades to clear, and the viewer closes
- **And** a short drag that I release springs the image back and keeps the viewer open

### Page through a multi-image gallery

- **Given** a post with several images
- **When** I open it and swipe sideways
- **Then** it pages to the next image and the page dots update to the current page
- **And** a single image shows no dots

### Animated GIF plays and saves as a GIF

- **Given** a post whose image is an animated GIF
- **When** I open it
- **Then** it plays the animation
- **And** tapping save writes an animated GIF to Photos (and share shares an animated `.gif`), not a flattened frame

### Save asks for Photos permission

- **Given** Photos add-access has not yet been granted
- **When** I tap save
- **Then** the app requests add-only access, and saves on grant
- **And** if access is denied it offers to open Settings instead

### Play a video inline

- **Given** a post linking to an mp4, mov, or m4v
- **When** I tap it
- **Then** the system video player opens and starts playing, with scrubber, full-screen, AirPlay, and Picture-in-Picture controls

### Play a streamable video inline

- **Given** a post whose link is a streamable.com video
- **When** I tap it
- **Then** a brief spinner shows while the video resolves, then it plays inline in the system player

### A streamable video that can't resolve opens in the browser

- **Given** a streamable post that is offline, removed, or fails to resolve
- **When** I tap it
- **Then** it opens the streamable page in the browser instead of a dead player

### Play a loops.video short inline

- **Given** a post whose link is a `loops.video/v/<shortcode>` short
- **When** I tap it
- **Then** a brief spinner shows while it resolves through loops.video's API, then it plays inline in the system player (a still-processing loops video opens in the browser instead)

### An unplayable video opens in the browser

- **Given** a post linking to a webm (or other container the device can't decode)
- **When** I tap it
- **Then** it opens in the browser, not in the video player

## Not supported / out of scope

- The viewer is for images and GIFs only — video is never shown inside it; video is a
  separate system-player hand-off.
- The present/dismiss transition is a cross-dissolve, not a matched-geometry zoom from the
  source thumbnail.
- webm and mkv are not played in-app; AVFoundation cannot decode them, so they are routed to
  the browser as external links.
- Inline video-host playback covers streamable, PeerTube, loops.video, and YouTube-via-Piped.
  The whole YouTube family — youtube.com/youtu.be, Piped, Invidious front-ends, and the bare
  `/watch?v=<id>` shape on unknown hosts — is recognized as video (play badge and play
  affordance), but plays inline only when the user's YouTube front-end is a Piped instance;
  otherwise the original page opens in the browser (an Invidious link is never resolved via
  the Invidious instance itself, and is never rerouted through Piped unless the user chose
  Piped). Google's servers are never contacted for playback — if a
  proxied stream can't be produced, the video opens in the browser instead. A post whose own
  link is a streamable, PeerTube, or loops.video video always plays inline. A streamable or PeerTube link written inside
  post or comment **body text** also plays inline when tapped in the post-detail screen — its
  external-link handling re-runs video detection — while on other screens (a community or
  person description, direct messages) a body-text link opens in the browser.
- Save targets the Photos library only; there is no "save to Files" or other destination.
- Zoom tops out at a fixed maximum (at least 3x fit, never below native resolution); there
  is no unbounded zoom.
- There is no slideshow, no thumbnail strip, and no swipe-up-for-info — paging is the only
  gallery navigation, shown as plain page dots.
