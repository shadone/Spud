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
| `ipad` | iPad, regular width — `NavigationSplitView` with a persistent detail pane |
| `widget` | Home Screen widget (`SpudWidgetExtension`) — top posts at a glance |
| `share-extension` | "Open in Spud" Safari Web Extension (`OpenInAppExtension`) — rewrites a Lemmy post page to a deep link that opens the post in the app |

## Capabilities

| Capability | Surfaces | Status |
|---|---|---|
| [Configurable swipe actions](swipe-actions.md) | `iphone`, `ipad` | shipped |
| [Marking posts read and hiding read posts](mark-read-and-hiding.md) | `iphone`, `ipad` | shipped |
| [NSFW content visibility and blur](nsfw-content.md) | `iphone`, `ipad` | shipped |
| [Feeds and sorting](feeds-and-sorting.md) | `iphone`, `ipad` | shipped |
| [Feed loading and pagination](feed-loading.md) | `iphone`, `ipad` | partial — no pull-to-refresh on the feed |
| [Post thumbnails and media badges](post-thumbnails.md) | `iphone`, `ipad` | shipped |
| [Post peek (context-menu preview)](post-peek.md) | `iphone`, `ipad` | shipped |
| [Post detail and comments](post-detail-and-comments.md) | `iphone`, `ipad` | shipped |
| [Voting](voting.md) | `iphone`, `ipad` | shipped |
| [Saving](saving.md) | `iphone`, `ipad` | shipped |
| [Replying](replying.md) | `iphone`, `ipad` | partial — no edit/delete of own comments |
| [Sharing](sharing.md) | `iphone`, `ipad` | shipped |
| [Media viewer and inline video](media-viewer.md) | `iphone`, `ipad` | shipped |
| [Search](search.md) | `iphone`, `ipad` | shipped — scopes: posts / communities / users / comments (federated) + instances (local directory) |
| [Instance browsing (open an instance in-app)](instance-browsing.md) | `iphone`, `ipad` | shipped — directory hit + live `/api/v3/site` probe (Lemmy + PieFed); non-compatible hosts open in browser; communities fetched live via `/api/v3/community/list` when the directory has none |
| [Subscriptions sidebar](subscriptions-sidebar.md) | `ipad` | shipped |
| [Subscribe / unsubscribe](subscribe-unsubscribe.md) | `iphone`, `ipad` | shipped |
| [Community screen](community-screen.md) | `iphone`, `ipad` | shipped — overflow: subscribe, favorite, mute, block, share |
| [Person / user profile](person-profile.md) | `iphone`, `ipad` | shipped — Posts tab renders with the feed cell (vote / save, live state) |
| [Accounts and switching](accounts-and-switching.md) | `iphone`, `ipad` | shipped |
| [Signed-out browsing](signed-out-browsing.md) | `iphone`, `ipad` | shipped |
| [Login](login.md) | `iphone`, `ipad` | shipped — incl. two-factor (TOTP) sign-in |
| [Instance picker](instance-picker.md) | `iphone`, `ipad` | shipped |
| [Registration](registration.md) | `iphone`, `ipad` | partial — no in-app captcha |
| [Sign-in gate on write actions](sign-in-gate.md) | `iphone`, `ipad` | shipped |
| [Inbox](inbox.md) | `iphone`, `ipad` | shipped |
| [Marking inbox items read](inbox-mark-read.md) | `iphone`, `ipad` | shipped |
| [Private messages](private-messages.md) | `iphone`, `ipad` | shipped |
| [Background unread refresh](background-unread-refresh.md) | `iphone`, `ipad` | shipped |
| [New post](new-post.md) | `iphone`, `ipad` | shipped |
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
| [iPad split-view handoff](ipad-split-view.md) | `ipad`, `iphone` | shipped |
| [Empty, error, and loading states](empty-error-loading-states.md) | `iphone`, `ipad` | shipped |
| [Accessibility](accessibility.md) | `iphone`, `ipad` | shipped |
| [Home Screen widget (top posts)](widget.md) | `widget` | shipped |
| [Open in Spud (Safari extension)](share-extension.md) | `share-extension`, `iphone`, `ipad` | partial |

<!-- Add new capability docs here as they are written. -->

## Feature coverage by area

Every shipped capability, grouped by area — the coverage map that replaced the legacy
`design/FEATURES.md` grid. `[x]` shipped, `[~]` partial (qualifier inline).

