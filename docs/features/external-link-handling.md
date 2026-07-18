# External link handling

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [sharing.md](sharing.md), [post-detail-and-comments.md](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → General → Links controls how external links from posts and comments open: in an in-app Safari view, or in the system default browser. When the in-app view is chosen, two further options apply — an optional Reader Mode, and an "Open in Apps" toggle that lets an installed app claim the link (a universal link) before falling back to the in-app browser. A testing area in the settings footer lets you try a normal link and a universal link against the current settings.

## Behavior and rules

- **Two open modes:** In-App Safari (an `SFSafariViewController` presented over the current screen) or Safari (handed to the system default browser via `UIApplication.open`). In-App Safari is the default. The picker shows a one-line explanation of the selected mode.
- **Reader Mode (in-app only).** When on, the in-app Safari view is configured to enter Reader automatically if the page supports it. The default is on. It has no effect in system-browser mode.
- **Open in Apps / universal links (in-app only).** When on (the default), tapping a link first asks iOS to open it in an installed app that registered for it (a universal link); only if no app handles it does the in-app Safari view open. With it off, the link goes straight to the in-app Safari view. This check applies in In-App Safari mode; in system-browser mode the link is handed to the OS directly, which applies its own universal-link routing.
- **Same path for link previews.** The in-app Safari view used for context-menu link previews is built with the same Reader-Mode configuration, so previews match the opened result.
- **Load Link Previews (default on).** When on, in-body link preview cards for YouTube, Invidious, Piped, and PeerTube video links fetch a thumbnail and title before displaying — YouTube via Google's oEmbed, Invidious via the instance's own oEmbed, and Piped via its `/streams` API (front-end links are resolved from the front-end itself, never Google). When off, those cards show only the anchor text and host without making any third-party network request. This preference lives in Settings → General → Links and only gates the client-side embed fetch; tapping a card opens the link through the open-mode setting above (except a card pointing at a recognized threadiverse post — the frontend `/c/<community>/p/<id>` form — which resolves in-app through the shared link router instead, even for instances outside the Explorer directory).
- **Settings testing area.** The Links section footer has a normal link and a universal link that, when tapped, route through the same open path so you can verify your settings without leaving Settings.
- **This governs external links only.** Opening the post's own page on its instance (the "open in browser" action) always uses an in-app Safari view; that is part of [sharing.md](sharing.md), not this preference.
- **Recognized video hosts are not opened as links by default.** A streamable.com video post
  is classified as a video and played inline; the browser is only the fallback when inline
  resolution fails. See [Media viewer and inline video](media-viewer.md).
- **YouTube plays inline via Piped when configured.** A YouTube link is classified as a video;
  tapping resolves it through the user's Piped front-end (never Google) and plays inline, or —
  when the front-end isn't Piped or resolution fails — opens in the browser (rewritten to the
  chosen front-end). The opt-in "Play YouTube Videos Inline" toggle (below) adds the default
  cataloged Piped instance as a fallback when no Piped front-end is configured. See
  [Media viewer and inline video](media-viewer.md).

## Privacy & Link Cleaning

Settings → General → Links → "Privacy & Link Cleaning" (PreferencesPrivacyView) runs on every external link before the open-mode logic above applies. It uses a URL sanitizer with configurable steps:

- **Clean Outgoing Links** (master toggle) — when on, enables the pipeline below; when off, all steps are disabled.
- **Strip Tracking Parameters** — removes known tracking parameters (e.g. `utm_*`, `fbclid`) from query strings.
- **Unwrap Redirectors** — follows redirect domains to their real destinations.
- **Upgrade to HTTPS** — rewrites `http://` URLs to `https://` where safe.
- **De-AMP** — converts Google AMP URLs to their canonical forms.
- **Redirect to Front-ends** — routes known sites to privacy-focused front-end instances (e.g. YouTube → Invidious, Twitter → Nitter). Each front-end service has an editable hostname, defaulting to a public instance; services can be individually disabled if an instance fails. Video links are recognized on any wrapper form (`youtu.be`, `/shorts`, `/live`, Invidious, Piped) and rewritten to a grammar-correct `/watch?v=<id>` on the chosen host. A separate "Rewrite Third-Party Front-ends" toggle controls whether links already on a front-end (e.g. Invidious) are re-pointed to your chosen host (e.g. open Invidious links in Piped); when off, only canonical `youtube.com`/`youtu.be` links are rewritten.

The sanitized URL is then passed to the open-mode logic (In-App Safari or system browser).

The same screen carries a separate "Video Playback" section:

