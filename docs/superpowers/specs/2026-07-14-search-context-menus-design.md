# Search Result Context Menus — Design Spec

**Date:** 2026-07-14
**Status:** Approved (brainstorm) — pending implementation plan

**Goal:** Give every Search result row a long-press context menu that mirrors the actions you'd get long-pressing that same entity elsewhere in the app. Post results reach full parity with the post-list menu (via a builder extracted from the feed and shared); community, comment, user, and instance results get parity-where-practical menus built the same way.

---

## 1. Concept

Search (`Spud/Scenes/Search/`) renders results across five scopes — posts, communities, users, comments, instances — as tappable `UITableViewCell`s. Today a tap navigates but a long-press does nothing. Every comparable list elsewhere (the post feed, Discover community cards) offers a long-press context menu; Search is the gap.

This feature adds a `UIContextMenuConfiguration` per result type, dispatched from `SearchViewController`'s `UITableViewDelegate.tableView(_:contextMenuConfigurationForRowAt:point:)` on the row's result type. The menus are produced by small, testable **context-menu builders**, one per entity type, driven by **delegate protocols** that abstract the actions so the same builder works from any host screen.

The centerpiece is the **post** builder: the feed's context menu is extracted out of `PostListViewController` into a reusable `PostContextMenuBuilder`, the feed adopts it (becoming a consumer of the shared builder rather than the owner of an inline menu), and Search uses the identical builder — guaranteeing the two menus never drift.

---

## 2. Architecture

### 2.1 Builders + delegate protocols (the shared pattern)

For each entity type, a builder type with a single responsibility: given the entity's row/state and a host delegate, return a `UIMenu` (or a `UIContextMenuConfiguration` wrapping it). Builders live in a new `Spud/Utils/ContextMenus/` directory (one small file each), alongside the existing `Spud/Utils/PostActions.swift`.

```
Spud/Utils/ContextMenus/
  PostContextMenuBuilder.swift
  CommunityContextMenuBuilder.swift
  CommentContextMenuBuilder.swift
  UserContextMenuBuilder.swift
  InstanceContextMenuBuilder.swift
```

A builder is a near-pure function of (row state) -> (menu structure): which `UIAction`s and sub-`UIMenu`s appear, their titles, SF Symbols, `.destructive` attributes, and enabled state. It performs no side effects itself; each action's handler calls a method on the **host delegate**. This makes "given this state, the menu contains these items" unit-testable without a live screen.

Delegate protocols abstract the action surface. They are `@MainActor` protocols refining `UIViewController`, composed from the existing factored protocols plus new ones:

