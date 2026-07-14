# Instance meta communities — design

Date: 2026-07-14
Status: Approved (brainstorming) — ready for implementation planning
Branch: `feat/instance-meta-communities`

## Problem

Most Lemmy instances host a small number of "meta" communities that are *about the
instance itself* — e.g. `tchncs@discuss.tchncs.de`, `announcements@lemmy.world`,
`meta@beehaw.org`. They are local to the instance by definition and are where an
instance's news, changelogs, support, and site discussion live. Today Spud gives
them no special treatment: they are indistinguishable from any other community in a
list, and a user has no easy path to the meta communities of their *own* home
instance.

We want to:

1. **Identify** meta communities wherever community lists appear (Discover, instance
   browsing, search, the community screen) with a subtle badge.
2. **Surface the home instance's** meta communities front-and-center so they are easy
   to reach, with one-tap Subscribe / Favourite.

## Key constraint: detection is heuristic

Lemmy's API has **no field** that designates "this is the instance's meta community"
(`GetSiteResponse` carries `site_view`, `admins`, `taglines`, etc., but nothing
that names a meta community). Detection is therefore a **heuristic** over the
community's name/title, its home instance, and — when available — that instance's
site name. Meta-ness is **intrinsic to the community's own home instance**, not
relative to the viewing account: `tchncs@discuss.tchncs.de` is meta because it is
about discuss.tchncs.de, regardless of who is viewing.

## Decisions (from brainstorming)

- **Auto-action stance: suggest, one-tap opt-in.** Never auto-subscribe or
  auto-favourite. Because detection is heuristic and subscribing has real federation
  + feed side effects, the user always makes the final tap.
- **Detection breadth: broad keyword set** (+ locality + name-match). Higher recall;
  acceptable because we only *suggest*, never auto-act. False positives cost only a
  badge and a suggestion.
- **Home surface: a "About <instance>" section in the Communities tab**, always
  visible even when not subscribed. Also surface on any instance's About screen
  (near-free generalization).
- **Sourcing (Approach A): candidate-name resolution.** Resolve a fixed candidate
  name list against the home instance via the existing
  `LemmyService.fetchCommunityInfo(communityName:)` path; cache results. No
  enumeration of the (thousands-deep) local community list. Top-local scan is a
  possible later enhancement, not in v1.
- **Two-tier confidence** so broad detection does not make the home section noisy:
  badge everything in the broad set, but rank/gate the home *suggestions* by
  confidence.

## Non-goals (explicit scope guard)

- **No push-on-new-post.** Lemmy has no per-community push notification and Spud has
  none either. "Subscribe" here means the community joins the user's **Subscribed
  feed**; "Favourite" pins it for quick access. Building background per-community
  polling / push is a separate, much larger feature and is out of scope.
- **No auto-subscribe / auto-favourite.** See decisions above.
- **No top-local `listCommunities(type: Local)` scan** in v1 (candidate resolution
  only).
- **No curated per-instance map.** Detection is heuristic + name-match only.

## Architecture

Four cooperating pieces, smallest-first:

### 1. `MetaCommunityClassifier` (pure — SpudUtilKit)

A pure value-in / value-out classifier. No DB, no account, no I/O — trivially
unit-testable (Swift Testing, matching the test-migration direction).

```
struct MetaCommunityCandidate {
    let name: String            // community.name, e.g. "announcements"
    let title: String?          // community.title, human display
    let instanceHost: String    // community actor-id host, e.g. "lemmy.world"
    let siteName: String?       // that host's site name/title, when known
    let isLocalToViewer: Bool?  // CommunityRecord.isLocal, corroborating only
}

enum MetaConfidence { case high, low }

struct MetaClassification {
    let isMeta: Bool
    let confidence: MetaConfidence
    let reason: MetaReason      // .nameMatchesInstance / .strongKeyword / .broadKeyword
}

enum MetaCommunityClassifier {
    static func classify(_ candidate: MetaCommunityCandidate) -> MetaClassification
}
```

Rules (applied to a normalized name/title — lowercased, trimmed, separators
collapsed):

- **High confidence** when:
  - normalized name/title equals the instance's `siteName` (when known), or the
    instance's primary domain label (e.g. `discuss.tchncs.de` → `tchncs`, after
    stripping common subdomain prefixes like `discuss.` / `lemmy.` / `the.`); OR
  - keyword ∈ **strong set**: `meta`, `announcements`, `announcement`, `changelog`,
    `sitenews`, `site`, `instance`.
