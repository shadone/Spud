# Instance-detail "About this instance" meta section — design

Date: 2026-07-19
Status: approved

## Problem

The instance-meta-communities feature deferred its Task 12: the instance-detail
screen (`Spud/Scenes/Account/InstanceDetail/`) badges meta communities inside
community lists but has no dedicated section, so someone evaluating an instance
can't see its announcement/meta communities at a glance. Everything needed
already exists: `MetaCommunityService.refreshInstance(host:siteName:forAccountKeychainId:)`
takes an arbitrary host (its doc comment names this screen as the intended
caller), `LiveMetaCommunityResolver` probes `name@host` through the acting
account's HOME instance — mirroring hits into the home `community` table, which
gives every resolved row a home-instance server id — and the v38
`instanceMetaCommunity` cache plus `observeMetaCommunities(forAccountId:instanceHost:)`
are keyed per `(account, instanceHost)`. Because rows resolve to home server
ids, Subscribe, Favourite, and the community new-posts follow ("Notify About
New Posts") all work here with no new resolution machinery.

## Decisions (user-approved)

- **Row actions via long-press context menu** (tap = open the community);
  no inline star/bell/pill — keeps the screen's compact card design clean and
  matches the Search-results pattern.
- **Hidden pre-account.** The section renders only when the app has a default
  (non-service) account — signed-in or signed-out. Onboarding / add-account
  presentations of this screen are unchanged. No directory-classified fallback.

## Data flow

- **Trigger:** in the screen's existing secondary-data load, when a default
  account exists, fire-and-forget
  `metaCommunityService.refreshInstance(host: record.baseurl, siteName: record.name, forAccountKeychainId: <default account>)`.
  The explicit `siteName` comes from the Explorer record (this is NOT the
  account's home site, so the DB fallback would be wrong — exactly the case the
  parameter was kept for). 24h freshness, per-(account,host) in-flight guard,
  and never-overwrite-on-all-miss all inherit from the service.
- **Observation:** `observeMetaCommunities(forAccountId:instanceHost: record.baseurl)`
  drives the section, appended to the screen's existing observation-task list.
  Items carry home-resolved `serverCommunityId`, name, title, actorId, icon,
  confidence, live `subscribedState`, `isFavorite`.
- **Acting account** = the default account at presentation time. All actions go
  through that account's `AccountScope`.
- Cost note (accepted): probing an un-cached instance is ~10-14 `resolve_object`
  calls against the home instance, engagement-gated (only on opening the detail
  screen) and bounded by the 24h cache — same shape as the home-instance probe.

## Rendering

- A new card in the body stack placed **immediately above the existing
  Communities card**: `InstanceSectionHeader` titled "About this instance" with
  the item count, then one row per cached meta community — high-confidence
  first (the observation already orders this way), all items shown (the
  candidate list bounds the size).
- Rows visually match the Communities card's rows (icon, display name, chevron)
  and carry the shared "Instance community" badge glyph. Reuse
  `InstanceCommunityRowView` if it can host the badge cleanly; otherwise a
  minimal sibling row view in the same visual style.
- The section is **absent** (not empty-stated, no placeholder) when: no default
  account, the cache is empty, or classification found nothing. It appears/
  updates live when the observation yields items.

## Interactions

- **Tap** opens the community in-app via the internal community link
  (rows are resolved, so name+instance always work).
- **Long-press** shows the community context menu via the existing
  `CommunityContextMenuBuilder`, driven by a `SearchCommunityResult` adapter
  built from the row (server id, name, qualified name, instance, icon,
  actorId as `communityUrl`; display-only fields the menu ignores may be
  defaulted). Menu contents: Open Community / Subscribe-Unsubscribe (signed-in
  only, 5-state resolved label) / **Add to Favorites - Remove from Favorites**
  (new, see below) / Notify About New Posts / Mute-Unmute / Share / Copy Link /
  Block Community.
- **Builder extension — optional Favourite action:** `CommunityContextMenuHost`
  gains favourite methods with default implementations (state accessor
  defaulting to nil = "surface doesn't offer Favourite"); the builder inserts
  the Favorites action (after Subscribe) only when the host reports a state.
  Search's host is untouched and inherits the defaults. The Favorites copy
  ("Add to Favorites" / "Remove from Favorites" + star symbols) is centralized
  in a small label helper (the `CommunityNotifyLabel` pattern) and
  `CommunityViewController`'s existing overflow action is refactored to consume
  it — the same copy must never live in two places.
- **Block keeps the follow invariant:** this menu's Block handler must also
  remove a live new-posts follow for the community (fourth block call site;
  same fire-and-forget shape as the existing three).
- Favourite and Notify work signed-out (local, per-account); Subscribe is
  sign-in gated exactly as elsewhere.

## Dependencies / cascade

Adding `HasMetaCommunityService` to `InstanceDetailViewController.OwnDependencies`
cascades into every VC spelling out `NestedDependencies` manually and into the
snapshot/unit test doubles that construct them (the known linker-trap: a missed
double fails at TEST-target link time while `make build` passes). The
implementation must build the full test plan and stub every affected double.

## Testing

- Unit: builder favourite-extension (action present only when host provides
  state, title/state correctness, dispatch), the SearchCommunityResult adapter
  mapping, account-gating rule (no default account -> no refresh, no section),
  block-removes-follow wiring at the new call site.
- Snapshot: extend the existing instance-detail snapshot suite with a seeded
  meta-section state (cache rows + community rows in the in-memory DB).
- Existing service/cache/classifier tests already cover the cross-instance
  resolution path; no changes there.

## Out of scope

- Directory-classified pre-account fallback (decided against).
- The "Browse all communities" list (`InstanceExploreViewController`) — no meta
  section there; its rows keep whatever badging they already have.
- Auto-anything: the section is suggest-only, same philosophy as the
  Communities-tab section.
- Discover surfaces (unchanged; still no follow entry points there).

## Docs to update

The instance-detail / instance-browsing feature doc (add the section +
scenarios), `instance-meta-communities.md` (remove the DEFERRED Task-12 note,
document the new surface, reconcile Related:), `community-context-menus` /
search doc if it enumerates the builder's items (Favorites is host-optional —
note Search doesn't show it), `community-new-posts-follow` coverage in
`reminders.md` entry-point list (now six entry points), and
`docs/features/README.md` — BOTH the capability table and the by-area map.
