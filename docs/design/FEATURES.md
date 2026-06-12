# Spud — Feature List

Status legend: **Shipped** (built + verified) · **Partial** (partial/stub) · **Deferred** (not started / deferred)

Derived from the implemented source under `Spud/Scenes`, `SpudUIKit`, and the
project milestone log (M0–M6 + M8 shipped; M7 push and M9 submit
outstanding).

---

## Reading & feeds

| Feature | Status | Notes |
|---|---|---|
| Frontpage feed (All / Local / Subscribed) | Shipped | Sort: Active, Hot, New, Top (by range), Most Comments |
| Community-scoped feed | Shipped | Below the community header |
| Saved feed | Shipped | Saved posts list |
| Pull-to-refresh | Shipped | Every feed surface |
| Infinite scroll | Shipped | Footer spinner; fetches at ~90% scroll, cursor-based pagination |
| Inline thumbnails (text/link/image/video) | Shipped | Smart per-content layout |
| GIF badge / video play indicator on thumbnails | Shipped | `MediaBadgeView` |
| External-link embed thumbnail | Shipped | Shows embed image, opens the post |
| Context-menu peek on posts | Shipped | Long-press → image + title + body |
| Mark-as-read (on interact / on scroll) | Shipped | Preference-driven |
| Hide read posts (immediately / on refresh) | Shipped | Preference-driven, live filtering |
| Configurable swipe actions (posts) | Shipped | upvote/downvote/save/reply/share |

## Posts & comments

| Feature | Status | Notes |
|---|---|---|
| Post detail with header + comment tree | Shipped | |
| Upvote / downvote post & comment | Shipped | Haptic on commit; confirm-then-mirror |
| Save / unsave post & comment | Shipped | |
| Threaded comment collapse (tap / swipe) | Shipped | Depth rails + "+N" child badge |
| Jump to next top-level comment | Shipped | Floating button, animated |
| Reply to post / comment | Shipped | Markdown composer sheet |
| Edit / delete own comment | Shipped | |
| Per-comment swipe actions | Shipped | Configurable |
| Context menu (vote/save/reply/report/block/delete) | Shipped | |
| Comment sort | Shipped | Preference-driven |
| Share post / comment / community URL | Shipped | |
| Open post in Safari | Shipped | |

## Media

| Feature | Status | Notes |
|---|---|---|
| Full-screen image viewer | Shipped | Pinch/double-tap zoom, pan |
| Multi-image gallery paging | Shipped | Page dots |
| Swipe-down-to-dismiss | Shipped | Proportional backdrop fade |
| Save / share from viewer | Shipped | Animated GIFs preserved as GIF |
| Animated GIF playback | Shipped | `AnimatedImageDecoder` |
| Inline video (mp4/mov/m4v) | Shipped | System AVPlayer; webm → browser |

## Discovery

| Feature | Status | Notes |
|---|---|---|
| Search posts / comments / communities / users | Shipped | Scoped, debounced |
| Inline subscribe from search | Shipped | Community/user results |
| Subscriptions sidebar | Shipped | SwiftUI; feeds + saved + communities |
| Subscribe / unsubscribe community | Shipped | Reflects live in sidebar |
| Community screen (header + feed) | Shipped | Banner, icon, about, subscribe, mod-aware |
| Person / user profile (posts + comments) | Shipped | Header + segmented tabs |

## Account & auth

| Feature | Status | Notes |
|---|---|---|
| Multi-account, multi-instance | Shipped | Keychain credential per account |
| Account switcher | Shipped | Live app-wide switch |
| Signed-out browsing (anonymous) | Shipped | Bootstrap account on first run |
| Login (username/email + password) | Shipped | |
| Two-factor (2FA) login | Shipped | Field appears on demand |
| Instance picker (site list) | Shipped | Searchable |
| Registration / signup | Shipped | Handles application + email-verify states |
| Sign-in gate on write actions | Shipped | "Sign in to …" + warning haptic |

## Inbox & messaging

| Feature | Status | Notes |
|---|---|---|
| Inbox: replies / mentions / messages | Shipped | Segmented |
| Unread badge on tab | Shipped | Live |
| Mark read / mark-all-read | Shipped | Swipe + button |
| Private message threads | Shipped | Chat bubbles + input bar |
| Send DM | Shipped | |
| Background-refresh unread counts | Shipped | App Refresh task, no server |

## Content creation

| Feature | Status | Notes |
|---|---|---|
| New post: text / link / image | Shipped | Community picker, NSFW flag |
| Image upload (pict-rs) | Shipped | Hand-written multipart, unit-tested |
| Markdown editor + formatting toolbar | Shipped | bold/italic/code/quote/link |
| Markdown live preview | Shipped | Write/Preview toggle |
| Draft persistence | Shipped | Per target |

## Safety & moderation

| Feature | Status | Notes |
|---|---|---|
| Block / unblock person & community | Shipped | |
| Blocked-list management | Shipped | Swipe-to-unblock in Settings |
| Report post / comment | Shipped | |
| Moderator / admin actions | Shipped | Gated by site capability |

## Customization & settings

| Feature | Status | Notes |
|---|---|---|
| Themes: System / Light / Dark / True Black (OLED) | Shipped | Live |
| Accent color (9 options, Lemmy default) | Shipped | Live, app-wide tint |
| Post density (Comfortable / Compact) | Shipped | Live cell reconfigure |
| Thumbnail position (Left / Right / Hidden) | Shipped | Live |
| Text scale (−3…+6) | Shipped | Live |
| Default post / comment sort | Shipped | |
| External-link handling (Safari/in-app/reader/universal) | Shipped | |
| Configurable swipe actions (posts + comments) | Shipped | |
| Selectable app icons (5 variants) | Partial | Picker UI present; icon switching not wired |
| Acknowledgements (third-party licenses) | Shipped | |
| App logs viewer + storage size + export backup | Shipped | |
| Server-side user settings sync | Deferred | App-local only (`save_user_settings` TODO) |

## Platform

| Feature | Status | Notes |
|---|---|---|
| iPad + landscape split-view handoff | Shipped | Detail survives collapse/expand & rotation |
| Designed empty / error / loading states | Shipped | Across scenes |
| Accessibility: Dynamic Type, VoiceOver, Reduce Motion | Shipped | incl. `LinkLabel` per-link a11y |
| Home-screen widget (top posts) | Shipped | `SpudWidgetExtension` |
| "Open in Spud" share/action extension | Shipped | Routes Lemmy URLs via deep link |
| Push notifications | Deferred | Deferred to v1.1 (needs a relay server) |
| App Store submission (screenshots, metadata, privacy URL) | Deferred | M9 — outstanding |
