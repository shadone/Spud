# Spud feature documentation

What Spud does **today** — present-tense, shipped, observable behavior. Each file
documents one capability and links back to the plan / design doc that produced it. This
is not a plan, not a design spec, and not developer-internals: those live in
[`../DESIGN.md`](../DESIGN.md)
and the [`../design/`](../design/) bundle.

Each doc is two layers — a skimmable `What it does` header plus a Gherkin-style
`Scenarios` section — so it serves a reader browsing features, an agent reasoning about
correct behavior, and (later) an author deriving XCUITest scenarios.

> **This directory is the authoritative feature index.** It replaces the former
> `design/FEATURES.md` at-a-glance status grid, which has been removed. The
> per-capability docs here are the source of truth for what each feature does; several
> correct behavior the old grid had described inaccurately. The coverage map at the
> bottom lists every capability by area and flags the partials.

## How to add a feature doc

1. Copy `_TEMPLATE.md` to `<capability>.md` (kebab-case, named for the capability, not
   the surface).
2. Document only behavior that has actually shipped. Verify each scenario against real
   source under `Spud/Scenes`, `SpudUIKit`, and `SpudDataKit` before writing it; mark
   unshipped behavior `Status: partial` or put it under `Not supported`, never as present.
3. Tag surfaces from the legend below. The doc-level `Surfaces:` line must equal the union
   of the scenarios' surface tags — every surface listed there has to appear in at least
   one scenario. Don't claim a surface no scenario covers.
4. These are product-feature descriptions for end users (with a sprinkle of technical
   detail), not implementation docs — **do not link to source code** (`.swift`) anywhere,
   including `Related:`. Reference symbols as inline code (`` `HideReadPostsFilter` ``),
   never as links; source links drift as code moves. Link only plans / design docs /
   sibling feature docs, and make each such reference a clickable relative Markdown link
   (e.g. `[mark-read-and-hiding.md](mark-read-and-hiding.md)`), not bare path text.
5. Add a row to the capability table and tick it off the Migration backlog.

## Keeping docs honest

These docs describe shipped behavior, which drifts as code changes. Re-verify a doc
against source after changing a documented feature, and before relying on a doc you
didn't write — confirm each scenario maps to real behavior in `Spud/Scenes` /
`SpudUIKit` / `SpudDataKit`, and check the format rules above (surfaces union, no source
links, present tense). An `/audit-feature-doc`-style command can be added later to
automate this with `file:line` citations.

## Surface-tag legend

Spud is iOS-only. Its surfaces are the shipped targets in `project.yml`.

| Tag | Surface |
|---|---|
| `iphone` | iPhone, compact width — the primary single-column experience |
| `ipad` | iPad, regular width — two-column split views on the Posts tab and (when reading a community) the Communities tab; adaptive layouts for sheets and content-width screens |
| `widget` | Home Screen widget (`SpudWidgetExtension`) — top posts at a glance |
| `share-extension` | "Open in Spud" Safari Web Extension (`OpenInAppExtension`) — rewrites a Lemmy post page to a deep link that opens the post in the app |

## Capabilities