**Reading & feeds**
- [x] Frontpage feed (All / Local / Subscribed) + sort
- [x] Community-scoped feed
- [x] Saved feed (documented in saving.md)
- [~] Pull-to-refresh — not on the main feed; ships on inbox / profiles / post detail
- [x] Infinite scroll (cursor pagination)
- [x] Inline thumbnails (text / link / image / video) + media badges
- [x] Context-menu peek on posts
- [x] Marking posts read / hiding read posts
- [x] NSFW content visibility and blur — hidden by default; server-side filter + client-side discovery gating (Search, picker, Discover); age acknowledgment on first enable; blur overlay (thumbnails, post-detail header, community art) with tap-to-reveal on posts; privacy screen hides NSFW media from the app-switcher snapshot and screen capture; synced to server for signed-in accounts (nsfw-content.md)
- [x] Configurable swipe actions (posts)

**Posts & comments**
- [x] Post detail (header + comment tree); in-body link preview cards (anchor text always; video thumbnail + title when "Load Link Previews" is on; post-header link card uses server-provided title + thumbnail)
- [x] Upvote / downvote (post & comment)
- [x] Save / unsave (post & comment)
- [x] Threaded comment collapse + jump-to-next-top-level
- [~] Reply — shipped (optimistic inline send + durable retry); edit / delete own comment not supported
- [x] Configurable swipe actions (comments)
- [~] Comment sort — preference-only; no in-screen picker (noted in post-detail-and-comments.md)
- [x] Share post / comment / community URL; open in Safari

**Media**
- [x] Full-screen image viewer (zoom / pan / swipe-to-dismiss)
- [x] Multi-image gallery paging
- [x] Animated GIF playback; inline video

**Discovery**
- [x] Search (posts / comments / communities / users federated, + instances over the local Explorer directory) + inline subscribe + paste-a-Lemmy-URL "Open in Spud" (canonical + frontend `/c/../p/<id>` form)
- [x] Subscriptions sidebar (iPad / regular-width only; no iPhone-portrait entry point) + favorites pinned to top
- [x] Subscribe / unsubscribe
- [x] Community screen (header + feed; overflow: subscribe, favorite, mute, block, copy link / share / open in browser)
- [x] Open an instance in-app — tapping an instance name (community header, body link, Search paste, person profile) opens its in-app screen; directory hit is instant, an unknown host is resolved by a live `/api/v3/site` probe (Lemmy + PieFed open in-app, others fall back to the browser); communities come from the bundled directory, or live via `/api/v3/community/list` when the directory has none; session-cached, curated directory untouched (instance-browsing.md)
- [x] Per-account community favorites (local, pinned in the Communities list)
- [x] Person / user profile (Posts tab uses the feed cell — vote / save through the optimistic outbox, live state; Comments tab is the comment-with-context cell)

**Account & auth**
- [x] Multi-account, multi-instance + account switcher
- [x] Signed-out browsing (bootstrap account)
- [x] Login — incl. two-factor (TOTP) sign-in (code collected and sent; a 2FA-required login auto-prompts for the code)
- [x] Instance picker (site list)
- [~] Registration / signup — shipped; captcha-required instances not handled in-app
- [x] Sign-in gate on write actions

**Inbox & messaging**
- [x] Inbox (replies / mentions / messages) + unread badge
- [x] Mark read / mark-all-read
- [x] Private message threads + send DM
- [x] Background unread-count refresh (foreground scene refresh; not a `BGAppRefreshTask`)

**Content creation**
- [x] New post (text / link / image) + community picker + NSFW
- [x] Image upload (pict-rs)
- [x] Markdown editor + toolbar + live preview
- [x] Draft persistence — durable, per-target, auto-saved (survives dismiss / relaunch)
- [x] Optimistic + durable sending — comments inline in the tree, posts via a pending screen; background retry with backoff
- [x] Drafts & Outbox recovery list (failed / sending / drafts; retry / discard)

**Safety & moderation**
- [x] Block / unblock person & community + blocked-list management
- [x] Report post / comment
- [x] Moderator / admin actions

**Customization & settings**
- [x] Themes (System / Light / Dark / True Black) + accent color
- [x] Post density + thumbnail position + text scale
- [x] Default post / comment sort — comment sort persisted in preferences; default post sort persisted per account
- [x] External-link handling — open mode (in-app / system browser), Reader Mode, universal links, "Load Link Previews" (oEmbed fetch for video cards)
- [x] App icon variants — switching is wired; alternate art is placeholder (grid's "not wired" was stale)
- [x] Acknowledgements; logs viewer + backup export

**Platform**
- [x] iPad split-view handoff
- [x] Empty / error / loading states
- [x] Accessibility (Dynamic Type, VoiceOver, Reduce Motion)
- [x] Home Screen widget (top posts)
- [~] "Open in Spud" — Safari Web Extension (not a share/action extension); post URLs only
