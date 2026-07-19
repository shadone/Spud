# Community new-posts follow — design

Date: 2026-07-19
Status: approved

## Problem

The instance-meta-communities feature surfaced "about this instance" communities
(announcements, site news) and made them one tap to Favourite or Subscribe — but
subscribing only folds posts into the feed. There is no way to be *notified* when a
community (meta or otherwise) gets a new post, because Lemmy has no push. The
post-reminders feature later built exactly the substrate that works around this: a
local, durable, per-account follow store + a foreground poll (5-minute scheduler
tick, 30-minute per-item throttle) + best-effort `BGAppRefreshTask` + local
notifications + the Inbox Reminders segment. This feature extends that substrate
from "watch a post's comments" to "watch a community's posts".

## Decision summary

A third reminder kind, `communityPosts`, in the existing `reminder` table — **no
schema migration**. The community's server id rides in the existing target column
(`postServerId`), `rootCommentServerId` stays at the whole-post sentinel `0`, and
the existing unique key `(accountId, postServerId, rootCommentServerId, kind)`
gives one live follow per community per account. Post ids and community ids are
different id spaces, but `kind` disambiguates every read, so collisions are
impossible.

Column reuse for `communityPosts` rows (documented on `ReminderRecord`):

| Column | Meaning for `communityPosts` |
|---|---|
| `postServerId` | the community's server id (home-instance-local) |
| `rootCommentServerId` | always `0` (`wholePostSentinel`) |
| `apId` | the community's federation `actorId` |
| `titleSnapshot` | community display title (fallback: name) |
| `communityName` / `instanceHost` | as today — also the navigation target |
| `thumbnailUrl` | community icon URL |
| `baselineAt` | the **watermark**: newest post `published` seen (creation: now) |
| `baselineCount` | unused (`nil`) |
| `nextCheckAt` | next poll due time, as for `activity` |
| `fireAt` | unused (`nil`) — community follows never schedule up-front |

Rejected alternative: a parallel `communityFollow` table + service. Cleaner
column names, but it duplicates the poll loop, notification scheduling, Inbox row
type, unseen/badge blending, mark-seen, swipe-remove, and account teardown — and
the Inbox list would need a union of two observations. The column-reuse cost is
purely naming, mitigated with doc comments and a `communityServerId` computed
alias on `ReminderRecord`.

## Detection & firing

- **Fetch seam.** New public `LemmyService` wrapper (mirrors `fetchPostInfo` /
  `fetchSubtreeChildCount`): fetch the community's newest posts —
  `api.getPostsNeutral(listingType: .All, sort: .New, communityId:, pageCursor: nil)`,
  one page, fixed limit (constant, ~20). No feed row is created; the response is
  read directly, not persisted (mirror of posts is unnecessary — only `published`
  stamps are consumed).
- **Poll.** A new `ReminderService.pollDueCommunityFollows(asOf:postDatesFetcher:)`
  alongside `pollDueActivityReminders`, same shape: reads due `communityPosts`
  rows, calls a `@Sendable (Int64) async -> [Date]?` fetcher (the published dates
  of the newest page; `nil` = fetch failed). `newPosts = dates.filter { $0 > watermark }.count`.
- **Rule: ≥ 1 new post fires** (`CommunityFollowRule`, parallel to
  `ReminderActivityRule` but without the 5-or-24h shape — meta/announcement
  communities post rarely; holding notifications back would defeat the use case).
  Batched per check: one notification regardless of count. If the count saturates
  the fetch limit, the body reads "20+ new posts".
- **Re-arm on fire:** watermark := max published seen, `status = fired`,
  `unseen = true`, `nextCheckAt = now + 30 min` — keeps watching, like `activity`.
  On zero new / failed fetch: bump `nextCheckAt` only.
- **Watermark at creation is device-now.** No network call on toggle (instant UI).
  Re-arming to server-published timestamps self-corrects clock skew after the
  first fire. Known best-effort edges (accepted): a device clock ahead of the
  server can miss posts published inside the skew window right after following; a
  post *federated late* with an older `published` never fires.
- **Scheduler wiring.** `SchedulerService`'s existing reminder sweep additionally
  calls the community poll per pollable account (signed-in and signed-out), with a
  fetcher built over the new `LemmyService` wrapper. The `BGAppRefreshTask` path
  (`runReminderPoll()`) inherits this for free — no new task identifier.
- **Mute interplay:** the sweep's fetcher skips muted communities
  (`isCommunityMutedSync` by actorId) — poll bumps `nextCheckAt`, watermark
  untouched. After unmute, accumulated posts fire once as one batch.
- **Block interplay:** the Block Community action also removes any live follow for
  that community (blocking is an explicit "never show me this").