| Capability | Surfaces | Status |
|---|---|---|
| [Configurable swipe actions](swipe-actions.md) | `iphone`, `ipad` | shipped |
| [Marking posts read and hiding read posts](mark-read-and-hiding.md) | `iphone`, `ipad` | shipped |
| [NSFW content visibility and blur](nsfw-content.md) | `iphone`, `ipad` | shipped |
| [Feeds and sorting](feeds-and-sorting.md) | `iphone`, `ipad` | shipped — feed switcher: left-edge back-swipe on iPhone; navbar-title popover on iPad (see [iPad split-view handoff](ipad-split-view.md)) |
| [Feed loading and pagination](feed-loading.md) | `iphone`, `ipad` | shipped — cursor pagination + pull-to-refresh + offline/unreachable/malformed states with retry |
| [Download a feed for offline browsing](offline-download.md) | `iphone`, `ipad` | shipped — choose 100/250/500 posts; predownload posts + comments + images (+ optional linked-page web archives read in an in-app offline reader) from the feed config popover, with progress + cancel; paced + retried requests (back-off on transient/pushback errors) and partial-success (keeps what it got when a page permanently fails) |
| [Post thumbnails and media badges](post-thumbnails.md) | `iphone`, `ipad` | shipped |
| [Post peek (context-menu preview)](post-peek.md) | `iphone`, `ipad` | shipped |
| [Post detail and comments](post-detail-and-comments.md) | `iphone`, `ipad` | shipped — incl. offline-aware comments (truthful failed/offline state with Retry — plus automatic re-fetch when connectivity returns — not a false "no comments yet") + header thumbnail-while-loading with a "Low-res preview" pill |
| [Voting](voting.md) | `iphone`, `ipad` | shipped — incl. offline-aware "we'll send your vote when you're back online" toast |
| [Saving](saving.md) | `iphone`, `ipad` | shipped — incl. offline-aware "we'll save this when you're back online" toast |
| [Replying](replying.md) | `iphone`, `ipad` | shipped — reply + edit + delete/restore own comments, all optimistic + durable (see [Post detail and comments](post-detail-and-comments.md)); composer sheet uses proper medium/large detents on iPad |
| [Sharing](sharing.md) | `iphone`, `ipad` | shipped |
| [Media viewer and inline video](media-viewer.md) | `iphone`, `ipad` | shipped — incl. "Showing low-resolution preview" pill when the full-res image can't load over a thumbnail; recognized video hosts (streamable + PeerTube + YouTube-via-Piped) play inline with browser fallback on resolution failure; YouTube inline requires a Piped front-end configured in Privacy settings |
| [Discover (Community Explorer)](discover.md) | `iphone`, `ipad` | shipped — rails (Starter packs / Trending / Rising / Because you follow / Browse by instance) each with "See all", over a sortable directory + same-name compare (per-variant subscribe) + live network-search fallback; auto-refreshes the directory on open (per Community Data settings); on iPad (regular width) rails render as an adaptive multi-column grid and the directory is width-capped/centered; tapping a community opens it in the two-column reading split |
| [Search](search.md) | `iphone`, `ipad` | shipped — scopes: posts / communities / users / comments (federated) + instances (local directory) |
| [Instance browsing (open an instance in-app)](instance-browsing.md) | `iphone`, `ipad` | shipped — directory hit + live `/api/v3/site` probe (Lemmy + PieFed); non-compatible hosts open in browser; communities fetched live via `/api/v3/community/list` when the directory has none |
| [Communities tab (subscriptions)](subscriptions-sidebar.md) | `iphone`, `ipad` | shipped — first-class tab (was the iPad sidebar); feed shortcuts + Discover entry + subscribed list with favorites pinned, filter + sort |
| [Subscribe / unsubscribe](subscribe-unsubscribe.md) | `iphone`, `ipad` | shipped |
| [Community screen](community-screen.md) | `iphone`, `ipad` | shipped — overflow: subscribe, favorite, mute, block, share; on iPad (regular width) opens as a two-column reading split (see [iPad split-view handoff](ipad-split-view.md)) |
| [Person / user profile](person-profile.md) | `iphone`, `ipad` | shipped — Posts tab renders with the feed cell (vote / save, live state) |
| [Accounts and switching](accounts-and-switching.md) | `iphone`, `ipad` | shipped — signed-in Account tab is a profile header + shortcuts list (Switch account / Saved / Activity / Your posts / Your comments / Log out) |
| [Account Activity](account-activity.md) | `iphone`, `ipad` | shipped — reverse-chronological timeline of everything the signed-in account has done (authored posts + comments, upvoted/downvoted, saved, read, seen, hidden); rows reuse feed/search cells; filter chip bar (7 types); search; day-based grouping; states + pull-to-refresh; infinite scroll; Your posts/Your comments/Activity open it pre-filtered (the Saved row opens the server saved feed); + Summary screen (identity strip, 6 stat tiles, 18-week contribution heatmap with All/Reads/Votes metric picker, extras insights); on iPad (regular width) a two-column split — timeline primary, Summary pinned in the detail column (tapping a row opens it in the detail over Summary; collapse to compact restores the Summary nav button); on iPhone the "Your footprint" rail (default state only: default filters + no search + has content) shows four quick stats and a Summary entry above the timeline |
| [Edit your profile](profile-editing.md) | `iphone`, `ipad` | shipped — display name, bio, avatar + banner (live-preview header, pict-rs upload, remove) + server-synced toggles (scores / bots / read posts / avatars) + default feed; on iPad the live-preview banner is width-capped and centered rather than full-bleed |
| [Signed-out browsing](signed-out-browsing.md) | `iphone`, `ipad` | shipped — signed-out Account tab is a grouped "Browsing anonymously" screen (Reading-from row, Create account / Log in, Settings) |
| [Login](login.md) | `iphone`, `ipad` | shipped — incl. two-factor (TOTP) sign-in |
| [Instance picker](instance-picker.md) | `iphone`, `ipad` | shipped |
| [Registration](registration.md) | `iphone`, `ipad` | shipped |
| [Sign-in gate on write actions](sign-in-gate.md) | `iphone`, `ipad` | shipped |
| [Inbox](inbox.md) | `iphone`, `ipad` | shipped |
| [Marking inbox items read](inbox-mark-read.md) | `iphone`, `ipad` | shipped |
| [Private messages](private-messages.md) | `iphone`, `ipad` | shipped — GRDB-backed (offline-readable) threads + optimistic, durable sending (instant bubble, background retry, failure recovery via Drafts & Outbox); new-message compose (recipient picker) + Markdown bodies |
| [Background unread refresh](background-unread-refresh.md) | `iphone`, `ipad` | shipped — foreground scene refresh (unread badge) + periodic scheduler site-info refresh with persisted exponential back-off and permanent give-up after N=5 consecutive permanent failures |
| [Account provenance and site-info refresh](account-provenance-and-site-refresh.md) | `iphone`, `ipad` | shipped — pending release — ephemeral browse accounts excluded from the recurring sweep; one on-demand site-info fetch on first open; persisted per-site give-up after N=5 permanent failures; self-heals on a successful visit |
| [New post](new-post.md) | `iphone`, `ipad` | shipped; composer sheet uses proper medium/large detents on iPad |
| [Image upload](image-upload.md) | `iphone`, `ipad` | shipped |
| [Markdown editor](markdown-editor.md) | `iphone`, `ipad` | shipped |
| [Draft persistence](draft-persistence.md) | `iphone`, `ipad` | shipped |
| [Drafts & Outbox](drafts-and-outbox.md) | `iphone`, `ipad` | shipped |
| [Block / unblock](block-unblock.md) | `iphone`, `ipad` | shipped |
| [Report](report.md) | `iphone`, `ipad` | shipped |
| [Moderator / admin actions](moderation-actions.md) | `iphone`, `ipad` | shipped |
| [Themes and accent color](themes-and-accent.md) | `iphone`, `ipad` | shipped |
| [Display density and text size](display-density-and-text.md) | `iphone`, `ipad` | shipped |
| [Default sort](default-sort.md) | `iphone`, `ipad` | shipped |
| [External link handling](external-link-handling.md) | `iphone`, `ipad` | shipped |
| [App icon](app-icon.md) | `iphone`, `ipad` | shipped — placeholder art |
| [Acknowledgements](acknowledgements.md) | `iphone`, `ipad` | shipped |
| [Diagnostics and backup](diagnostics-and-backup.md) | `iphone`, `ipad` | shipped |
| [Diagnostics logging](diagnostics-logging.md) | `iphone`, `ipad` | shipped — durable GRDB event log (survives relaunch) + two-tab viewer (Event Log with filter/search/detail/export; System Log OSLog tail with level/category filter + time window) |
| [iPad split-view handoff](ipad-split-view.md) | `ipad`, `iphone` | shipped — Posts two-column split + feed-switcher title popover; Communities two-column reading split; Activity two-column split (timeline primary + Summary detail pinned); adaptive layouts (Discover grid, capped banners, sheet detents) at regular width |
| [Empty, error, and loading states](empty-error-loading-states.md) | `iphone`, `ipad` | shipped |
| [Removed and unavailable posts](removed-unavailable-content.md) | `iphone`, `ipad` | shipped — neutral feed badge + placeholder screen for gone posts; cause-specific copy (ambiguous / removed / deleted); moderator + author bypass; automatic recovery on re-fetch; deep-link resolves to placeholder not spinner |
| [Accessibility](accessibility.md) | `iphone`, `ipad` | shipped |
| [Home Screen widget (top posts)](widget.md) | `widget` | shipped |
| [App Shortcuts, Siri & Spotlight](app-shortcuts-and-siri.md) | `iphone`, `ipad` | shipped — 7 App Intents (incl. Open Saved, Switch Account); Spotlight indexes communities + saved/history posts |
| [Open in Spud (Safari extension)](share-extension.md) | `share-extension`, `iphone`, `ipad` | partial |