- Reuse (already exist, `Spud/Utils/PostActions.swift`): `PostVoteDispatching` (`vote(serverPostId:action:)` — sign-in gate + outbox), `PostSaveDispatching` (`toggleSaved`/`setSaved`).
- New per-entity host protocols, e.g. `PostContextMenuHost`, `CommunityContextMenuHost`, `CommentContextMenuHost`, `UserContextMenuHost`, `InstanceContextMenuHost`. Each declares the actions its builder needs. Framework-generic actions (share via `UIActivityViewController`, copy link to the pasteboard, navigate to a community/person/post/instance through the app's existing open paths) are provided as **default implementations** in protocol extensions, so a conforming host only implements the screen-specific ones. Screen-specific mutating actions that already have a shared path (vote/save via the outbox) reuse it; the rest (hide, mute community, block author/user, report, reply, remind-me, subscribe) are declared and implemented by the host.

`PostListViewController` and `SearchViewController` both conform to `PostContextMenuHost`; `SearchViewController` additionally conforms to the four other hosts (Search is the only UIKit list of communities/comments/users/instances today, so those four builders have a single consumer for now — but they are structured for reuse).

### 2.2 Attachment in Search

`SearchViewController` implements `tableView(_:contextMenuConfigurationForRowAt:point:)`. It resolves the row's result model from the diffable data source's item identifier, switches on the result type, and asks the matching builder for a configuration:

- `.post` -> `PostContextMenuBuilder.configuration(for: result.row, host: self)`
- `.community` -> `CommunityContextMenuBuilder.configuration(for: result, host: self)`
- `.comment` -> `CommentContextMenuBuilder.configuration(for: result, host: self)`
- `.user` -> `UserContextMenuBuilder.configuration(for: result, host: self)`
- `.instance` -> `InstanceContextMenuBuilder.configuration(for: result, host: self)`

The "Open in Spud" URL-paste row (`SearchOpenURLCell`) is not an entity result and gets no menu (return `nil`).

### 2.3 Post builder extraction (the biggest single piece)

`PostListViewController.tableView(_:contextMenuConfigurationForRowAt:)` (~`:2177-2321`) builds the feed menu inline from many private methods. Extraction:

1. Move the menu STRUCTURE into `PostContextMenuBuilder` (a function taking a `PostListRow` + a `PostContextMenuHost`), reproducing the current grouping and order exactly: vote group (Upvote, Downvote, Save, Remind Me submenu) | share group (Reply, Share, Cross-post) | nav group (Visit community, View author, "Also posted in" submenu when cross-post siblings exist) | hide group (Hide, Mute community submenu) | moderation submenu (only when the viewer moderates the community) | safety group (Block author, Report).
2. Lift the action implementations that are currently private to `PostListViewController` (share, cross-post prefill, reply composer presentation, report flow, remind-me menu, mute-community menu, moderation menu, hide, block author) into a host-agnostic form: either default protocol-extension implementations (framework-generic ones) or `PostContextMenuHost` requirements that both VCs implement by delegating to the same services (outbox, `lemmyService`, `ReminderService`, `AlertService`, the composer, the app coordinator). The vote/save path already goes through `PostVoteDispatching`/`PostSaveDispatching` and is reused as-is.
3. `PostListViewController` becomes a consumer: its `contextMenuConfigurationForRowAt` calls `PostContextMenuBuilder.configuration(for:host:)`. Behavior must be byte-for-byte the same feed menu — this is a refactor, not a redesign, of the feed's menu.

**Parity-where-practical for Search post rows:** a search post row carries the full `PostListRow` (`SearchPostResult.row`), so all identity is present. Submenus that depend on data a search row may not carry surface only when their data is present: the "Also posted in" cross-post submenu appears only if the row has cross-post siblings; the moderation submenu appears only when the host reports the viewer moderates that community (Search reports not-a-moderator unless cheaply known, so it is normally omitted). Remind Me is post-scoped (`serverPostId`) and works in Search.

---

## 3. The five menus (items)

Titles use existing localized strings where an equivalent action already exists; new strings follow the same `NSLocalizedString` convention. Community/user copy uses the qualified `name@instance` handle.

### 3.1 Post (full parity)
Upvote, Downvote, Save/Unsave, Remind Me (submenu) | Reply, Share, Cross-post | Visit c/community, View u/author, Also posted in (submenu, when siblings) | Hide, Mute c/community (submenu) | Moderation (submenu, when viewer moderates) | Block author (destructive), Report (destructive).

### 3.2 Community
Open community, Subscribe/Unsubscribe, Mute/Unmute (client-local, by `communityActorId`), Share, Copy link, Block community (destructive). Mirrors Discover's `CommunityContextMenu` items, rebuilt in UIKit; reuses `lemmyService.setSubscribed`/`setBlocked` and the `AppDatabase` mute helpers (`muteCommunitySync`/`isCommunityMutedSync`/`unmuteCommunitySync`) the SwiftUI version already calls.

### 3.3 Comment
Open thread (the parent post), Upvote, Downvote, Save/Unsave, Share, Copy link, View author, Report (destructive). No Edit/Delete (own-comment) or moderation in this first cut — those are lower value from a search surface and need the fuller per-comment state; they can be added later if wanted.

### 3.4 User
Open profile, Copy handle, Share, Block/Unblock (destructive when blocking). Mirrors the two-action `PersonViewController` header menu plus Open/Share.

### 3.5 Instance
Open (the instance explore screen), Copy link, Share, Add account here (routes to the sign-in/add-account flow pre-targeted at this instance). Designed from scratch (no existing instance menu).

---

## 4. Data enrichment (no new network calls)

The Lemmy search endpoint already returns the fuller view objects; the thin result models simply don't map all fields. Enrich them (mapping-only) so the menus can be built:

- `SearchCommentResult` (+): `creatorPersonId` (View author), `serverCommunityId` + `communityActorId` (copy/share community context if needed), `isSaved` (Save toggle label), `myVote` (Upvote/Downvote selected state). All present on the search `CommentView`.
- `SearchCommunityResult` (+): `communityActorId`/URL (Share + Copy link), and subscribed/blocked state (Subscribe vs Unsubscribe, Block state) from the `CommunityView`. Mute state is client-local via `AppDatabase`.
- `SearchUserResult`: block state is not in the search `PersonView`; resolve `isBlocked` from the account's cached block list (the same source the profile menu uses) when available. When it cannot be determined, show a single "Block user" action rather than a toggle (blocking is idempotent).

Enrichment changes the mapping in `Spud/Scenes/Search/SearchResults.swift` and its construction site in `SearchViewModel`; it must not change existing cell rendering (the cells read a subset of the model and are snapshot-tested — the added fields are menu-only).

---

## 5. Signed-out, errors, dispatch

- **Sign-in gate:** every mutating action (vote/save/hide/mute/subscribe/block/report/reply/remind) reuses the existing signed-out gate (`presentSignInGate` / the `PostVoteDispatching` gate) — a signed-out user long-pressing and choosing a mutating action is prompted to sign in, exactly as in the feed. Read-only actions (Open, Share, Copy link, View author, Visit community) work signed-out.
- **Dispatch reuse:** vote/save/hide go through the same durable outbox the feed uses (`viewModel.accountScope.lemmyService` / outbox); subscribe/block go through `lemmyService`; mute is the client-local `AppDatabase` path; errors surface through the existing `AlertService` handling. No new persistence, no new migration.
- **Optimistic UI:** Search rows render from `SearchResults` (the fetched response), not a live GRDB observation, so a mutating action does not necessarily re-render the search row (e.g. a Save from search won't flip the search row's saved glyph live). This is acceptable for a first cut — the action still lands durably and the entity's own screen reflects it. Document this limitation rather than building live search-row observation.

---

## 6. Testing

- **Builder unit tests (new coverage, closes an existing gap):** for each builder, assert the produced `UIMenu`'s items given representative state — e.g. the post builder includes the moderation submenu when the host reports moderator, omits it otherwise; includes "Also posted in" only with siblings; a signed-out community builder still lists Open/Share/Copy but its mutating items route through the gate. Drive builders with a fake host conforming to the delegate protocol; assert on the returned menu tree (titles, `.destructive`, submenu presence). Today no test asserts any context menu's contents.
- **UITests for nav actions:** mirror the existing `SpudUITests.test_VisitCommunityFromPostContextMenu_showsNavbarActions` — a long-press on a search result -> menu action -> asserted pushed screen (at least: search post -> Visit community; search user -> Open profile; search community -> Open). Menus cannot be snapshotted (cells render in isolation), so nav coverage is a UITest.
- **Regression:** the feed menu must be unchanged after extraction — cover with a post-builder unit test asserting the full feed menu structure, and rely on the existing feed UITest.
- **No new snapshot refs** (context menus aren't snapshottable); existing `SearchResultCellsSnapshotTests` must stay byte-identical (enrichment is menu-only).

---

## 7. Out of scope (YAGNI)

- Live re-render of a search row after a mutating action (Search renders the fetched response, not a GRDB observation).
- Own-comment Edit/Delete and comment moderation from search (fuller per-comment state; add later if wanted).
- Adopting the new post builder in `PersonViewController` / `ActivityViewController` (they can adopt it later; not required for this feature).
- Any change to the SwiftUI `CommunityContextMenu` used in Discover (the UIKit `CommunityContextMenuBuilder` is a parallel, not a replacement).
- Context menu on the "Open in Spud" URL-paste row.

---

## 8. Suggested phasing (for the plan)

Each phase is independently shippable and testable:

1. **Post builder extraction + feed adoption + Search post menu** — the big one: `PostContextMenuBuilder` + `PostContextMenuHost`, `PostListViewController` refactored to consume it (feed menu unchanged), `SearchViewController` conforms + attaches for `.post`. Builder unit tests + a Search-post nav UITest.
2. **Community menu** — `CommunityContextMenuBuilder` + host, `SearchCommunityResult` enrichment, attach for `.community`. Unit tests + nav UITest.
3. **Comment menu** — `SearchCommentResult` enrichment, `CommentContextMenuBuilder` + host, attach for `.comment`. Unit tests.
4. **User menu** — `UserContextMenuBuilder` + host (with block-state resolution), attach for `.user`. Unit tests + nav UITest.
5. **Instance menu** — `InstanceContextMenuBuilder` + host (incl. Add account here), attach for `.instance`. Unit tests.

---

## 9. Docs

Update `docs/features/search.md` (Behavior + Given/When/Then scenarios: long-pressing each result type opens a menu; the post menu matches the feed; mutating actions gate when signed-out; read-only actions work signed-out). Update `docs/features/README.md` capability table + the "Feature coverage by area" map. Reconcile the adjacent `post-actions` / Discover docs if they claim menus are feed-only.
