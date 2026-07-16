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
| `share-extension` | "Open in Spud" Safari Web Extension (`OpenInAppExtension`) — in-page banner + toolbar popup on known instances, plus the share/action extension — hands a Lemmy page to a deep link that opens it in the app |

## Capabilities

| Capability | Surfaces | Status |
|---|---|---|
| [Configurable swipe actions](swipe-actions.md) | `iphone`, `ipad` | shipped |
| [Marking posts read and hiding read posts](mark-read-and-hiding.md) | `iphone`, `ipad` | shipped |
| [NSFW content visibility and blur](nsfw-content.md) | `iphone`, `ipad` | shipped |
| [Feeds and sorting](feeds-and-sorting.md) | `iphone`, `ipad` | shipped — feed switcher: left-edge back-swipe on iPhone; navbar-title popover on iPad (see [iPad split-view handoff](ipad-split-view.md)) |
| [Feed loading and pagination](feed-loading.md) | `iphone`, `ipad` | shipped — cursor pagination + pull-to-refresh + offline/unreachable/malformed states with retry |
| [Download a feed for offline browsing](offline-download.md) | `iphone`, `ipad` | shipped — choose 100/250/500 posts; predownload posts + comments + images (+ optional linked-page web archives read in an in-app offline reader) from the feed config popover, with a non-blocking progress pill (dismiss the chooser and keep using the app; the pill's ✕ cancels) + cancel; paced + retried requests (back-off on transient/pushback errors) and partial-success (keeps what it got when a page permanently fails); a durable **Downloaded** feed (count-gated switcher entry + a "View downloaded content" button on the offline screen) lists downloaded posts and reads them entirely offline |
| [Post thumbnails and media badges](post-thumbnails.md) | `iphone`, `ipad` | shipped |
| [Post peek (context-menu preview)](post-peek.md) | `iphone`, `ipad` | shipped |
| [Post detail and comments](post-detail-and-comments.md) | `iphone`, `ipad` | shipped — incl. offline-aware comments (truthful failed/offline state with Retry — plus automatic re-fetch when connectivity returns — not a false "no comments yet") + header thumbnail-while-loading with a "Low-res preview" pill; tappable inline "load more replies" expansion pending release (on `feat/load-more-replies`) |
| [Voting](voting.md) | `iphone`, `ipad` | shipped — incl. offline-aware "we'll send your vote when you're back online" toast; structural voted-state cue: filled capsule (vote buttons on) or dog-ear fold (vote buttons off) on posts, filled capsule on post-detail header, filled mini-pill on comment score; downvote color changed app-wide to indigo |
| [Saving](saving.md) | `iphone`, `ipad` | shipped — incl. offline-aware "we'll save this when you're back online" toast |
| [Replying](replying.md) | `iphone`, `ipad` | shipped — reply + edit + delete/restore own comments, all optimistic + durable (see [Post detail and comments](post-detail-and-comments.md)); composer sheet uses proper medium/large detents on iPad |
| [Sharing](sharing.md) | `iphone`, `ipad` | shipped |
| [Media viewer and inline video](media-viewer.md) | `iphone`, `ipad` | shipped — incl. "Showing low-resolution preview" pill when the full-res image can't load over a thumbnail; recognized video hosts (streamable + PeerTube + loops.video + YouTube-via-Piped) play inline with browser fallback on resolution failure; YouTube inline requires a Piped front-end configured in Privacy settings |
| [Discover (Community Explorer)](discover.md) | `iphone`, `ipad` | shipped — rails (Starter packs / Trending / Rising / Because you follow / Browse by instance) each with "See all", over a sortable directory + same-name compare (per-variant subscribe) + live network-search fallback; Browse by instance shows live software+signups chips on open (fail-open, engagement-gated); auto-refreshes the directory on open (per Community Data settings); on iPad (regular width) rails render as an adaptive multi-column grid and the directory is width-capped/centered; tapping a community opens it in the two-column reading split |
| [Search](search.md) | `iphone`, `ipad` | shipped — scopes: posts / communities / users / comments (federated) + instances (local directory); post results reuse the rich feed cell (community@instance, counts, thumbnail, status/author badges) + an author line, vote arrows suppressed; NSFW posts render blurred (not dropped); all five result kinds carry a long-press context menu (post = feed parity, community = Discover parity, comment = post-detail comment-menu parity, user = Person-profile-header-menu parity plus Open/Share, instance = Open/Copy Link/Share/Add Account Here); mutating actions gate on sign-in, none of them live-update the search row |
| [Instance browsing (open an instance in-app)](instance-browsing.md) | `iphone`, `ipad` | shipped — directory hit + live `/api/v3/site` probe (Lemmy + PieFed); non-compatible hosts open in browser; communities fetched live via `/api/v3/community/list` when the directory has none |
| [Communities tab (subscriptions)](subscriptions-sidebar.md) | `iphone`, `ipad` | shipped — first-class tab (was the iPad sidebar); feed shortcuts + Discover entry + subscribed list with favorites pinned, filter + sort |
| [Subscribe / unsubscribe](subscribe-unsubscribe.md) | `iphone`, `ipad` | shipped |
| [Community screen](community-screen.md) | `iphone`, `ipad` | shipped — overflow: subscribe, favorite, mute, block, share; on iPad (regular width) opens as a two-column reading split (see [iPad split-view handoff](ipad-split-view.md)) |
| [Instance meta communities](instance-meta-communities.md) | `iphone`, `ipad` | shipped — heuristic "Instance community" badge on Discover / Communities tab / Search / community header; always-visible "About `<instance>`" section in the Communities tab (high-confidence first, low-confidence under a disclosure) with one-tap Favourite (always) / Subscribe (signed in); a dedicated meta section on the instance-detail screen is not shipped |
| [Person / user profile](person-profile.md) | `iphone`, `ipad` | shipped — Posts tab renders with the feed cell (vote / save, live state) |
| [Accounts and switching](accounts-and-switching.md) | `iphone`, `ipad` | shipped — signed-in Account tab is a profile header + shortcuts list (Switch account / Saved / Activity / Your posts / Your comments / Drafts & Outbox / Log out) |
| [Session re-login hint](session-reauth.md) | `iphone`, `ipad` | shipped — pending on-device validation; a "!" tab badge, an Account-screen row, a switcher per-row affordance, and a blocked-action toast all flag an account whose stored session expired and route to an in-place, pre-filled re-login; a WAF/CDN 403 never triggers it |
| [Account Activity](account-activity.md) | `iphone`, `ipad` | shipped — reverse-chronological timeline of everything the signed-in account has done (authored posts + comments, upvoted/downvoted, saved, read, seen, hidden); rows reuse feed/search cells; filter chip bar (7 types); search; day-based grouping; states + pull-to-refresh; infinite scroll; Your posts/Your comments/Activity open it pre-filtered (the Saved row opens the server saved feed); + Summary screen (identity strip, 6 stat tiles, 18-week contribution heatmap with All/Reads/Votes metric picker, extras insights); on iPad (regular width) a two-column split — timeline primary, Summary pinned in the detail column (tapping a row opens it in the detail over Summary; collapse to compact restores the Summary nav button); on iPhone the "Your footprint" rail (default state only: default filters + no search + has content) shows four quick stats and a Summary entry above the timeline |
| [Edit your profile](profile-editing.md) | `iphone`, `ipad` | shipped — display name, bio, avatar + banner (live-preview header, pict-rs upload, remove) + server-synced toggles (scores / bots / read posts / avatars) + default feed; on iPad the live-preview banner is width-capped and centered rather than full-bleed |
| [Signed-out browsing](signed-out-browsing.md) | `iphone`, `ipad` | shipped — signed-out Account tab is a grouped "Browsing anonymously" screen (Reading-from row, Create account / Log in, Settings) |
| [Login](login.md) | `iphone`, `ipad` | shipped — incl. two-factor (TOTP) sign-in |
| [Instance picker](instance-picker.md) | `iphone`, `ipad` | shipped |
| [Custom instance entry](custom-instance-entry.md) | `iphone`, `ipad` | shipped — type the address of a private/non-federated instance not in the directory, from onboarding or the instance picker, straight into the normal login/register flow |
| [Registration](registration.md) | `iphone`, `ipad` | shipped |
| [Instance software detection](instance-software-detection.md) | `iphone`, `ipad` | partial — instance-detail badge shows detected software + live version; details-card Signups row prefers a live open-registrations signal (fail-open, same copy as the Explorer fallback); Discover browse-instance chips surface the same signal; bare-instance link signpost deferred |
| [PieFed instances](piefed.md) | `iphone`, `ipad` | shipped — browse **and** sign in: a PieFed instance (detected via NodeInfo, routed through a PieFed `/api/alpha` dialect decoded into the same neutral content types as Lemmy) is fully readable (feeds, communities, posts + comment trees, person profiles, search) and a signed-in account can vote/save/subscribe/mark-read/hide, comment (create/edit/delete), post (create/edit/delete), read the replies/mentions inbox, and send/read DMs. Login is username-based (no 2FA); withheld on PieFed: image upload + server-side profile/settings save (capability-gated), account content lists, blocks; registration is web-only; PieFed-native extras (reactions/flair/topics/feeds) decode harmlessly but are unsurfaced (Phase 3) |
| [Instance capability gating](instance-capability-gating.md) | `iphone`, `ipad` | shipped, now **dormant for Lemmy** — the mechanism (UI gates, service backstop, `capability.blocked` event) is retained but gates nothing on any Lemmy version now that Spud speaks native v4; the seven features it once withheld on Lemmy 1.0 all work there; still fails open for non-Lemmy software and a future version-varying capability |
| [Sign-in gate on write actions](sign-in-gate.md) | `iphone`, `ipad` | shipped |
| [Inbox](inbox.md) | `iphone`, `ipad` | shipped — backend-neutral (v3 per-kind endpoints or the native v4 unified notification inbox); no longer gated on Lemmy 1.0 |
| [Marking inbox items read](inbox-mark-read.md) | `iphone`, `ipad` | shipped |
| [Reminders](reminders.md) | `iphone`, `ipad` | shipped — time-based "Remind Me…" reminders (local OS notification + Inbox Reminders segment + tab badge); "When there are new comments" activity follow, checked via a foreground poll plus a best-effort `BGAppRefreshTask` background poll; either can target the whole post OR a single comment's thread (from the comment's context menu), independently; a thread reminder opens the post scrolled to that comment; removing/logging out of an account cancels its reminders and follows |
| [Private messages](private-messages.md) | `iphone`, `ipad` | shipped — GRDB-backed (offline-readable) threads + optimistic, durable sending (instant bubble, background retry, failure recovery via Drafts & Outbox); load-earlier thread history (position-preserving prepend) + conversation-list infinite scroll; new-message compose (recipient picker) + Markdown bodies |
| [Background unread refresh](background-unread-refresh.md) | `iphone`, `ipad` | shipped — foreground scene refresh (unread badge) + periodic scheduler site-info refresh with persisted exponential back-off and permanent give-up after N=5 consecutive permanent failures |
| [Account provenance and site-info refresh](account-provenance-and-site-refresh.md) | `iphone`, `ipad` | shipped — pending release — ephemeral browse accounts excluded from the recurring sweep; one on-demand site-info fetch on first open; persisted per-site give-up after N=5 permanent failures; self-heals on a successful visit |
| [New post](new-post.md) | `iphone`, `ipad` | shipped; composer sheet uses proper medium/large detents on iPad |
| [Cross-posting](cross-posting.md) | `iphone`, `ipad` | shipped — "Cross-post" on the feed context menu and post-detail overflow menu; opens the new-post composer pre-filled with title + link (+ quoted body attribution from post detail); an open post also shows a "Cross-posted to N communities" section listing its existing cross-posts, tappable to open one; the feed also collapses same-link duplicates it has loaded into one row with an "Also in ..." affordance and a context-menu jump to each sibling (preference-gated, default on; same-page only — see [Display density and text size](display-density-and-text.md) for the toggle) |
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
| [Post author status](author-status.md) | `iphone`, `ipad` | shipped — full role/status pills (MOD/ADMIN/BOT/BANNED/SUSPENDED) on the post-detail byline (mirroring comment badges); low-noise single red banned-author marker in the feed (suspended / community-banned only); "[deleted]" author byline; VoiceOver announces status |
| [Accessibility](accessibility.md) | `iphone`, `ipad` | shipped |
| [Home Screen widget (top posts)](widget.md) | `widget` | shipped |
| [App Shortcuts, Siri & Spotlight](app-shortcuts-and-siri.md) | `iphone`, `ipad` | shipped — 7 App Intents (incl. Open Saved, Switch Account); Spotlight indexes communities + saved/history posts; NSFW posts excluded from Handoff/Spotlight/Siri |
| [Open in Spud (Safari extension)](share-extension.md) | `share-extension`, `iphone`, `ipad` | shipped |

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
- [x] Download a feed for offline browsing — "Download for offline" in the feed config popover opens a chooser (100/250/500 posts; optional "save linked web pages") then bulk-saves posts + comments + images into the local store + durable image cache (+ external-link web archives, read offline in an in-app WKWebView reader); a non-blocking window-anchored progress pill (survives feed/tab switches; its ✕ is the sole cancel — dismissing it never cancels) + result toast; requests are paced and retried with back-off (and back off further on a 429/503), and a page that permanently fails after some pages landed finishes partial rather than aborting; offline, the GRDB-first feed/detail browse from the saved copy — plus a durable **Downloaded** feed (per-post `downloadedAt` marker) reachable from a count-gated feed-switcher entry and a "View downloaded content" button on the offline screen, listing downloaded posts newest-first and rendering entirely from GRDB with no network (offline-download.md)
- [x] Inline thumbnails (text / link / image / video) + media badges
- [x] Context-menu peek on posts
- [x] Marking posts read / hiding read posts
- [x] Grouping cross-posts in the feed — same-link duplicates already loaded into the feed collapse into one row with an "Also in c/name" / "Also in N communities" affordance and a context-menu "Also posted in" jump to each collapsed sibling; runs after the hide-read filter; preference-gated (Settings → Display → "Group Cross-posts", default on); client-side and same-page only, since the feed API carries no cross-post list (cross-posting.md)
- [x] NSFW content visibility and blur — hidden by default; server-side filter + client-side discovery gating (Search, picker, Discover); age acknowledgment on first enable; blur overlay (thumbnails, post-detail header, community art) with tap-to-reveal on posts; privacy screen hides NSFW media from the app-switcher snapshot and screen capture; never advertised to Handoff, in-app or system Spotlight, or Siri suggestions (unconditional, independent of Show NSFW); synced to server for signed-in accounts (nsfw-content.md)
- [x] Configurable swipe actions (posts)