<!-- Add new capability docs here as they are written. -->

## Feature coverage by area

Every shipped capability, grouped by area — the coverage map that replaced the legacy
`design/FEATURES.md` grid. `[x]` shipped, `[~]` partial (qualifier inline).

**Reading & feeds**
- [x] Frontpage feed (All / Local / Subscribed) + sort
- [x] Community-scoped feed
- [x] Saved feed (documented in saving.md)
- [x] Pull-to-refresh — main feed (refresh-in-place + toast on failure), inbox, profiles, post detail
- [x] Infinite scroll (cursor pagination)
- [x] Download a feed for offline browsing — "Download for offline" in the feed config popover opens a chooser (100/250/500 posts; optional "save linked web pages") then bulk-saves posts + comments + images into the local store + durable image cache (+ external-link web archives, read offline in an in-app WKWebView reader); progress sheet + cancel; requests are paced and retried with back-off (and back off further on a 429/503), and a page that permanently fails after some pages landed finishes partial rather than aborting; offline, the GRDB-first feed/detail browse from the saved copy (offline-download.md)
- [x] Inline thumbnails (text / link / image / video) + media badges
- [x] Context-menu peek on posts
- [x] Marking posts read / hiding read posts
- [x] NSFW content visibility and blur — hidden by default; server-side filter + client-side discovery gating (Search, picker, Discover); age acknowledgment on first enable; blur overlay (thumbnails, post-detail header, community art) with tap-to-reveal on posts; privacy screen hides NSFW media from the app-switcher snapshot and screen capture; synced to server for signed-in accounts (nsfw-content.md)
- [x] Configurable swipe actions (posts)

