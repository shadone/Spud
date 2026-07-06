# Discover (Community Explorer)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped.
- **Related:** [Search](search.md), [Community screen](community-screen.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Subscriptions sidebar](subscriptions-sidebar.md), [Instance picker](instance-picker.md), [Instance browsing](instance-browsing.md), [Signed-out browsing](signed-out-browsing.md), [Sign-in gate](sign-in-gate.md), [NSFW content visibility and blur](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Discover is a browsable home for finding new communities across the whole fediverse, reached from the Communities tab. Instead of a single flat list, it leads with curated and computed rails — Starter packs, Trending now, Rising, Because you follow, and Browse by instance — over the full, sortable community directory. It runs on bundled directory data, so it works signed-out and offline; subscribing to a community is the only part that needs an account. Communities that share a name across servers are collapsed into one entry you can expand to compare and pick from. While searching, an optional live-network search finds communities that aren't in the bundled directory.

## Behavior and rules

- **Entry from the Communities tab.** Discover is pushed from the "Discover communities" entry above the subscriptions list. Discover has its **own** navigation search field ("Search all communities") and sort control — it is a self-contained browse-and-search screen, not a hand-off into the [Search](search.md) tab.
- **The landing is a stack of rails over the directory.** Top to bottom: **Starter packs**, **Trending now**, **Rising**, **Because you follow** (signed-in only, and only when it has results; omitted otherwise), **Browse by instance**, then the **All communities** directory. Each computed rail (Trending / Rising / Because you follow / Browse by instance) shows its top 12 in a horizontal carousel with a **"See all"** that pushes the full ranked list (Starter packs has no "See all" — the whole curated set is shown). While the user is searching, the rails step aside and only the filtered directory (plus the optional network-search section) is shown.
- **Sorting the directory.** The "All communities" sort is a navigation-bar menu (Recommended / Most active / Members / Name / Newest); the directory header shows the active sort as a label. There is no inline sticky sort control on the landing. (The instance drill-in has its own inline sort picker.)
- **Ranking reflects life, not just size.** Rankings are computed from the directory's current snapshot (cumulative counts plus active-user windows for day / week / month / half-year); there is no time series.
  - **Trending now** — ordered by recent activity (`usersActiveWeek`), above a small noise floor, excluding suspicious communities. The carousel shows the top 12; "See all" opens the full ranked list (as a directory-style list of rows).
  - **Rising** — communities below a size ceiling, ordered by engagement intensity (recent active users relative to subscriber base) above an activity floor. Surfaces small, accelerating communities. Carousel + "See all" as above.
  - **Browse by instance** — the liveliest home instances by aggregate weekly activity (carousel of 12; "See all" opens the full ranked instance list). Tapping an instance opens that server's communities, with a tappable instance info card (members, description, trust) that drills into the richer [Instance browsing](instance-browsing.md) detail.
  - **All communities** default sort is "Recommended" (the directory's composite `score`); other sorts are **Most active** (recent active users), **Members**, **Name**, and **Newest**. While browsing, the directory is capped at the first 200 rows for snappiness; a search shows every match. "Most posts" is intentionally not a lead sort — the stored post count is a cumulative total that favors old communities rather than active ones.
- **Same-name communities collapse into one entry.** In the default directory, communities that share a name across servers are deduplicated to a single canonical row — the variant with the strongest blend of subscribers, recent activity, and instance trust. The row notes "also on N other servers · total members". Tapping that badge opens a **compare sheet** listing each variant ranked busiest-first, with members and recent activity, each with its own **Subscribe** (and a tap-through to open the community). Dedupe is **off in the live network-search results**, where you may be looking for one specific server's copy.
- **Starter packs are curated topics with live numbers.** Each pack is a hand-curated, ordered set of communities (a topic title, a short blurb, and a list of community references) whose names, icons, member counts, and activity are rendered live from the directory — so the curation is editorial but the stats never go stale. Tapping a starter pack opens a dedicated Pack detail screen listing the pack's communities, each individually subscribable, with a single **Subscribe to all** action that subscribes to the ones you don't already have.
- **Search the bundled directory, then the network.** The search field filters the bundled directory instantly. Below the local matches, an optional "Search the network for X" button runs a live Lemmy community search; results not already in the local directory are shown under a "From the network" header (NSFW-gated by the same client preference), each subscribable. The network search re-runs on tap if it fails.
- **Long-press a community for quick actions.** Any community row or rail card exposes a context menu: Open community, Subscribe / Unsubscribe, Mute (a submenu of durations) / Unmute, Share, Copy link, and Block community. Mute is client-local (keyed by the community's actor id, works for any account, no server round-trip); Block and Subscribe hit the server.
- **Curated surfaces stay clean (trust and safety).** Communities flagged suspicious are excluded from all rails and from the default directory. NSFW communities are hidden by default, honoring the app's global "Show NSFW" client preference (the same setting that governs feeds, Search, and the composer community picker — see [NSFW content visibility and blur](nsfw-content.md)) regardless of sign-in state; when shown, they are badged. If "Blur NSFW" is also on, NSFW community icons in Discover are blurred. Both preferences are observed live, so toggling either in Settings (or the post-list Quick Switch) re-filters / re-renders an open Discover in place.
- **Because you follow is deterministic, not inferred.** When signed in with subscriptions, this rail surfaces the most active communities (not already subscribed) on the instances where you're already subscribed to at least one community. No topic modeling. It is omitted when signed out or when it has no results. (The rail keeps the name "Because you follow"; the underlying action everywhere is Subscribe.)
- **Subscribing mirrors the rest of the app.** Subscribe / unsubscribe from any row, rail card, or starter pack first resolves the Explorer row to a server community id, then applies the change through the same durable, optimistic mutation outbox used everywhere else (see [Subscribe / unsubscribe](subscribe-unsubscribe.md)) — the local subscribed state updates the instant that resolve completes, without waiting on the follow request itself. An in-flight spinner shows on the row while the id is resolving, and a haptic fires on commit. A permanent failure rolls back and surfaces the shared outbox failure toast rather than reverting silently. Communities the account is already subscribed to read "Subscribed" from the first render. A signed-out tap is gated with a "Sign in to subscribe" affordance and a warning haptic per the [Sign-in gate](sign-in-gate.md).
- **The community page shows vitality.** Opening a community shows a compact stat strip in its header — members, active this week, and posts — from the live community data, plus a tappable source-instance chip that opens that instance's card. See [Community screen](community-screen.md).
- **Live and offline.** The landing and directory observe the local Explorer directory and update in place. Opening Discover refreshes the community directory from the network when it is older than your Community Data refresh interval (default daily) and automatic updates are on — streamed part-by-part in the background and folded into the open screen live. With no network, the last bundled / fetched snapshot is shown.
- **Adaptive layout on iPad.** On a regular-width iPad, the rails (Starter packs, Trending, Rising, etc.) render as an adaptive multi-column grid rather than horizontal carousels. The All communities directory is width-capped and centered rather than stretching edge-to-edge. Tapping a community opens it in the Communities tab's two-column reading split (see [iPad split-view handoff](ipad-split-view.md)); the Communities tab stays active, not the Posts tab.

## Scenarios

### Browse the Discover landing

- **Given** I am on the Communities tab
- **When** I tap the "Discover communities" entry
- **Then** Discover opens showing Starter packs, Trending now, Rising, Browse by instance, and the All communities directory
- **And** if I am signed in with subscriptions on shared instances, a Because you follow rail also appears

### Subscribe to a whole starter pack

- **Given** a starter pack with several communities while signed in
- **When** I open it and tap Subscribe to all
- **Then** each not-yet-subscribed community is subscribed (optimistically and durably, with a haptic) and the rows read Subscribed
- **And** I can subscribe to communities individually instead

### Pick among same-name communities

- **Given** a directory row for a name that exists on several servers, marked "also on N other servers"
- **When** I tap the badge
- **Then** a compare sheet lists each server's community ranked busiest-first, with members and recent activity, each with its own Subscribe (or I tap a row to open it)

### Sort the directory

- **Given** the All communities directory
- **When** I open the sort menu in the navigation bar and choose Most active
- **Then** the list re-sorts by recent active users, keeping same-name entries collapsed

### Search beyond the bundled directory

- **Given** I am searching for a community that isn't in the bundled directory
- **When** I tap "Search the network for …"
- **Then** a live Lemmy community search runs and shows matching communities not already listed, each followable

### Trending surfaces the busy, Rising surfaces the small-and-active

- **Given** the Discover landing
- **When** I read the Trending now and Rising rails
- **Then** Trending lists the communities with the most recent activity, and Rising lists smaller communities whose recent activity is high for their size

### See all of a rail

- **Given** a rail (Trending / Rising / Because you follow / Browse by instance) with more than the 12 shown in its carousel
- **When** I tap its "See all"
- **Then** a screen pushes with the full ranked list — communities as directory-style rows (Subscribe / open / long-press actions), instances as a tappable list that opens each server's communities

### A signed-out subscribe is gated

- **Given** I am browsing Discover signed out
- **When** I tap Subscribe on any community
- **Then** a "Sign in to subscribe" affordance and a warning haptic are shown, and no call is made

### Tapping a starter pack opens the pack detail

- **Given** I am browsing Discover
- **When** I tap a starter pack
- **Then** a dedicated Pack detail screen opens, listing the pack's communities, each individually subscribable, with a "Subscribe to all" action

### NSFW and suspicious communities are kept out by default

- **Given** the global Show NSFW setting is off and I am browsing the landing or default directory
- **When** the rails and directory render
- **Then** NSFW communities are hidden and suspicious communities do not appear

## Not supported / known gaps

- **The community directory refreshes on demand, not via a background task.** It is seeded from the bundle, then refreshed from the network when you **open Discover** (if it is stale per your Community Data refresh interval and automatic updates are on — `ExplorerService.refreshCommunitiesIfStale`), or on Settings → "Update Now" (`ExplorerService.refreshAll`). The smaller **instance** directory refreshes at launch / when the instance picker opens. The multi-MB community set is refreshed on-demand (on Discover open) rather than at launch, so launch never triggers a large download. There is no `BGAppRefreshTask` / periodic timer — refresh is tied to opening the relevant screen.
- **No topic auto-grouping or category browser.** The only topical organization is the hand-curated Starter packs; communities are not auto-sorted into topics or categories (the directory has no reliable topic field, and name-keyword bucketing is too error-prone).
- **No trend graphs or real-time counts.** Trending and Rising are heuristics over a periodic snapshot, not live or historical time series; the directory's numbers are as fresh as the last refresh, not live.
- **Not content search.** Discover browses communities; searching posts / comments / users stays in the [Search](search.md) tab.
- **Communities-first.** Instance discovery is reached *through* Discover (Browse by instance) but is governed by [Instance browsing](instance-browsing.md) and the instance directory, not redefined here.
- **"See all" detail screens aren't separately snapshotted.** The assembled landing has a full-screen snapshot (`DiscoverScreenSnapshotTests`) and every building block has a component snapshot (`DiscoverSnapshotTests`); the per-rail "See all" detail screens are thin compositions of those already-covered rows, so they have no dedicated snapshot.

## Design notes (data, ranking, architecture)

Non-obvious decisions and the data they rest on. Not end-user behavior; kept here so an implementer or a future design iteration has the rationale.

- **Source data.** The local explorer directory (~26K communities, ~505 instances) bundled and refreshed from `data.lemmyverse.net`. Per community we hold name, title, description, icon/banner, instance, NSFW, subscribers, posts, comments, active users (day/week/month/half-year), a composite `score`, and a suspicious flag. Per instance we hold user counts, community count, uptime, latency, a trust `score`, registration mode, languages, tags, NSFW, and federation/block counts.
- **Ranking is pure and testable.** `ExplorerCommunityDirectory` is a pure sort/filter/dedupe helper (mirroring the instance directory's) that takes the rows plus a sort, filter, and dedupe rule and returns sectioned output. `trending`, `rising`, `topInstances`, `becauseYouFollow`, the same-name `variants`/dedupe canonicalization, and the safety filters are all pure functions over the snapshot — no LLM, no network — and are unit-tested directly (`ExplorerCommunityDirectoryTests`, 20 cases).
  - *Trending* ≈ `usersActiveWeek` desc, floor on minimum recent activity (`defaultTrendingMinActiveWeek = 50`).
  - *Rising* ≈ among `numberOfSubscribers` below a ceiling (`defaultRisingMaxSubscribers = 25_000`), ordered by recent active users relative to subscriber base (`usersActiveWeek / sqrt(numberOfSubscribers)`), with an activity floor (`defaultRisingMinActiveWeek = 100`). Thresholds are constants in the helper, not user-configurable.
  - *Canonical (same-name)* = best blend of subscribers, `usersActiveWeek`, and instance trust among rows sharing a `name`.
- **Starter packs ship as an in-code catalog, not JSON (yet).** `StarterPackCatalog` is a small set of hand-curated packs embedded in Swift (`StarterPack.swift`, currently 6 packs of `{ id, title, blurb, communityActorUrls: [...] }`), joined live to the directory at render time by actor id (`StarterPackCatalogTests`). A bundled `starter-packs.json` was anticipated in the original design but deferred — the resolver and UI don't care which backs it, so it can be swapped later without UI changes.
- **No schema change required.** All fields already exist. New reactive queries provide the landing rails, the sortable directory, and the "because you follow" join from followed communities to the directory.
- **Rails are ranked deeper than they show.** Each computed rail is ranked `railDepth` (60) deep but the landing carousel renders only the first `railCarouselCount` (12); "See all" pushes the rest (`RailDetailView` for communities — reusing `DiscoverCommunityRow` so Subscribe / context-menu / open behave identically — and `InstanceRailDetailView` + `InstanceRow` for instances). The "See all" affordance appears only when a rail has more than the carousel shows. Computing 60 vs 12 is the same pure pass over the snapshot, so there's no extra fetch.
- **Directory freshness.** The community directory is refreshed on-demand when Discover appears (`DiscoverViewController.viewDidAppear` → `ExplorerService.refreshCommunitiesIfStale`), gated by the `explorerAutoRefreshEnabled` preference and the `explorerRefreshInterval` staleness window, with an actor-held in-flight guard so repeated opens can't start concurrent multi-MB downloads. The instance directory keeps its launch / picker-open refresh. This is what makes the **Community Data** settings actually govern the community dataset (previously they applied only to instances).
- **Reuses prior work.** The instance directory and instance detail built for [Instance browsing](instance-browsing.md) back the Browse-by-instance lens and the instance drill-in's "before you commit" detail; the [Subscribe / unsubscribe](subscribe-unsubscribe.md) flow handles subscribing.