- **Play YouTube Videos Inline** (default off) — an explicit opt-in that plays YouTube-family video posts (youtube.com/youtu.be, Invidious front-ends, and the bare `/watch?v=<id>` shape) inline by resolving the stream through the default cataloged Piped instance (piped.video's API), even when no Piped front-end is configured. A configured Piped front-end still takes precedence; video traffic goes to Piped, never to Google; if a stream can't be fetched the post opens in the browser. It is off by default because it routes playback traffic to a third party (Piped) the user didn't otherwise choose — that must be consensual. Unlike the cleaning steps above, it is independent of the "Clean Outgoing Links" master toggle (that switch gates link rewriting, not playback resolution).

## Post & Comment Links

Settings → General → Links also contains two link-generation pickers for the "Open in browser" and "Share" actions on post and comment bodies:

- **Open in Browser** — chooses which instance's URL to open: My Instance (the current account's instance) or Original Instance (the post's original instance).
- **Share** — chooses which instance's URL to copy to the clipboard: My Instance or Original Instance.

See [sharing.md](sharing.md) for the full context of these actions.

## Scenarios

### Open an external link in the in-app browser

- **Given** Open External Links is set to In-App Safari
- **When** I tap a link in a post or comment
- **Then** it opens in an in-app Safari view presented over the screen

### Reader Mode opens articles cleaned up

- **Given** In-App Safari with Use Reader Mode on
- **When** I open a link to an article that supports Reader
- **Then** the in-app Safari view enters Reader automatically

### A universal link opens its app

- **Given** In-App Safari with Open in Apps on, and an app installed that handles the link
- **When** I tap that link
- **Then** the installed app opens it instead of the in-app browser
- **And** a link no app claims falls back to the in-app Safari view

### Open links in the system browser

- **Given** Open External Links is set to Safari
- **When** I tap a link
- **Then** it is handed to the system default browser

### Load Link Previews on — video card shows thumbnail and title

- **Given** Load Link Previews is on
- **And** a post or comment body contains a YouTube, Invidious, or PeerTube link
- **Then** the in-body preview card shows the video thumbnail (with a play badge) and the video title fetched via oEmbed

### Load Link Previews off — anchor text only, no fetch

- **Given** Load Link Previews is off
- **And** a post or comment body contains a video link
- **Then** the in-body preview card shows only the anchor text and the host
- **And** no third-party network request is made to fetch embed metadata

### Try a link from Settings

- **Given** the Links section testing area
- **When** I tap its sample link
- **Then** it opens through the same path the current settings define

### Piped link preview resolves privately via Piped's API

- **Given** Load Link Previews is on
- **And** a comment contains a `piped.video/watch?v=<id>` link
- **Then** the preview card shows the video title and thumbnail fetched from Piped's `/streams` API
- **And** no request is made to Google (`i.ytimg.com` / `youtube.com`)

### Rewrite Third-Party Front-ends on — Invidious link opens in the chosen front-end

- **Given** Clean Outgoing Links and Redirect to Front-ends are on
- **And** the YouTube front-end host is set to `piped.video`
- **And** Rewrite Third-Party Front-ends is on
- **When** the user opens an `yewtu.be/watch?v=<id>` link
- **Then** it opens as `https://piped.video/watch?v=<id>`

### Rewrite Third-Party Front-ends off — front-end links are left alone

- **Given** Redirect to Front-ends is on and Rewrite Third-Party Front-ends is off
- **When** the user opens an `yewtu.be/watch?v=<id>` link
- **Then** it opens unchanged (only canonical youtube.com/youtu.be links are rewritten)

### Play YouTube Videos Inline on — a YouTube post plays inline without a Piped front-end

- **Given** Play YouTube Videos Inline is on
- **And** no Piped YouTube front-end is configured
- **When** the user taps a youtube.com, Invidious, or bare `/watch?v=<id>` video post
- **Then** the stream is resolved through the default cataloged Piped instance and plays inline
- **And** no request is made to Google — the video traffic goes to Piped
- **And** if the stream can't be fetched, the post opens in the browser instead

### Play YouTube Videos Inline off (default) — YouTube posts open in the browser

- **Given** Play YouTube Videos Inline is off
- **And** the user's YouTube front-end is not a Piped instance
- **When** the user taps a YouTube-family video post
- **Then** the original page opens in the browser — playback is never rerouted through a Piped instance the user didn't choose

### A configured Piped front-end takes precedence over the opt-in default

- **Given** Play YouTube Videos Inline is on
- **And** Redirect to Front-ends is on with the YouTube front-end set to a Piped instance
- **When** the user taps a YouTube video post
- **Then** the stream is resolved through the chosen front-end's API, not the catalog default

## Not supported / out of scope

- The two modes are In-App Safari and the system default browser; there is no third-party-browser chooser beyond what the system resolves.
- Reader Mode and Open in Apps apply to the in-app Safari mode; in system-browser mode the OS handles routing.
- Opening a post's own instance page ("open in browser") is fixed to an in-app Safari view and is documented in [sharing.md](sharing.md).
- Deep links that route into Spud itself (from the share/action extension) are a separate concern, not this external-link preference.