**Posts & comments**
- [x] Post detail (header + comment tree); in-body link preview cards (anchor text always; video thumbnail + title when "Load Link Previews" is on; post-header link card uses server-provided title + thumbnail); offline-aware — a failed comment load shows a truthful offline/unreachable/malformed state with Retry (never a false "No comments yet"), and an offline failure re-fetches automatically once connectivity returns, and the header keeps the cached feed thumbnail while the full image loads, falling back to a tappable "Low-res preview" pill when the full image can't load
- [x] Upvote / downvote (post & comment) — offline votes queue with a "we'll send your vote when you're back online" toast
- [x] Save / unsave (post & comment) — offline saves queue with a "we'll save this when you're back online" toast
- [x] Threaded comment collapse + jump-to-next-top-level
- [x] Reply / edit / delete / restore own comments — all optimistic + durable (reply + edit via the content outbox; delete / restore via the mutation outbox)
- [x] Edit / delete / restore your own post — optimistic + durable (edit via the content outbox; delete / restore via the mutation outbox)
- [x] Configurable swipe actions (comments)
- [x] Comment sort — global default (Settings) + in-screen per-post picker (post-detail config popover: Hot / Top / New / Old / Controversial)
- [x] Share post / comment / community URL; open in Safari

**Media**
- [x] Full-screen image viewer (zoom / pan / swipe-to-dismiss) — keeps the preview thumbnail and shows a "Showing low-resolution preview" pill when the full-res image can't load (e.g. offline), instead of the broken-image icon
- [x] Multi-image gallery paging
- [x] Animated GIF playback; inline video — direct mp4/mov/m4v plays via the system player; recognized video hosts (streamable.com, PeerTube instances, YouTube-via-Piped) resolve to their stream and play inline, with browser fallback on resolution failure; YouTube inline requires a Piped front-end in Privacy settings (Invidious and other front-ends open in the browser; Google is never contacted)