- Subscribe/unsubscribe and Favourite are fully independent of the follow.

## Notification & Inbox

- **Content** (`ReminderNotificationFactory.communityFollowContent`): title = the
  community title, body = "N new post(s) in c/<name>@<instance>" (count-only — no
  post titles, so nothing NSFW leaks into the notification), routing URL =
  `URL.SpudInternalLink.community(name:instance:)`. Delivered via the existing
  `scheduler.postNow`; nothing is scheduled up-front, so there is no OS request to
  cancel on removal.
- **Inbox Reminders segment:** `communityPosts` rows appear as sibling rows.
  Thumbnail = community icon, title = community title, handle line =
  `c/<community>@<instance>` as today. `ReminderStatusText`: live — "Watching for
  new posts"; fired — "New posts · tap to catch up". Tap navigates to the
  community screen (`.community(name:instance:)` — a kind branch in
  `openReminder`, which today builds `objectAtURL` from `apId`). Swipe-to-remove,
  unseen dot, badge contribution, and mark-seen-on-open all inherit unchanged.
- **Account teardown** inherits: `removeAllReminders` is kind-agnostic, and
  community follows have no scheduled OS notification to cancel.

## Entry points ("Notify About New Posts")

All surfaces use one centralized copy/symbol helper (the
`CommunitySubscribeButtonLabel` pattern): menu title "Notify About New Posts",
checkmark when live, toggle on tap; bell symbols `bell.badge` / `bell.badge.fill`
(NOT `bell`/`bell.slash`, which Mute/Unmute already use in the same menus); toasts
"You'll be notified of new posts." / "Stopped notifying."

1. **Community screen overflow menu** — a deferred action in the state group next
   to Subscribe / Favorites (`CommunityViewController`). Also the header
   long-press context menu.
2. **Search community context menu** — new host method + inline item after the
   subscribe group in `CommunityContextMenuBuilder` (identity available:
   `serverCommunityId`, `name`, `instance`, `communityUrl`).
3. **Communities tab, "About <instance>" meta rows** — a bell toggle button next
   to the Favourite star in `MetaCommunityAboutRow` (this is the payoff of the
   original meta-communities ask; `MetaCommunityListItem` already carries id,
   actorId, title, icon). Available signed-in and signed-out, like all follows.
4. **Communities tab, subscribed-list row context menu** — new item in the
   existing Open/Copy/Share menu (verify at implementation time that the row's
   `id` is the community server id; if not, resolve via `communityRowIdSync`
   helpers).

**Deferred: Discover surfaces.** Discover rows can be unresolved directory
entries with no home-instance server id; following one would first require a
`resolve_object` round-trip. Out of scope here (documented), consistent with
Discover's menu already omitting Favourite.

Follow creation captures: community server id, actorId, name, title, instance
host, icon URL — all available at each in-scope surface.

## Testing

Existing seams carry over: injected `ReminderNotificationScheduling` fake,
pure-clock `asOf`/`now`, injected fetcher closure (network-free), in-memory
`AppDatabase`.

- `CommunityFollowRule` unit tests (threshold, saturation phrasing input).
- `ReminderService` community-follow tests: create/toggle/remove, watermark
  baseline + re-arm, fire on ≥1, no-fire on zero/failed fetch, throttle bump,
  uniqueness per community, no cross-talk with a post whose server id equals a
  community id.
- `ReminderStatusText` + notification-content tests for the new kind.
- Inbox VM remove-dispatch test for the new kind; menu-builder unit tests
  (checkmark state, item placement) per surface.
- Snapshot: `RemindersSegmentSnapshotTests` gains community-row states (watching /
  fired); meta-row bell states in the Subscriptions snapshot if one exists.
- Mute-skip and block-removal covered at the service/sweep level with fakes.

## Out of scope

- Real push — delivery remains foreground poll + opportunistic background
  refresh, best-effort by design (same honesty as reminders.md).
- Discover entry points (above).
- Per-follow rule tuning (e.g. digest thresholds) — the rule is fixed at ≥1.
- Auto-following meta communities — everything stays suggest-only, one explicit
  tap.

## Docs to update

`docs/features/reminders.md` (new follow type, rule, entry points),
`docs/features/instance-meta-communities.md` (bell action; delete the "no push
notification on new posts" out-of-scope claim), `docs/features/inbox.md` (row
type), `docs/features/community-screen.md`, `docs/features/subscribe-unsubscribe.md`
(menu items + independence), search context-menus doc if it enumerates items,
and `docs/features/README.md` — both the capability table and the by-area map
(the map's meta-communities line explicitly says "no push notification on new
posts" and must be revised).
