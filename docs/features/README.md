# Spud feature documentation

What Spud does **today** — present-tense, shipped, observable behavior. Each file
documents one capability and links back to the plan / design doc that produced it. This
is not a plan, not a design spec, and not developer-internals: those live in
[`../DESIGN.md`](../DESIGN.md)
and the [`../design/`](../design/) bundle.

Each doc is two layers — a skimmable `What it does` header plus a Gherkin-style
`Scenarios` section — so it serves a reader browsing features, an agent reasoning about
correct behavior, and (later) an author deriving XCUITest scenarios.

> **Relationship to `design/FEATURES.md`.** [`../design/FEATURES.md`](../design/FEATURES.md)
> is the legacy at-a-glance status grid (shipped / partial / deferred, by area). These
> per-capability docs supersede it as they are written: a feature with a doc here is the
> authoritative description of that behavior. Until migration is complete, use the grid
> as the index of what still needs a doc (see Migration backlog below).

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
| `share-extension` | "Open in Spud" share / action extension (`OpenInAppExtension`) — routes Lemmy URLs into the app via deep link |

## Capabilities

| Capability | Surfaces | Status |
|---|---|---|
| [Configurable swipe actions](swipe-actions.md) | `iphone`, `ipad` | shipped |
| [Marking posts read and hiding read posts](mark-read-and-hiding.md) | `iphone`, `ipad` | shipped |
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

<!-- Add new capability docs here as they are written. -->

## Migration backlog

Capabilities still to convert from [`../design/FEATURES.md`](../design/FEATURES.md)
into per-capability docs. Grouped as in the grid; tick when a doc lands above.

**Reading & feeds**
- [x] Frontpage feed (All / Local / Subscribed) + sort
- [x] Community-scoped feed
- [x] Saved feed (documented in saving.md)
- [~] Pull-to-refresh — not on the main feed; ships on inbox / profiles / post detail
- [x] Infinite scroll (cursor pagination)
- [x] Inline thumbnails (text / link / image / video) + media badges
- [x] Context-menu peek on posts
- [x] Marking posts read / hiding read posts
- [x] Configurable swipe actions (posts)

**Posts & comments**
- [x] Post detail (header + comment tree)
- [x] Upvote / downvote (post & comment)
- [x] Save / unsave (post & comment)
- [x] Threaded comment collapse + jump-to-next-top-level
- [~] Reply — shipped; edit / delete own comment not supported
- [x] Configurable swipe actions (comments)
- [~] Comment sort — preference-only; no in-screen picker (noted in post-detail-and-comments.md)
- [x] Share post / comment / community URL; open in Safari

**Media**
- [x] Full-screen image viewer (zoom / pan / swipe-to-dismiss)
- [x] Multi-image gallery paging
- [x] Animated GIF playback; inline video

**Discovery**
- [ ] Search (posts / comments / communities / users) + inline subscribe
- [ ] Subscriptions sidebar
- [ ] Subscribe / unsubscribe
- [ ] Community screen (header + feed)
- [ ] Person / user profile

**Account & auth**
- [ ] Multi-account, multi-instance + account switcher
- [ ] Signed-out browsing (bootstrap account)
- [ ] Login (+ 2FA)
- [ ] Instance picker (site list)
- [ ] Registration / signup
- [ ] Sign-in gate on write actions

**Inbox & messaging**
- [ ] Inbox (replies / mentions / messages) + unread badge
- [ ] Mark read / mark-all-read
- [ ] Private message threads + send DM
- [ ] Background unread-count refresh

**Content creation**
- [ ] New post (text / link / image) + community picker + NSFW
- [ ] Image upload (pict-rs)
- [ ] Markdown editor + toolbar + live preview
- [ ] Draft persistence

**Safety & moderation**
- [ ] Block / unblock person & community + blocked-list management
- [ ] Report post / comment
- [ ] Moderator / admin actions

**Customization & settings**
- [ ] Themes (System / Light / Dark / True Black) + accent color
- [ ] Post density + thumbnail position + text scale
- [ ] Default post / comment sort
- [ ] External-link handling
- [ ] App icon variants (partial)
- [ ] Acknowledgements; logs viewer + backup export

**Platform**
- [ ] iPad split-view handoff
- [ ] Empty / error / loading states
- [ ] Accessibility (Dynamic Type, VoiceOver, Reduce Motion)
- [ ] Home Screen widget (top posts)
- [ ] "Open in Spud" share / action extension