**Discovery**
- [x] Discover (Community Explorer) — browsable home in the Communities tab: Starter packs / Trending / Rising / Because you follow / Browse-by-instance rails (each with "See all" into the full ranked list) over a sortable, searchable directory; same-name dedupe + compare sheet (per-variant subscribe); live network-search fallback; long-press quick actions (subscribe, mute, block, share); NSFW + suspicious safety filtering; refreshes the directory from the network on open (per Community Data settings); on iPad (regular width) rails render as an adaptive multi-column grid and the directory is width-capped and centered; tapping a community opens it in the Communities tab's two-column reading split (discover.md)
- [x] Search (posts / comments / communities / users federated, + instances over the local Explorer directory) + inline subscribe + paste-a-Lemmy-URL "Open in Spud" (canonical + frontend `/c/../p/<id>` form)
- [x] Communities tab (subscriptions) — first-class tab on iPhone + iPad (was the iPad-only sidebar); feed shortcuts, Discover entry, subscribed list with favorites pinned, "Search your communities" filter + Alphabetical / By-instance sort
- [x] Subscribe / unsubscribe
- [x] Community screen (header + feed; overflow: subscribe, favorite, mute, block, copy link / share / open in browser)
- [x] Open an instance in-app — tapping an instance name (community header, body link, Search paste, person profile) opens its in-app screen; directory hit is instant, an unknown host is resolved by a live `/api/v3/site` probe (Lemmy + PieFed open in-app, others fall back to the browser); communities come from the bundled directory, or live via `/api/v3/community/list` when the directory has none; session-cached, curated directory untouched (instance-browsing.md)
- [x] Per-account community favorites (local, pinned in the Communities list)
- [x] Person / user profile (Posts tab uses the feed cell — vote / save through the optimistic outbox, live state; Comments tab is the comment-with-context cell)

