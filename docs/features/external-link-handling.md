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
- **Settings testing area.** The Links section footer has a normal link and a universal link that, when tapped, route through the same open path so you can verify your settings without leaving Settings.
- **This governs external links only.** Opening the post's own page on its instance (the "open in browser" action) always uses an in-app Safari view; that is part of [sharing.md](sharing.md), not this preference.

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

### Try a link from Settings

- **Given** the Links section testing area
- **When** I tap its sample link
- **Then** it opens through the same path the current settings define

## Not supported / out of scope

- The two modes are In-App Safari and the system default browser; there is no third-party-browser chooser beyond what the system resolves.
- Reader Mode and Open in Apps apply to the in-app Safari mode; in system-browser mode the OS handles routing.
- Opening a post's own instance page ("open in browser") is fixed to an in-app Safari view and is documented in [sharing.md](sharing.md).
- Deep links that route into Spud itself (from the share/action extension) are a separate concern, not this external-link preference.