- **Low confidence** when keyword ∈ **broad set**: `support`, `help`, `feedback`,
  `news`, `updates`, `admin`, `welcome`, `general`, `lounge`, `rules`, `moderators`,
  `mods`.
- Otherwise `isMeta == false`.

Keyword sets live in one centralized, tunable `MetaCommunityKeywords` value so the
lists are easy to adjust without touching logic. Domain-label derivation is a known
fuzzy signal (see Risks) and is treated as *high* only when it also passes a
name-equality check, not a substring match — so `world@lemmy.world` does **not** get
flagged by the `world` domain label alone.

### 2. Badge in community lists (all surfaces)

A shared badge decision fed by the classifier, plus a small badge view rendered on
every community-row surface:

- `DiscoverCommunityRow` (SwiftUI) — Discover / instance-browse / See-all
  (`Spud/Scenes/Discover/DiscoverView.swift:409`, `RailDetailView.swift`,
  `InstanceRailDetailView.swift`).
- `SearchCommunityCell` (UIKit) — search (`Spud/Scenes/Search/SearchResultCells.swift:66`).
- `SubscriptionsCommunityRow` — Communities tab.
- A pill on `CommunityHeaderView` (`Spud/Scenes/Community/Content/CommunityHeaderView.swift`).

Treatment: a subtle tinted SF Symbol (candidate: `building.2` or `info.circle`) with
accessibility label "Instance community". The badge appears for the **broad** set
(both tiers). Exact glyph + copy finalized during implementation.

Row models differ and must not be conflated:
- `CommunityListRow` (`SpudDataKit/Services/AppDatabase/CommunityListRow.swift:17`) —
  directory-sourced, not account-scoped; has `name` + `instanceHost` but no `isLocal`
  and no site name. Keyword + name-match drive the badge here.
- `CommunityRecord` (`Records/Community.swift`) — account-scoped; has `isLocal`,
  `name`, `title`, `actorId`.

### 3. Home surface — "About <instance>" section (Communities tab)

A pinned section at the top of `SubscriptionsView` / `SubscriptionsViewModel`
(`Spud/Scenes/Subscriptions/`), **always visible even when not subscribed** — this
sidesteps the existing wrinkle that a favourite only shows in the Communities tab if
it is also subscribed.

- Each row renders the community + inline **Subscribe** and **Favourite** controls:
  - Subscribe reuses the optimistic subscribe outbox
    (`LemmyService.setSubscribed(serverCommunityId:subscribed:)`,
    `LemmyService.swift:1996`; states via `CommunitySubscribedState`,
    `Records/Community.swift:106`; button copy via
    `Spud/Utils/CommunitySubscribeButtonLabel.swift`).
  - Favourite reuses `FavoritedCommunityQueries`
    (`SpudDataKit/Services/AppDatabase/FavoritedCommunityQueries.swift`).
- **High-confidence** hits shown first; **low-confidence** hits tucked under a
  lightweight "More on this instance" disclosure so the section stays clean.
- **Nothing is auto-subscribed or auto-favourited** — one tap each.
- Empty/again-later states: if resolution has not completed, show a slim loading
  affordance consistent with the tab's existing loading treatment; if the instance
  genuinely has no detectable meta communities, omit the section entirely.

Home instance identity: `AccountScope.instanceActorId`
(`SpudDataKit/Services/Account/AccountScope.swift:62`) →
`InstanceActorId.hostWithPort`. Site name for name-matching comes from the home
instance's `SiteRecord` (`Records/Site.swift`) when loaded.

### 4. Instance About screen (bonus)