**Account & auth**
- [x] Multi-account, multi-instance + account switcher
- [x] Account tab — signed-in home: tappable profile header (banner + avatar + display name + handle -> Edit your profile) over a shortcuts list (Switch account, Saved, Activity, Your posts, Your comments, Log out), Settings in the nav bar (accounts-and-switching.md)
- [x] Account Activity — reverse-chronological timeline of posts/comments authored, upvoted/downvoted, saved, read, seen, hidden; rows reuse the feed/search cells; 7-type filter chip bar (funnel reset) with preset filters from Account tab shortcuts (Your posts/Your comments open it pre-filtered; the Saved row opens the server saved feed instead); search; day-based grouping; states (empty/loading/offline/voted-first-run); pull-to-refresh; infinite scroll; + Summary screen (identity strip, 6 stat tiles, 18-week contribution heatmap with All/Reads/Votes metric picker, extras insights); on iPad (regular width) a two-column split with the Summary pinned in the detail column and timeline rows opening their detail over it; on iPhone a "Your footprint" glance rail above the timeline (default filters, no search, has content) showing four quick stats and a Summary entry (account-activity.md)
- [x] Edit your profile — display name, bio, avatar + banner (pict-rs upload; live-preview header mirrors the public person profile; remove clears from the server; no in-app cropping), plus the server-synced account toggles (show scores / bot accounts / read posts / others' avatars) and default feed; saved via `save_user_settings` then refreshed; banner also shown in Account tab header; on iPad the live-preview banner is width-capped and centered rather than full-bleed (profile-editing.md)
- [x] Signed-out browsing (bootstrap account) — signed-out Account tab is a grouped "Browsing anonymously" screen: guest header, Reading-from / change-server row, Create account / Log in, Settings (signed-out-browsing.md)
- [x] Account provenance and site-info refresh (pending release) — browse accounts are flagged ephemeral and excluded from the 5-minute site-info sweep; one best-effort on-demand fetch on first open; persisted per-site exponential back-off + permanent give-up after N=5 consecutive permanent failures; give-up is self-healing (a successful visit resets it); existing browse accounts backfilled on upgrade (account-provenance-and-site-refresh.md)
- [x] Login — incl. two-factor (TOTP) sign-in (code collected and sent; a 2FA-required login auto-prompts for the code)
- [x] Instance picker (site list)
- [x] Registration / signup — shipped (captcha was removed from Lemmy server-side; no in-app captcha solver)
- [x] Sign-in gate on write actions

**Inbox & messaging**
- [x] Inbox (replies / mentions / messages) + unread badge
- [x] Mark read / mark-all-read
- [x] Private message threads — GRDB-backed (offline-readable), with optimistic + durable sending (instant "Sending…" bubble, multiple in flight, background retry, failure recovery in Drafts & Outbox), per-correspondent draft autosave, optimistic conversation-list rows, new-message compose (recipient picker), and Markdown-rendered message bodies
- [x] Background unread-count refresh (foreground scene refresh; not a `BGAppRefreshTask`) + periodic scheduler site-info refresh with persisted per-site exponential back-off (≈5 min doubling → ~2 h cap) and permanent give-up after N=5 consecutive permanent failures (account-provenance-and-site-refresh.md, background-unread-refresh.md)

**Content creation**
- [x] New post (text / link / image) + community picker + NSFW; on iPad the composer sheet uses proper medium/large detents (not a full-screen modal)
- [x] Image upload (pict-rs)
- [x] Markdown editor + toolbar + live preview
- [x] Draft persistence — durable, per-target, auto-saved (survives dismiss / relaunch)
- [x] Optimistic + durable sending — comments inline in the tree, posts via a pending screen, direct messages as inline chat bubbles; background retry with backoff; reply and new-post composer sheets use proper medium/large detents on iPad
- [x] Drafts & Outbox recovery list (failed / sending / drafts; retry / discard)

**Safety & moderation**
- [x] Block / unblock person & community + blocked-list management
- [x] Report post / comment
- [x] Moderator / admin actions

**Customization & settings**
- [x] Themes (System / Light / Dark / True Black) + accent color
- [x] Post density + thumbnail position + text scale
- [x] Default post / comment sort — comment sort persisted in preferences; default post sort persisted per account
- [x] External-link handling — open mode (in-app / system browser), Reader Mode, universal links, "Load Link Previews" (YouTube via oEmbed, Invidious via oEmbed, Piped via `/streams` API, PeerTube via oEmbed), Privacy & Link Cleaning (tracking-param strip, redirector unwrap, HTTPS upgrade, De-AMP, front-end redirect with "Rewrite Third-Party Front-ends" toggle)
- [x] App icon variants — switching is wired; alternate art is placeholder (grid's "not wired" was stale)
- [x] Acknowledgements; backup export (raw SQLite database via share sheet)
- [x] Diagnostic logging — durable GRDB event log (migration v26) recording outbox lifecycle (incl. `op.permanentRollback` on a rolled-back vote, `op.permanentPark` on a parked content send), site-info failures with instance host (`site.fetchFailed`, bounded by give-up), scheduler give-up (`site.giveUp` notice, carries `failureCount`), scheduler ticks, unread refresh, offline downloads, Spotlight reindex, and app lifecycle; pruned to ≤10k rows / ≤14 days; two-tab viewer (Event Log: filter by category + level, search, per-entry detail, export, clear; System Log: OSLog tail with level/category filter + time window); survives relaunch (diagnostics-logging.md)

**Platform**
- [x] iPad split-view handoff — Posts two-column split + feed-switcher title popover (compact: left-edge swipe), Communities two-column reading split, Activity two-column split (timeline primary + Summary detail pinned), collapse/expand with state preservation; adaptive layouts at regular width: Discover multi-column grid + width-capped directory, sheet detents (composer / new-post), capped banners (Edit Profile / Account tab)
- [x] Empty / error / loading states
- [x] Removed and unavailable posts — neutral feed badge (exclamationmark.octagon) + cause-specific placeholder screen when a cached post is no longer found on the server; moderators and the post's author bypass the placeholder and keep access to Restore; automatic recovery on a successful re-fetch (removed-unavailable-content.md)
- [x] Accessibility (Dynamic Type, VoiceOver, Reduce Motion)
- [x] Home Screen widget (top posts)
- [x] App Shortcuts, Siri & Spotlight — 7 App Intents (Open Feed / Search / New Post / Inbox / Open Community / Open Saved / Switch Account); Spotlight indexes communities + saved/history posts
- [~] "Open in Spud" — Safari banner (Web Extension) + an "Open in Spud" share/action extension (handles post / comment / community / user URLs); the Web Extension's browser-action popup is a stub
