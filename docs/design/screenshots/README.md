# Spud — Screenshots

Captured live from the running app on an iPhone 17 simulator, 1206×2622, status
bar set to 9:41. These show the **implemented** UI as of 2026-06-12. Screens
`01`–`12` were captured as a signed-out guest on `discuss.tchncs.de`; the
signed-in screens (`13`–`19`) were captured signed in as `ddenis@lemmy.world`.

| File | Screen | What it demonstrates |
|---|---|---|
| `01-feed.png` | Post list (dark) | Frontpage "All" feed, thumbnails, vote/comment/age metadata, tab bar |
| `02-account-signed-out.png` | Account (guest) | Designed sign-in CTA; **Lemmy accent** on Log in / Sign up |
| `03-preferences.png` | Settings root | Section list with teal SF Symbol iconography (Safety section hidden when signed-out) |
| `04-general-settings.png` | Settings › General | Default sorts, Swipe Actions entry, external-link handling toggles |
| `05-post-detail.png` | Post detail | Header (title, image, vote arrows, save) + threaded comments with collapse chevron |
| `06-appearance.png` | Settings › Appearance (dark) | **Theme picker** (System/Light/Dark/True Black) + **9-swatch accent grid**, Lemmy selected |
| `07-appearance-light.png` | Settings › Appearance (light) | Same screen, light palette — theme system following System appearance |
| `08-feed-light.png` | Post list (light) | Light-mode feed; demonstrates the theme system end-to-end |
| `09-search.png` | Search | Search bar + designed empty state ("Search posts, communities, and people") |
| `10-site-list.png` | Instance picker | Federated "Choose an instance" list with descriptions + search |
| `11-display-settings.png` | Settings › Display | **Density / Thumbnail position / Text-scale** tokens (the customization core) |
| `12-inbox.png` | Inbox | Segmented Replies/Mentions/Messages + sign-in-gated empty state |
| `13-account-signed-in.png` | Account (signed in) | Own profile header + Saved / Log out footer (Settings lives in its own tab) |
| `14-community.png` | Community page | `!antitrumpalliance`: banner, icon, subscribe button, community-scoped feed |
| `15-person.png` | Person profile | Header (banner, avatar, post/comment counts, bio + link) + Posts/Comments tabs with content |
| `17-composer.png` | New post composer | Community picker, title, Text/Link/Image type, attach image, Write/Preview toggle, markdown body, NSFW |
| `18-dm-thread.png` | DM thread | Private-message chat: incoming (gray) + outgoing (accent) bubbles + message input & send |
| `19-media-viewer.png` | Media viewer | Full-screen image on black with close / share / save chrome (pinch-zoom & pan, swipe-to-dismiss) |

## Not captured

- **Subscriptions sidebar** (would have been `16`) — **genuinely unreachable on iPhone.**
  It's the split-view primary column, shown only at regular width (iPad / landscape). On
  iPhone portrait the feed replaces the back button with the compose button (which disables
  the interactive pop gesture), re-tapping the tab doesn't pop to root, and the app is
  portrait-locked — so there's no entry point. Capture on an iPad if it's needed.
- Still out of scope this pass (built, see `../FEATURES.md`; need more setup): Comment
  composer, Registration, Account switcher, Blocked-lists.

## Recapture

```sh
# Build + install + launch
cd Spud && xcodebuild -project Spud.xcodeproj -scheme Spud -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/DerivedData -skipPackagePluginValidation -skipMacroValidation build
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Spud.app
xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --cellularBars 4
xcrun simctl launch booted info.ddenis.Spud
xcrun simctl io booted screenshot docs/design/screenshots/01-feed.png
```

> Note: `idb` tap automation is broken in this environment (Python 3.14 asyncio),
> so these were driven with `cliclick` coordinate taps against the Simulator
> window. Accessibility-tree navigation will return once `idb` is fixed.
