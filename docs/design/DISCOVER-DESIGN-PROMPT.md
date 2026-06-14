# Claude Design prompt — Spud Discover (Community Explorer)

Paste the block below into Claude Design inside the **Spud** project. It assumes the existing
Spud files are present (`design-canvas.jsx`, `phone.jsx`, `unified-shell.jsx`,
`screens-common.jsx`, `app-kit.jsx`, `community-groups.jsx`, `community.jsx`, `lemmy-data*.js`)
and reuses their kit. The companion feature spec is [`../features/discover.md`](../features/discover.md).

---

Build **Spud Discover** — the Community Explorer for the Spud Lemmy client. This extends the
existing **Spud Communities** design; match it exactly and reuse its kit. Do **not** restyle the
app or invent new tokens.

**Reuse the existing kit and language.** Use `window.SPUD` (`T` color tokens, `TabBar`, `NAV_H`,
`ACCENTS` — accent is `ACCENTS[0].hex`, the Lemmy teal), `window.KIT.NavBar`,
`window.SC` (`CommunityIcon`, `FollowBtn`, `PrimaryBtn`, `GhostBtn`), and the globals `Icon`,
`PhoneFrame`, `Thumb`, `Tile`, `SAFE_TOP`. Match `community-groups.jsx`: dark UI, hairline
`0.5px` row separators, `T.mono` tabular numerals for all stats, `c/name@instance` handles with a
dimmed `@instance`, the `GroupMosaic` 2×2 icon tile for multi-community things, the frosted
context-menu/sheet style, `TabBar active="Communities"`. Artboards are `446×1056` on a transparent
board, laid out with `DesignCanvas` / `DCSection` / `DCArtboard` / `Caption`, exactly like
`Spud Communities.html`.

**Deliver** a new component file `discover.jsx` (an IIFE exposing `window.DISC = { ... }`) and a
canvas `Spud Discover.html` that loads the existing scripts plus `discover.jsx` and renders the
sections below — each `DCArtboard` wrapped in a captioned `Board` with `{ accent, n, name, who,
concept }`, same as the Communities canvas.

**Data realism.** Use fields the app actually has per community: name, title, instance, icon,
NSFW flag, subscribers, posts, comments, and active-users for day/week/month. Show activity as
"active/wk" and members as compact counts (e.g. `201K`). Use the same-name problem concretely:
have a name like `gaming` or `technology` exist on several servers (lemmy.world, lemmy.ml,
beehaw.org, …) with different sizes. Rankings are computed from current activity, not size alone.

Produce these artboards, grouped into sections:

### Section — Discover home
- **Landing (top).** Title "Discover" + a search field "Search or explore communities". Then a
  horizontally-scrolling **Starter packs** rail of pack cards (each: `GroupMosaic` of member icons,
  pack title, blurb, "N communities · M members"). Below it a **Trending now** rail of community
  cards (icon, name, `c/name@instance`, members, "active/wk", a small Follow). Show the start of the
  next rail peeking. Each rail header has a quiet "See all".
- **Landing (continued).** Continue the scroll: a **Rising** rail (same card shape but with a small
  "↑ active" momentum indicator and smaller, lesser-known communities), a **Because you follow** rail
  (cards grouped under a one-line reason), a **Browse by instance** entry row (globe + "Explore by
  server"), then the **All communities** section header with a sort pill ("Recommended") and the
  first few directory rows.

### Section — Rails expanded
- **Trending — all.** A `NavBar` "Trending" over a full ranked list. Each row: `CommunityIcon`,
  name, `c/name@instance`, members · active/wk, a `FollowBtn`. Collapse same-name duplicates (see
  below).
- **Rising — all.** Same list shape, but each row foregrounds the small-but-active story — show
  active/wk prominently and a subtle "small · very active" tag; smaller member counts.

### Section — All communities directory
- **Directory + sort menu.** The full sortable list with the frosted **sort menu open** (options:
  Recommended ✓, Most active, Members, Name — mirror the `SortMenu` in `community-groups.jsx`).
  Rows carry a `FollowBtn`; NSFW and suspicious communities are absent (clean default). Where a name
  exists on multiple servers, the row shows a dedupe badge "**also on 6 other servers · 892K**".
- **Same-name compare sheet.** Tapping that badge: a sheet titled e.g. "Gaming — 7 communities".
  Each variant as a row with its instance, members, active/wk, and a small instance-trust indicator,
  each with its own `FollowBtn`. A one-line explainer that these are independent places on different
  servers (reuse the teal info-callout style from `SuggestDetail`).

### Section — Starter packs
- **Packs overview.** The Starter packs rail expanded into a grid/list of pack cards (mosaic,
  title, blurb, member total).
- **Pack detail.** A `NavBar` with the pack name over: a header (mosaic + title + blurb), then the
  member communities as a multi-select list (each row a `CommunityIcon` + handle + members with a
  checkable circle, all selected by default, mirroring `NewGroup`), and a primary **Follow all (N)**
  plus a ghost **Not now**.

### Section — Browse by instance
- **Instance lens.** Reuse the `ExploreSearchInstance` pattern: an instance card (globe tile, host,
  "M members · K communities", a one-line character blurb, and a small health/trust indicator) over
  that instance's communities, each with a `FollowBtn`.

### Section — Because you follow
- **Because you follow — expanded.** Two labelled groups: "**Also on other servers**" (same-name
  communities on servers you don't yet follow, each with the reason inline) and "**Popular on
  servers you follow**" (active communities on instances where you already follow something). Each
  row has a `FollowBtn`. Signed-in context.

### Section — Community vitality & states
- **Community header with vitality.** A variant of `CommunityPage` (from `community.jsx`) whose
  header gains a compact stat strip — **members · active this week · posts** in `T.mono` — and a
  tappable source-instance chip (globe + host). Keep the prominent Subscribe.
- **States.** One artboard with three stacked phone states or a representative one: **signed-out
  Discover** (Follow buttons replaced by a subtle "Sign in to follow", and no Because-you-follow
  rail), a **loading skeleton** for the rails, and an **offline** note ("Showing the latest cached
  directory").

Keep everything on-brand with the existing Communities canvas: teal accent, dark surfaces,
hairline rows, mono numerals, friendly-but-refined. No emojis in UI copy. Captions should explain
the discovery intent (what data drives each rail) in the same voice as the Communities captions.

---

## Notes for whoever runs this

- The prompt deliberately mirrors `Spud Communities.html` + `community-groups.jsx` so the new
  screens drop into the same gallery system. If you'd rather extend the Communities canvas than add
  a separate one, tell Claude Design to add the sections to `community-groups.jsx` / the Communities
  canvas instead of new files.
- Ranking semantics (Trending = recent active users; Rising = active relative to size; canonical =
  best blend of size, activity, instance trust) are spelled out so the mock numbers stay plausible.
  The real formulas live in [`../features/discover.md`](../features/discover.md).