**Posts & comments**
- [x] Post detail (header + comment tree); in-body link preview cards (anchor text always; video thumbnail + title when "Load Link Previews" is on; post-header link card uses server-provided title + thumbnail); offline-aware — a failed comment load shows a truthful offline/unreachable/malformed state with Retry (never a false "No comments yet"), and an offline failure re-fetches automatically once connectivity returns, and the header keeps the cached feed thumbnail while the full image loads, falling back to a tappable "Low-res preview" pill when the full image can't load
- [x] Load more replies (pending release) — tapping a "N more replies" row fetches the missing subtree and splices it in inline, in place, with a spinner while it loads; a subtree deeper than one fetch leaves a fresh "load more" row further down (self-healing); a failed fetch reverts the row and shows a "Couldn't load more replies" toast, retried by tapping again; works against both v3 and native v4 Lemmy servers (on `feat/load-more-replies`)
- [x] Upvote / downvote (post & comment) — offline votes queue with a "we'll send your vote when you're back online" toast; structural voted-state cue: filled capsule when vote buttons are visible (default), dog-ear fold when they're hidden (post list); filled capsule on post-detail header; filled score mini-pill on voted comments (neutral comments still show their score unfilled); downvote color changed app-wide to indigo; Reduce Motion cross-fades the fill instead of scaling; active vote control gains the `.selected` VoiceOver trait
- [x] Save / unsave (post & comment) — offline saves queue with a "we'll save this when you're back online" toast
- [x] Threaded comment collapse + jump-to-next-top-level
- [x] Reply / edit / delete / restore own comments — all optimistic + durable (reply + edit via the content outbox; delete / restore via the mutation outbox)
- [x] Edit / delete / restore your own post — optimistic + durable (edit via the content outbox; delete / restore via the mutation outbox)
- [x] Configurable swipe actions (comments)
- [x] Comment sort — global default (Settings) + in-screen per-post picker (post-detail config popover: Hot / Top / New / Old / Controversial)
- [x] Post author status — full MOD/ADMIN/BOT/BANNED/SUSPENDED pills on the post-detail byline (mirroring comment badges); a single low-noise red banned-author marker in the feed for suspended / community-banned authors only; "[deleted]" author byline with the profile link suppressed; VoiceOver announces the status (author-status.md)
- [x] Cross-posts on a post — "Cross-posted to N communities" section on the open post, listing other posts sharing its link in server order (community handle + score/comment-count line), tappable to open one; one-shot read on load + pull-to-refresh, no section when there are none (cross-posting.md)
- [x] Share post / comment / community URL; open in Safari