Render the same classified list on `InstanceAboutServerView` for **any** instance the
user visits (using that instance's host + site name), reusing the classifier + badge
+ a compact list. Generalizes the feature beyond the home instance and reinforces the
in-list labeling.

## Data + caching

Candidate resolution results are cached per instance so we resolve once and refresh
opportunistically rather than every launch.

New record (follows the `FavoritedCommunityRecord` pattern —
`Records/FavoritedCommunityRecord.swift` + `FavoritedCommunityQueries.swift` + a
migration in `AppDatabase+Migrations.swift`):

```
InstanceMetaCommunityRecord {
    instanceHost: String            // e.g. "discuss.tchncs.de"
    communityActorId: String        // resolved community actor id
    confidence: String              // "high" | "low"
    reason: String                  // MetaReason raw value
    discoveredAt: Date
}
```

- **Resolution service** (new, small — `SpudDataKit/Services/…`): given a host + site
  name, iterate the fixed candidate name list, call `fetchCommunityInfo(name@host)`,
  classify each hit, and upsert the meta ones into `InstanceMetaCommunityRecord`.
  Bounded to ~12 lookups per instance; deduped; cached.
- **Refresh triggers:** account setup / first appearance of the Communities tab /
  pull-to-refresh, throttled by `discoveredAt` (e.g. skip if refreshed within N
  hours). Exact cadence a v1 tuning detail.
- **Render:** the "About" section and the instance-About list read cached rows and
  **join live** subscribe state (`observeFollowedCommunities`,
  `Observations.swift:138`) and favourite state
  (`observeFavoritedCommunityActorIds`) at display time — cache holds *identity*, not
  mutable membership state.

## Data flow

```
Account home host ──▶ ResolutionService ──(fetchCommunityInfo × candidates)──▶ CommunityRecords
                             │
                             ▼  classify()
                    InstanceMetaCommunityRecord (cache, identity only)
                             │
        ┌────────────────────┼─────────────────────────┐
        ▼                    ▼                          ▼
 Communities-tab      Instance About            (badge everywhere:
 "About <instance>"   screen list                classifier runs inline
 section              (any instance)             per row, no cache needed)
        │                    │
        └── join live subscribe + favourite state at render ──┘
```

The **badge** does not depend on the cache — it runs the pure classifier inline per
row from data the row already carries. The **cache** exists only to power the home /
instance-About *sections*, which need to know the set of meta communities without the
user having scrolled past them.

## Error handling

- `fetchCommunityInfo` misses (community does not exist on the instance) are expected
  and non-fatal — the candidate is simply skipped. No user-visible error.
- Network failure during resolution leaves any prior cache intact and retries on the
  next trigger; the section shows whatever is cached (possibly empty). No blocking
  error UI.
- Signed-out / no home instance: the "About <instance>" section is omitted; badges
  still work wherever lists render.

## Testing

- **Classifier (unit, Swift Testing):** name-match (site name + domain label), strong
  vs broad keyword tiers, normalization (case, separators, non-Latin instance names),
  and negatives — critically `world@lemmy.world` must **not** be flagged by domain
  label alone; an ordinary `photography@lemmy.world` must not be flagged.
- **Resolution service:** with a stubbed `LemmyService`, verify bounded candidate
  lookups, correct classification, upsert/dedupe, and throttle-by-`discoveredAt`.
- **Rendering:** snapshot tests for the badge across row surfaces and for the "About
  <instance>" section (high-only, high+low disclosure, empty → omitted).
- **State join:** subscribe/favourite taps reflect optimistically and the section
  reads live membership state, not cached state.

## Risks / known limitations

- **Domain-label name-match is fuzzy.** Multi-label domains (`lemmy.world`) have no
  single unambiguous instance token. Mitigation: name-match is high-confidence only
  on **equality** with the site name or the stripped primary label, never substring;
  when in doubt it degrades to keyword-only. The site name (from `GetSite`) is the
  more reliable signal and is preferred when loaded.
- **Broad keywords mislabel some ordinary communities** (a general `news`/`general`
  community). Accepted per the breadth decision; contained because we only badge +
  suggest, low-confidence hits are de-emphasized, and the keyword set is centralized
  for easy tuning.
- **Candidate resolution misses oddly-named meta communities** not in the fixed list.
  Contained: the badge (broad keyword match) still flags them wherever they appear in
  lists; a top-local scan can be added later without reworking the model.

## Anchors (from codebase exploration)

- Community record + subscribe states: `SpudDataKit/Services/AppDatabase/Records/Community.swift`
- Favourites: `Records/FavoritedCommunityRecord.swift`, `FavoritedCommunityQueries.swift`, `CommunityViewModel.swift:179-206`
- Subscribe outbox: `Services/Outbox/OutboxOperation.swift`, `LemmyService.swift:1996`
- Home instance: `AccountScope.swift:62`, `AccountService.swift:452`, `SpudUtilKit/Extensions/InstanceActorId.swift`
- Community list rows: `SubscriptionsViewItemType.swift:15`, `Discover/DiscoverView.swift:409`, `Search/SearchResultCells.swift:66`, `AppDatabase/CommunityListRow.swift:17`
- Followed / favourite observations: `AppDatabase/Observations.swift:138`, `FavoritedCommunityQueries.swift:82`
