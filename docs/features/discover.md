# Discover (Community Explorer)

- **Surfaces:** `iphone`, `ipad`
- **Status:** planned
- **Related:** [Search](search.md), [Community screen](community-screen.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Subscriptions sidebar](subscriptions-sidebar.md), [Instance picker](instance-picker.md), [Signed-out browsing](signed-out-browsing.md), [Sign-in gate](sign-in-gate.md), [NSFW content visibility](nsfw-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Discover is a browsable home for finding new communities across the whole fediverse, reached from the Communities tab. Instead of a single flat list, it leads with curated and computed rails — Starter packs, Trending now, Rising, Because you follow, and Browse by instance — over the full, sortable community directory. It runs on bundled directory data, so it works signed-out and offline; following a community is the only part that needs an account. Communities that share a name across servers are collapsed into one entry you can expand to compare and pick from.

## Behavior and rules

- **Entry from the Communities tab.** The Communities tab keeps its "Search or explore communities" bar at the top of your subscriptions; tapping it pushes Discover. The search field routes into the existing scoped [Search](search.md) (Communities / Instances). Discover itself is browse, not search.
- **The landing is a stack of rails over the directory.** Top to bottom: **Starter packs**, **Trending now**, **Rising**, **Because you follow** (signed-in only; omitted otherwise), **Browse by instance**, then the **All communities** directory anchored at the bottom with a sticky sort control. Each rail has a "See all" that opens the full ranked list for that rail.
- **Ranking reflects life, not just size.** Rankings are computed from the directory's current snapshot (cumulative counts plus active-user windows for day / week / month / half-year); there is no time series.
  - **Trending now** — ordered by recent activity (`usersActiveWeek`), above a small noise floor, excluding suspicious communities.
  - **Rising** — communities below a size ceiling, ordered by engagement intensity (recent active users relative to subscriber base) above an activity floor. Surfaces small, accelerating communities.
  - **All communities** default sort is "Recommended" (the directory's composite `score`); other sorts are **Most active** (recent active users), **Members**, and **Name**. "Most posts" is intentionally not a lead sort — the stored post count is a cumulative total that favors old communities rather than active ones.
- **Same-name communities collapse into one entry.** In every rail and in the default directory, communities that share a name across servers are deduplicated to a single canonical row — the variant with the strongest blend of subscribers, recent activity, and instance trust. The row notes "also on N other servers · total members". Tapping that opens a **compare sheet** listing each variant with its members, recent activity, and instance trust, each with its own Follow, so the choice is deliberate. Dedupe is **off in raw search**, where you may be looking for one specific server's copy.
- **Starter packs are curated topics with live numbers.** Each pack is a hand-curated, ordered set of communities (a topic title, a short blurb, and a list of community references) whose names, icons, member counts, and activity are rendered live from the directory — so the curation is editorial but the stats never go stale. A pack screen lists its communities, each individually selectable, with a single **Follow all** action.
- **Curated surfaces stay clean (trust and safety).** Communities flagged suspicious are excluded from all rails and from the default directory; they are reachable only through raw search, and there they carry a caution badge. NSFW communities are hidden by default, honoring the app's global "Show NSFW" client preference (the same setting that governs the feeds — see [NSFW content visibility](nsfw-content.md)) regardless of sign-in state; when shown, they are badged. Communities on very low-trust instances are kept out of curated rails and carry a subtle instance indicator in the directory.
- **Because you follow is deterministic, not inferred.** When signed in with subscriptions, this rail combines two signals only: the same community name on other servers than the ones you already follow, and the most active communities on instances where you already follow at least one community. No topic modeling.
- **Following mirrors the rest of the app.** Follow / unfollow from any row, the compare sheet, or a starter pack calls the server and mirrors the confirmed result into local storage (confirm-then-mirror), feels instant, and fires a haptic on commit. A signed-out tap is gated with a "Sign in to follow" affordance and a warning haptic per the [Sign-in gate](sign-in-gate.md).
- **The community page shows vitality.** Opening a community shows a compact stat strip in its header — members, active this week, and posts — from the live community data, plus a tappable source-instance chip that opens that instance's card. See [Community screen](community-screen.md).
- **Live and offline.** The landing and directory observe the local directory data and update in place as it refreshes; with no network, the last bundled / fetched snapshot is shown. A periodic background refresh keeps the directory current.

## Scenarios

### Browse the Discover landing

- **Given** I am on the Communities tab
- **When** I tap the "Search or explore communities" bar
- **Then** Discover opens showing Starter packs, Trending now, Rising, Browse by instance, and the All communities directory
- **And** if I am signed in with subscriptions, a Because you follow rail also appears

### Follow a whole starter pack

- **Given** a starter pack with several communities while signed in
- **When** I open it and tap Follow all
- **Then** each community is followed (confirm-then-mirror, with a haptic) and the rows read Following
- **And** I can deselect individual communities before following so only the rest are added

### Pick among same-name communities

- **Given** a directory row for a name that exists on several servers, marked "also on N other servers"
- **When** I tap the badge
- **Then** a compare sheet lists each server's community with members, recent activity, and instance trust, each with its own Follow

### Sort the directory

- **Given** the All communities directory
- **When** I open the sort control and choose Most active
- **Then** the list re-sorts by recent active users, keeping same-name entries collapsed

### Trending surfaces the busy, Rising surfaces the small-and-active

- **Given** the Discover landing
- **When** I read the Trending now and Rising rails
- **Then** Trending lists the communities with the most recent activity, and Rising lists smaller communities whose recent activity is high for their size

### A signed-out follow is gated

- **Given** I am browsing Discover signed out
- **When** I tap Follow on any community
- **Then** a "Sign in to follow" affordance and a warning haptic are shown, and no call is made

### NSFW and suspicious communities are kept out by default

- **Given** the global Show NSFW setting is off and I am browsing the landing or default directory
- **When** the rails and directory render
- **Then** NSFW communities are hidden and suspicious communities do not appear; suspicious communities surface only in raw search, badged

## Not supported / out of scope

- **No topic auto-grouping or category browser.** The only topical organization is the hand-curated Starter packs; communities are not auto-sorted into topics or categories (the directory has no reliable topic field, and name-keyword bucketing is too error-prone).
- **No trend graphs or real-time counts.** Trending and Rising are heuristics over a periodic snapshot, not live or historical time series; the directory's numbers are as fresh as the last refresh, not live.
- **Not content search.** Discover browses communities; searching posts / comments / users stays in the [Search](search.md) tab.
- **Communities only.** Instance discovery is reached *through* Discover (Browse by instance) but is governed by the [Instance picker](instance-picker.md) and the instance directory, not redefined here.

## Design notes (data, ranking, architecture)

Non-obvious decisions and the data they rest on. Not end-user behavior; kept here so an implementer or a future design iteration has the rationale.

- **Source data.** The local explorer directory (~26K communities, ~505 instances) bundled and refreshed from `data.lemmyverse.net`. Per community we hold name, title, description, icon/banner, instance, NSFW, subscribers, posts, comments, active users (day/week/month/half-year), a composite `score`, and a suspicious flag. Per instance we hold user counts, community count, uptime, latency, a trust `score`, registration mode, languages, tags, NSFW, and federation/block counts.
- **Ranking is pure and testable.** A new directory component (mirroring the instance directory's pure sort/filter helper) takes the rows plus a sort, filter, and dedupe rule and returns sectioned output. Trending, Rising, the dedupe canonicalization, and the safety filters are all pure functions over the snapshot — no LLM, no network — so they unit-test directly.
  - *Trending* ≈ `usersActiveWeek` desc, floor on minimum recent activity.
  - *Rising* ≈ among `numberOfSubscribers` below a ceiling, order by recent active users relative to subscriber base (e.g. `usersActiveWeek / sqrt(numberOfSubscribers)`), with an activity floor. Thresholds are tunable.
  - *Canonical (same-name)* = best blend of subscribers, `usersActiveWeek`, and instance trust among rows sharing a `name`.
- **Starter packs ship as a small resource.** A bundled `starter-packs.json` (≈12–20 entries of `{ id, title, blurb, communityActorUrls: [...] }`) joined live to the directory at render time. Curation in the file; stats from the DB.
- **No schema change required.** All fields already exist; add sort indexes (e.g. on `numberOfSubscribers`, `usersActiveWeek`) for snappy re-sorts. New reactive queries provide the landing rails, the sortable directory, and the "because you follow" join from followed communities to the directory.
- **Reuses prior work.** The instance directory and instance detail built for the [Instance picker](instance-picker.md) back the Browse-by-instance lens; the [Search](search.md) scope toggle and same-name disambiguation are reused for the search entry; the [Subscribe / unsubscribe](subscribe-unsubscribe.md) flow handles Follow.
