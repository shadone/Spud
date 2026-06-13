# Spud — Design Brief

> A native iOS client for [Lemmy](https://join-lemmy.org), the federated link
> aggregator. This brief is the design source-of-truth for the Spud app: what it
> is, who it's for, the feel it's chasing, and the design system that already
> exists in code. It's written to be imported into Claude Design as the starting
> point for a living design system.

---

## 1. Product at a glance

| | |
|---|---|
| **Name** | Spud (final; was a placeholder) |
| **Platform** | iOS 18+, iPhone + iPad (split view), portrait & landscape |
| **Category** | Social networking |
| **What it is** | A full-featured Lemmy client: read, vote, comment, post, save, subscribe, search, inbox/DMs, moderation |
| **Tech** | UIKit (scenes + coordinators + `@Observable` view models), some SwiftUI (Subscriptions sidebar, all of Preferences), GRDB persistence, AsyncSequence/Observation reactivity |
| **Bundle** | `info.ddenis.Spud` |
| **License** | BSD-2-Clause |

Spud is a single-developer app picked back up in 2026 after a 2024 dormancy. It
is **production-ready as a read + vote + write client** today, tracking toward a
full-parity App Store release.

---

## 2. Who it's for

People who already use Lemmy (or are leaving Reddit for the fediverse) and want a
**native, fast, considered** iOS client — not a web wrapper. They expect the
fluidity and customization of best-in-class Reddit clients and are frustrated by
clients that "work" but feel janky. They value:

- Speed and smoothness above feature-count bragging.
- Deep customization (themes, density, gestures, icons).
- Multi-account, multi-instance federation handled gracefully.
- Privacy and a clean, ad-free, native experience.

---

## 3. The north-star: "Apollo-parity"

**The bar is feel, not feature count.** Every screen is built to be at least on
par with Apollo for Reddit — fluid gestures, instant feedback, deep
customization, refined media. A feature isn't "done" when it works; it's done
when it feels native, fast, and considered.

> The canonical short statement of this bar is [`../DESIGN.md`](../DESIGN.md); this
> section restates it so the brief reads standalone for Claude Design import.

### Non-negotiable feel (applies to every screen)

- **Haptics** on every committal action — vote, save, subscribe, send, collapse.
  Light impact by default; success/warning notifications where they fit.
- **Optimistic-feeling UI** — actions reflect instantly. (The data layer is
  confirm-then-mirror: call the server, then mirror the confirmed response into
  GRDB, which drives the UI via observation. The UI shows pending state
  immediately and never blocks the main thread.)
- **Fluid animations** — spring-based, interruptible; honor Reduce Motion.
- **Fast scrolling** — image prefetch, cell reuse, off-main markdown parsing with
  a cached `NSAttributedString`, target-size image downsampling, off-main bitmap
  decode. Budget: 60/120fps on a feed of 100+ posts.
- **Context menus with previews** on posts (and links/users/communities).
- **Pull-to-refresh** everywhere a feed lives; **infinite scroll** with a tasteful
  footer spinner.
- **Designed empty / error / loading states** — every async surface has all three;
  no blank screens.

### Signature gestures

- **Customizable swipe actions** on post and comment cells — upvote, downvote,
  save, reply, share, collapse — user-configurable, with sensible defaults.
- **Tap- and swipe-to-collapse** comment threads, with a collapsed-child count
  badge and colored depth rails (one hue per depth).
- **Swipe-from-edge back**; **swipe-down-to-dismiss** on the full-screen media
  viewer (backdrop fades proportionally).

---

## 4. Brand & visual identity

- **Motif:** the "potato" (Spud). App icon is a full-bleed potato mark; five
  selectable variants — **Potato (default), Midnight, Forest, Sunset, Mono** —
  are placeholder art on the same motif, to be replaced with final art.
- **Default accent:** **"Lemmy"** — a fixed brand teal/green
  `rgb(0, 150, 135)` ≈ `#009687`, chosen to read well on both light and dark
  without per-mode variants. It is the app-wide `tintColor`.
- **Personality:** friendly and a little playful (the potato, "Hello world :o)"
  in About) over a serious, refined, fast core. Native-first — leans on system
  materials, SF Symbols, and Dynamic Type rather than a heavy custom skin.

---

## 5. Design system (as implemented in `SpudUIKit`)

The design system lives in the `SpudUIKit` framework as typed Swift tokens. This
section is the canonical reference; components in Claude Design should mirror
these tokens exactly.

### 5.1 Theme (appearance)

Four user-selectable themes (`AppTheme`):

| Theme | Interface style | Notes |
|---|---|---|
| **System** | unspecified (follows OS) | icon `circle.lefthalf.filled` |
| **Light** | light | icon `sun.max` |
| **Dark** | dark | icon `moon` |
| **True Black** | dark + pure-black swap | OLED; icon `moon.stars.fill` |

**True Black** is dark mode with the background tokens swapped to pure black
(`#000000`) for OLED displays. It's driven entirely by theme-aware dynamic
`UIColor` providers that resolve at draw time, so flipping the window's
`overrideUserInterfaceStyle` re-resolves every color with no per-view override.

**Semantic background tokens** (`Theme`), each a dynamic color that goes pure
black under True-Black in a dark trait collection, otherwise falls through to the
system color:

| Token | Standard | True-Black (dark) |
|---|---|---|
| `background` | `systemBackground` | `#000000` |
| `secondaryBackground` | `secondarySystemBackground` | `#000000` |
| `tertiaryBackground` | `tertiarySystemBackground` | `#000000` |
| `groupedBackground` | `systemGroupedBackground` | `#000000` |
| `secondaryGroupedBackground` | `secondarySystemGroupedBackground` | `#121212` (white 0.07 — lifted off black so cells stay distinct) |

### 5.2 Accent palette (`AccentColor`)

User-selectable tint. Default is **Lemmy**; the rest are system colors that adapt
per interface style automatically.

| Name | Value |
|---|---|
| **Lemmy** (default) | `#009687` (fixed teal/green) |
| Blue | `systemBlue` |
| Indigo | `systemIndigo` |
| Purple | `systemPurple` |
| Pink | `systemPink` |
| Red | `systemRed` |
| Orange | `systemOrange` |
| Green | `systemGreen` |
| Teal | `systemTeal` |

The active theme + accent are held process-wide in `ThemeManager`; the scene
layer applies `overrideUserInterfaceStyle` and `window.tintColor` on change.

### 5.3 Typography

System San Francisco via **Dynamic Type** throughout — no custom font. Text
honors the user's Dynamic Type size everywhere. Post text additionally responds
to two app-level controls:

- **Text scale** — a relative adjustment, roughly **−3 to +6** points relative to
  the system body size (Display preference).
- **Density font adjustment** — Compact density shaves **−1pt** off post text on
  top of the text-scale preference.

Markdown bodies (posts, comments, bios, community descriptions) are rendered via
**Down** (cmark) into `NSAttributedString`, parsed off the main thread and cached.
Links render through a custom `LinkLabel` that exposes each link range as its own
accessibility element.

### 5.4 Density & layout metrics (`PostDensity`)

Post-list cell density, two modes:

| Metric | Comfortable | Compact |
|---|---|---|
| Cell margin (content inset) | 16pt | 10pt |
| Thumbnail ↔ text spacing | 8pt | 8pt |
| Title ↔ subtitle spacing | 8pt | 4pt |
| Relative font adjustment | 0 | −1pt |

`.comfortable` is the generous default; `.compact` is Apollo's tighter feel,
fitting more posts on screen.

### 5.5 Thumbnail position (`ThumbnailPosition`)

Where the post-list thumbnail sits, or whether it shows at all: **Left**
(default, leading the text), **Right** (trailing), **Hidden** (title + subtitle
take full width). Thumbnails are a fixed ~64pt square, downsampled to that size
before decode.

### 5.6 Iconography

**SF Symbols** throughout. Canonical post-action symbols (`Design.Post`):

- Upvote — `arrow.up`
- Downvote — `arrow.down`
- Save — `bookmark`

Thumbnail placeholders:

- Text post — `text.justifyleft` on a tinted background.
- Broken image — `questionmark.square.dashed`.

Settings pickers use per-option SF Symbols (see Theme/Density/Thumbnail tables
above). Media affordances: a **"GIF" badge** and a **video play indicator** overlay
feed/header thumbnails.

### 5.7 Haptics (`Haptics`)

Shared helper; the generator is prepared immediately before firing to warm the
Taptic Engine and minimize latency. Three entry points:

- `tap()` — light impact, for a discrete committal action (toggle save, vote).
- `success()` — success notification, for an action that completed as intended.
- `warning()` — warning notification, for a rejected/gated action (e.g. a
  signed-out user attempting a write).

### 5.8 Motion

Spring-based, interruptible animations. The "jump to next top-level comment"
floating button animates in/out. The media viewer uses a custom cross-dissolve
transition and a proportional swipe-to-dismiss fade. All motion respects
`UIAccessibility.isReduceMotionEnabled`.

---

## 6. Information architecture

Top-level shell is a **UISplitViewController** (`.doubleColumn`): a primary
column and a secondary post-detail column. On compact width (iPhone portrait) it
collapses to a single navigation stack; on iPad/landscape the detail stays on
screen. Deep links (`info.ddenis.spud://internal/...`, routed in from the
`OpenInAppExtension`) display a post in the detail column.

Primary navigable areas:

```
Spud
├─ Posts            feed (frontpage / community / saved) → Post detail (comments)
├─ Subscriptions    feeds (All / Local / Subscribed) + Saved + your communities
├─ Search           posts · communities · users · comments (scoped, debounced)
├─ Inbox            Replies · Mentions · Messages (DM threads)  ·  unread badge
├─ Account          your profile (posts/comments) · Saved · Settings · Log out
│                   └─ signed-out: Log in / Sign up / Browse anonymously
└─ Preferences      General · Appearance · Display · Marking & Hiding · Accounts
                    Safety (Blocked users/communities) · About
```

Cross-cutting destinations reachable from many places: **Post detail**,
**Community** (header + feed), **Person** (profile), **Composer** (new post /
reply), **Media viewer**, **Login / Site picker / Register**.

---

## 7. Screens (implemented)

Every screen below is **built and working today** unless marked otherwise. See the
per-capability docs under [`../features/`](../features/README.md) for the full feature
list and status.

### Feed & reading

- **Post list** — table feed with sort menu (Active/Hot/New/Top-by-range/Most
  comments), pull-to-refresh, infinite scroll with footer spinner, configurable
  left-swipe actions, mark-read-on-scroll, hide-read filtering, live
  density/thumbnail/text-scale reconfiguration without reload. Inline thumbnails
  for image/link/video/text with GIF badge and video play indicator;
  context-menu peek (image + title + body) on long-press.
- **Post detail** — pinned header (title, body/link preview, vote + save
  buttons, counts) over a collapsible threaded comment tree with colored depth
  rails, tap/swipe-to-collapse + child-count badge, a floating "jump to next
  top-level comment" button, per-comment swipe actions and context menus
  (vote/save/reply/report/block/delete; mod/admin actions gated by site
  capability), reply / save / share / open-in-Safari in the nav bar.

### Media

- **Media viewer** — full-screen, black backdrop, multi-image paging
  (UIPageViewController + page dots), pinch-zoom, double-tap zoom, pan,
  swipe-down-to-dismiss with proportional fade, auto-hiding blur top bar with
  share + save (animated GIFs save/share as animated GIFs, not flat frames).
  Inline video plays in the system AVPlayer.

### Discovery & community

- **Subscriptions** (SwiftUI) — collapsible sidebar: Feeds (All / Local /
  Subscribed), Saved, and your communities (searchable, with subscriber counts).
- **Search** — `UISearchController` with scope (All / Posts / Communities /
  Users / Comments), debounced, per-type result cells; inline subscribe on
  community/user results.
- **Community** — Apollo-style page: banner + icon + name/handle + member count +
  NSFW badge + markdown description + subscribe button, pinned over the
  community's feed; new-post button (sign-in gated) and block-community overflow.
- **Person** — profile header (banner, avatar, display name/username,
  post/comment counts, account age, bio) over a Posts / Comments segmented list;
  block/unblock; pull-to-refresh.

### Account & auth

- **Account** — signed in: your own profile + footer (Saved · Settings · Log out)
  + account switcher. Signed out: Log in / Sign up / Browse anonymously CTA.
- **Account switcher** — modal list of signed-in accounts; add / swipe-to-sign-out;
  switching updates the whole app live.
- **Site list** — searchable Lemmy instance picker.
- **Login** — username/email + password with 2FA field that appears on demand;
  forgot-password link; sign-up link.
- **Register** — username/email/password/confirm + optional application answer +
  NSFW flag; handles pending-application and email-verification states.

### Inbox & messaging

- **Inbox** — segmented Replies / Mentions / Messages; unread highlight + live
  unread tab badge; swipe-to-mark-read; mark-all-read; pull-to-refresh.
- **DM thread** — chat bubbles (left/right), pinned input bar above the keyboard,
  auto-scroll, read-on-open.

### Compose

- **New post composer** (sheet) — community picker, title, type segmented control
  (Text / Link / Image), URL field, image attach via `PHPicker` with upload
  progress (pict-rs), markdown editor with a formatting toolbar (bold, italic,
  code, quote, link) and Write/Preview toggle, NSFW flag.
- **Comment composer** (sheet) — lighter reply surface reused for post and
  comment replies.
- **Community picker** — searchable community list for the composer.

### Settings

- **Preferences** (SwiftUI) — root navigation tree: General (default sorts, swipe
  actions, external-link handling), Appearance (theme + accent grid + app icon),
  Display (density / thumbnail position / text scale, all live), Post Marking &
  Hiding (mark-read on interact/scroll, hide-read live/on-refresh), Accounts,
  Safety (Blocked users / communities — swipe-to-unblock), About (acknowledgements,
  logs, storage size, export backup).

### Known stubs / gaps

- **App Icon picker** — visual layout only; alternate-icon switching not yet wired.
- **Server-side user settings** (`save_user_settings`) — preferences are app-local
  only; not synced to the Lemmy account.

---

## 8. Interaction patterns (reusable)

These patterns recur across screens and should become shared Claude Design
components/specs:

- **Swipe-action set** — up to several configurable slots per cell
  (upvote/downvote/save/reply/share/collapse), with icon + accent-tinted
  background; defaults shippable, user-reorderable.
- **Vote control** — up/down arrows + count, with upvoted/downvoted color state
  and a haptic tap on commit.
- **Status badges** — NSFW / saved / upvoted / downvoted indicators
  (`PostStatusBadge`).
- **Collapsible comment** — depth rail (one hue per depth), tap row / rail to
  collapse, "+N" hidden-child badge.
- **Designed async states** — every list/detail has a matching empty, error
  (with retry/pull-to-refresh), and loading variant.
- **Context-menu preview** — long-press a post for an image + title + body peek.
- **Sign-in gate** — any write entry point a signed-out user taps shows a
  "Sign in to …" affordance + warning haptic instead of a silent no-op.

---

## 9. Accessibility

First-class, not a finishing pass:

- Full **Dynamic Type** everywhere.
- **VoiceOver** labels/traits on every interactive element, including the custom
  `LinkLabel`, which exposes each link range as its own accessibility element.
- Honors **Reduce Motion** and **Increase Contrast**.
- Designed states mean screen-reader users never hit an unlabeled blank.

---

## 10. Performance budget

- 60/120fps scroll on a feed of 100+ posts.
- Markdown parsed off-main and cached as `NSAttributedString`, pre-warmed before
  the diffable snapshot is applied.
- Feed thumbnails prefetched (`UITableViewDataSourcePrefetching`) and downsampled
  to the ~64pt cell size before decode; bitmaps decoded off-main
  (`byPreparingForDisplay`).
- No synchronous disk/DB on the main thread.

---

## 11. How this imports into Claude Design

This brief + the per-capability [`../features/`](../features/README.md) docs + the
`screenshots/` folder are the staging material for a Spud design-system project on
claude.ai/design. Suggested component groups
to build there, each mirroring the tokens in §5:

- **Foundations** — Color (semantic background tokens + accent palette),
  Type (Dynamic Type scale + text-scale/density adjustments), Spacing/Density,
  Iconography (SF Symbol set), Motion, Haptics.
- **Components** — Post cell (×density ×thumbnail-position), Vote control,
  Swipe-action set, Status badges, Comment cell (×depth), Composer + markdown
  toolbar, Community/Person headers, Search result cells, Inbox cells, DM bubble,
  Media viewer chrome, Settings rows.
- **Screens** — the §7 inventory, captured in `screenshots/`.

Once mirrored, the design system can drive iteration ahead of the code, and the
existing `SpudUIKit` tokens stay the implementation contract.