**Media**
- [x] Full-screen image viewer (zoom / pan / swipe-to-dismiss) — keeps the preview thumbnail and shows a "Showing low-resolution preview" pill when the full-res image can't load (e.g. offline), instead of the broken-image icon
- [x] Multi-image gallery paging
- [x] Animated GIF playback; inline video — direct mp4/mov/m4v plays via the system player; recognized video hosts (streamable.com, PeerTube instances, loops.video, YouTube-via-Piped) resolve to their stream and play inline, with browser fallback on resolution failure; YouTube inline requires a Piped front-end in Privacy settings (Invidious and other front-ends open in the browser; Google is never contacted for playback)

**Discovery**
- [x] Discover (Community Explorer) — browsable home in the Communities tab: Starter packs / Trending / Rising / Because you follow / Browse-by-instance rails (each with "See all" into the full ranked list) over a sortable, searchable directory; same-name dedupe + compare sheet (per-variant subscribe); live network-search fallback; Browse-by-instance shows live software+version and open-signups chips once an instance is opened (NodeInfo probe, engagement-gated, fail-open); long-press quick actions (subscribe, mute, block, share); NSFW + suspicious safety filtering; refreshes the directory from the network on open (per Community Data settings); on iPad (regular width) rails render as an adaptive multi-column grid and the directory is width-capped and centered; tapping a community opens it in the Communities tab's two-column reading split (discover.md)
- [x] Search (posts / comments / communities / users federated, + instances over the local Explorer directory) — post results render as the shared rich feed cell (community@instance, counts, thumbnail, status/author badges) plus a `@user@instance` author line, with vote arrows suppressed and NSFW posts blurred rather than dropped; every one of the five result kinds carries a long-press context menu: post = the same menu the feed uses (vote/save/reply/share/cross-post/visit community/view author/hide/block/report/mute/remind me); community = Discover's community context menu (open/subscribe/mute/share/copy link/block); comment = post detail's comment context menu (open thread/vote/save/share/copy link/view author/report); user = the Person profile header's long-press actions plus two for parity (open profile/copy handle/share/block user); instance = a small directory-appropriate menu with no per-viewer state (open/copy link/share/add account here, the last jumping straight to the login flow for that instance); every mutating action gates on sign-in and none of them live-update the search row (Search renders the fetched response, not a GRDB observation) + inline subscribe + paste-a-Lemmy-URL "Open in Spud" (canonical + frontend `/c/../p/<id>` form)
- [x] Communities tab (subscriptions) — first-class tab on iPhone + iPad (was the iPad-only sidebar); feed shortcuts, Discover entry, subscribed list with favorites pinned, "Search your communities" filter + Alphabetical / By-instance sort
- [x] Subscribe / unsubscribe
- [x] Community screen (header + feed; overflow: subscribe, favorite, mute, block, copy link / share / open in browser)
- [x] Instance meta communities — a heuristic classifier (name/title vs. the instance's site name / domain label vs. a strong/broad keyword set) flags communities that are about their own home instance (e.g. `announcements@lemmy.world`) with a small "Instance community" badge on Discover, the Communities tab, Search results, and the community header; the Communities tab additionally shows an always-visible "About `<instance>`" section listing the home instance's detected meta communities (high-confidence first, low-confidence under a "More on this instance" disclosure) with one-tap Favourite (always available, local-only) and Subscribe (signed in only); nothing is auto-subscribed or auto-favourited, and there's no push notification on new posts (instance-meta-communities.md)
- [x] Open an instance in-app — tapping an instance name (community header, body link, Search paste, person profile) opens its in-app screen; directory hit is instant, an unknown host is resolved by a live `/api/v3/site` probe (Lemmy + PieFed open in-app, others fall back to the browser); communities come from the bundled directory, or live via `/api/v3/community/list` when the directory has none; session-cached, curated directory untouched (instance-browsing.md)
- [x] Per-account community favorites (local, pinned in the Communities list)
- [x] Person / user profile (Posts tab uses the feed cell — vote / save through the optimistic outbox, live state; Comments tab is the comment-with-context cell)

**Account & auth**
- [x] Multi-account, multi-instance + account switcher
- [x] Account tab — signed-in home: tappable profile header (banner + avatar + display name + handle -> Edit your profile) over a shortcuts list (Switch account, Saved, Activity, Your posts, Your comments, Drafts & Outbox, Log out), Settings in the nav bar (accounts-and-switching.md)
- [x] Account Activity — reverse-chronological timeline of posts/comments authored, upvoted/downvoted, saved, read, seen, hidden; rows reuse the feed/search cells; 7-type filter chip bar (funnel reset) with preset filters from Account tab shortcuts (Your posts/Your comments open it pre-filtered; the Saved row opens the server saved feed instead); search; day-based grouping; states (empty/loading/offline/voted-first-run); pull-to-refresh; infinite scroll; + Summary screen (identity strip, 6 stat tiles, 18-week contribution heatmap with All/Reads/Votes metric picker, extras insights); on iPad (regular width) a two-column split with the Summary pinned in the detail column and timeline rows opening their detail over it; on iPhone a "Your footprint" glance rail above the timeline (default filters, no search, has content) showing four quick stats and a Summary entry (account-activity.md)
- [x] Edit your profile — display name, bio, avatar + banner (pict-rs upload; live-preview header mirrors the public person profile; remove clears from the server; no in-app cropping), plus the server-synced account toggles (show scores / bot accounts / read posts / others' avatars) and default feed; saved via `save_user_settings` then refreshed; banner also shown in Account tab header; on iPad the live-preview banner is width-capped and centered rather than full-bleed (profile-editing.md)
- [x] Signed-out browsing (bootstrap account) — signed-out Account tab is a grouped "Browsing anonymously" screen: guest header, Reading-from / change-server row, Create account / Log in, Settings (signed-out-browsing.md)
- [x] Account provenance and site-info refresh (pending release) — browse accounts are flagged ephemeral and excluded from the 5-minute site-info sweep; one best-effort on-demand fetch on first open; persisted per-site exponential back-off + permanent give-up after N=5 consecutive permanent failures; give-up is self-healing (a successful visit resets it); existing browse accounts backfilled on upgrade (account-provenance-and-site-refresh.md)
- [x] Login — incl. two-factor (TOTP) sign-in (code collected and sent; a 2FA-required login auto-prompts for the code); a transport/connection failure (unreachable host, DNS, timeout) shows "Couldn't connect to `<host>`" instead of a credentials error (custom-instance-entry.md)
- [x] Instance picker (site list) — incl. "Add your own instance" row for a host not in the directory (custom-instance-entry.md)
- [x] Custom instance entry — type a private/non-federated instance's address, from onboarding ("Enter instance address") or the instance picker ("Add your own instance"), into the normal login/register flow; client-side-only validation (no reachability probe, so a firewalled instance is never false-blocked) (custom-instance-entry.md)
- [x] Registration / signup — shipped (captcha was removed from Lemmy server-side; no in-app captcha solver); a transport/connection failure shows "Couldn't connect to `<host>`" instead of a generic retry message (custom-instance-entry.md)
- [x] Session re-login hint (pending on-device validation) — a signed-in account whose stored session is rejected (never a bare WAF/CDN 403) is flagged `sessionNeedsReauth`, surfaced as an Account-tab "!" badge, a prominent Account-screen row, a per-row "Re-login" affordance in the account switcher, and an in-the-moment "Session expired" toast on a blocked vote/save/hide; every surface opens the same in-place, pre-filled re-login (instance + username filled, password re-entered) that reuses the existing account (no duplicate) and self-heals the flag on any subsequent authenticated success (session-reauth.md)
- [~] Instance software detection — NodeInfo pre-flight on login/register blocks non-Lemmy hosts with an action sheet (names the software, offers Open in Safari); instance-detail badge shows detected software name + live version; details-card Signups row prefers a live open-registrations signal over the Explorer directory (fail-open, same copy so the row never visibly changes wording); fails open when the probe is undetermined; bare-instance link signpost deferred (instance-software-detection.md)
- [x] PieFed instances (browse + sign in) — a PieFed instance (detected via NodeInfo) is browsable signed-out and loginable: its feeds, communities, posts + comment trees, person profiles, and search all render, decoded into the same neutral content types as Lemmy by a dedicated PieFed `/api/alpha` dialect chosen from the detected software (never from a Lemmy-scale version parse). A signed-in PieFed account (username-based login, no 2FA) can vote/save/subscribe/mark-read/hide, comment (create/edit/delete), post (create/edit/delete), read the replies/mentions inbox with unread counts, and send/read DMs — all through the same durable outboxes as Lemmy. Withheld on PieFed via capability gating: image upload and server-side profile/settings save; also unsurfaced: account content lists and blocks. Registration is web-only (purpose-aware pre-flight). Session expiry offers in-place re-login. PieFed-native extras (reactions/flair/topics/feeds) decode harmlessly but are unsurfaced (Phase 3) (piefed.md)
- [x] Instance capability gating — a Phase-1 stopgap, now **dormant for Lemmy**: it once gated seven features whose endpoints the Lemmy 1.0 v3 compat shim lacked (person profiles, inbox, private messages, image upload, hide post, profile/settings save, server read-state sync), but Spud now speaks the native v4 API for all of them, so the version-derivation table gates nothing on any Lemmy version. The mechanism (the `InstanceCapabilities` type, each feature's UI gate, the `LemmyServiceError.unsupportedByInstance` service backstop classified as a permanent/non-retried outbox failure, and the `capability.blocked` diagnostic event) is retained for non-Lemmy software and a future version-varying capability; still fails open on an unknown/unparseable version and for non-Lemmy software (instance-capability-gating.md)
- [x] Sign-in gate on write actions

**Inbox & messaging**
- [x] Inbox (replies / mentions / messages) + unread badge — backend-neutral: reads the v3 per-kind endpoints or the native v4 unified notification inbox, identical UI either way; no longer gated on Lemmy 1.0
- [x] Mark read / mark-all-read
- [x] Reminders — "Remind Me…" time presets from the post-detail overflow menu, feed context menu, AND a comment's long-press context menu (the comment version scopes to that comment's subtree instead of the whole post); delivered as a local OS notification (or in-app only if notifications are denied) and surfaced in a dedicated Inbox Reminders segment with its own fired-unseen tab-badge contribution; local/durable only, no backend. Same menu's "When there are new comments" toggle follows the target's discussion (whole post, or a comment's thread), checked by a foreground poll (smart rule: ≥5 new comments/replies, or ≥1 new after 24h — a thread's count is that comment's own descendant count, including your own replies) plus a best-effort `BGAppRefreshTask` background poll (opportunistic — requires Background App Refresh, timing not guaranteed) that runs the identical check while the app is closed; shown in the same Reminders segment ("Watching for new comments"/"New comments · tap to catch up" for a whole post, "Watching a thread for new replies"/"New replies · tap to catch up" for a thread); works signed-out too. A thread reminder's tap opens the post scrolled to that comment. Removing/logging out of an account deletes its reminders and follows and cancels their scheduled OS notifications (reminders.md)
- [x] Private message threads — GRDB-backed (offline-readable), with optimistic + durable sending (instant "Sending…" bubble, multiple in flight, background retry, failure recovery in Drafts & Outbox), load-earlier thread history (a top control that pages the overall PM list and prepends older messages without moving the reading position), conversation-list infinite scroll (the Messages list pages in more conversations on scroll, with a bottom spinner), per-correspondent draft autosave, optimistic conversation-list rows, new-message compose (recipient picker), and Markdown-rendered message bodies
- [x] Background unread-count refresh (foreground scene refresh; not a `BGAppRefreshTask`) + periodic scheduler site-info refresh with persisted per-site exponential back-off (≈5 min doubling → ~2 h cap) and permanent give-up after N=5 consecutive permanent failures (account-provenance-and-site-refresh.md, background-unread-refresh.md)

**Content creation**
- [x] New post (text / link / image) + community picker + NSFW; on iPad the composer sheet uses proper medium/large detents (not a full-screen modal)
- [x] Cross-posting — "Cross-post" on the feed's long-press context menu and the post-detail "•••" overflow menu opens the new-post composer pre-filled with the source post's title + link (post detail also seeds a `cross-posted from: <link>` quoted-body attribution); target community left for the user to pick (cross-posting.md)
- [x] Image upload (pict-rs)
- [x] Markdown editor + toolbar + live preview
- [x] Draft persistence — durable, per-target, auto-saved (survives dismiss / relaunch)
- [x] Optimistic + durable sending — comments inline in the tree, posts via a pending screen, direct messages as inline chat bubbles; background retry with backoff; reply and new-post composer sheets use proper medium/large detents on iPad
- [x] Drafts & Outbox recovery list (failed / sending / drafts; retry / discard) — reached from the signed-in Account tab or the failure toast (drafts-and-outbox.md)

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
- [x] App Shortcuts, Siri & Spotlight — 7 App Intents (Open Feed / Search / New Post / Inbox / Open Community / Open Saved / Switch Account); Spotlight indexes communities + saved/history posts; an NSFW post (own flag or its community's) is never advertised to Handoff, indexed into Spotlight, or suggested by Siri, unconditionally
- [x] "Open in Spud" — Safari banner (Web Extension) + a toolbar popup (both known-instance) + an "Open in Spud" share/action extension (handles post / comment / community / user URLs)
