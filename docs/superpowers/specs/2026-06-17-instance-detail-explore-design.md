# Instance detail — trust (onboarding) + explore (in-app) — design spec

**Goal:** Bring Spud's instance-detail surface up to the updated Claude Design
mockup (handoff bundle `~/Downloads/Spud-handoff(1).zip` →
`spud/project/Spud Instance Detail.html` + `instance-detail.jsx` +
`instance-detail-kit.jsx`). The mockup now covers **two contexts**:

1. **Trust / onboarding** — the "before you commit" screen between the instance
   picker and login. Already shipped as `InstanceDetailViewController` (Concept
   A); the update adds an **Admins** section and a **top-3 Communities** section.
2. **Explore / in-app** — a new browse-focused screen reached when an already
   signed-in (or anonymous) user taps where a community lives. No signup gating;
   the focus is the server's full Markdown sidebar (rules/support/contact), who
   runs it, and every local community with one-tap Join.

The mockups are HTML/CSS prototypes; recreate the visual output natively, do not
copy prototype structure.

## Design source of truth

- `instance-detail.jsx`
  - `FullBody` / `FullDetail` — onboarding Concept A. Now ends with
    `AdminsSection` + `CommunitiesSection limit={3}` before the sticky actions.
  - `ExploreBody` / `ExploreDetail` — the new in-app screen.
  - Shared sub-components: `AboutServer` (collapsible Markdown sidebar with fade
    + Read more/Show less), `AdminsSection`, `CommunitiesSection` (+ `CommunityRow`,
    `SubPill`), `HealthLink`, `SectionHead`, `PersonAvatar`, `Markdown`.
- `instance-detail-kit.jsx` — token sets, health/quality logic, and primitives
  (`Pill`, `ScoreRing`, `StatGrid`, `MetaRow`, `InstIcon`). New fixture fields:
  `sidebar` (Markdown string), `admins` (`[{name, dn, hue, role}]`), `communities`
  (`[{name, title, hue, subs, posts, joined?}]`).

Concepts B (`CardSheet`) and C (`CompactSheet`) and the `HardInterstitial` are
**not** built — A is the recommendation and the two screens above are the scope.

## Decisions (locked with the user)

- **Scope:** build both screens (onboarding additions + new explore screen).
- **Join action:** one-tap **federated** Join (`resolveObject` → `setSubscribed`);
  signed-out users get a sign-in gate.
- **Modlog:** omitted from this build (no native modlog screen exists; defer).
- **Routing:** repoint all in-app instance taps (Community header, PostDetail
  `openInstance`, Discover) to the explore screen. Onboarding / SiteList / login
  keep the signup-style `InstanceDetailViewController`.
- **Admins data:** **persist** in GRDB (record + migration + importer + observation),
  rather than fetch-on-demand — fits the app's confirm-then-mirror/observation
  architecture and is reusable.

## Token mapping (design → Spud)

The design palette is standard iOS light/dark semantics plus the teal accent, so
existing `SpudUIKit` tokens cover it — no new colors. Health colours map to
`UIColor.systemGreen` (good) · `.systemOrange` (ok/caution) · `.systemRed`
(bad) · `.tertiaryLabel` (unknown); NSFW → `.systemPurple`. Cards →
`Theme.secondaryGroupedBackground`; page → `Theme.groupedBackground`; chips/inset
→ `Theme.secondaryBackground`. Accent is `ThemeManager.currentAccentColor`
(snapshots pin `#009687`). These already match the shipped onboarding screen.

## Data layer

### Admins (new persistence)

`GetSiteResponse.admins` (`[PersonView]`) is currently fetched in
`LemmyService.fetchSiteInfo()` and dropped. Add:

- **`SiteAdminRecord`** (`SpudDataKit/.../Records/SiteAdminRecord.swift`):
  `id`, `siteId` (FK), `ordinal: Int`, `personActorId: String`, `personName: String`,
  `displayName: String?`, `avatarUrl: String?`. One row per admin per site.
- **Migration:** a new `DatabaseMigrator` case in `AppDatabase+Migrations.swift`
  creating `siteAdmin` (FK → `site`, `ON DELETE CASCADE`, indexed on `siteId`).
  Append-only; do not edit existing migrations.
- **Importer:** in `SiteImporter.apply(...)`, after upserting the site, replace
  that site's admin rows (delete-by-siteId then insert in `admins` order) from
  `response.admins`.
- **Observation:** `SiteAdminObservations` exposing
  `observeAdmins(siteId:) -> AsyncStream<[SiteAdminRecord]>` and a sync read,
  following the existing `*Observations.swift` pattern (start on
  `.global(qos: .userInitiated)` per the strict-concurrency note).
- **Role mapping (view layer):** ordinal `0` → "Owner", others → "Admin". Lemmy
  exposes no explicit owner flag; this is a documented approximation.

### Sidebar / description (existing `SiteRecord`)

`SiteRecord.sidebar` and `.descriptionText` already persist from `GetSite`. The
screens obtain them by ensuring a **signed-out account** for the target host
(`AccountService.accountForSignedOut(forInstance:)`), resolving its
`LemmyService`, and triggering `fetchSiteInfo()` (the scheduler already does this
for signed-out accounts whose site info is stale). The view models observe the
`SiteRecord` for that instance and update sidebar/admins reactively. Sidebar
Markdown renders through **SpudMarkdownKit** (`MarkdownBlockCache.shared.blocks(for:)`
off-main, then `MarkdownBodyView` with `MarkdownContext(kind: .post, ...)`), not
a hand-rolled parser.

### Communities (existing Explorer directory)

Per-instance community rows come from `ExplorerCommunityDirectory.communities(onInstance:in:sort:)`
over the bundled lemmyverse dataset (the same source Discover's browse-by-instance
uses), surfaced via `ExplorerCommunityListObservations`. `CommunityListRow`
provides name/title/subscribers/`usersActiveWeek`. The mockup's "X posts/wk" is
not in the dataset, so each row shows **"N subscribers · M active/wk"**. The
"Browse all N communities" footer pushes the existing `InstanceCommunitiesView`.

### Join (federated subscribe)

Tapping Join on a community row:

- **Signed out (no usable account):** `Haptics.warning()` + a sign-in gate
  (route into the existing login/sign-in flow for the relevant instance).
- **Signed in:** optimistic flip to Joined + `Haptics.tap()`, then
  `resolveObject("!\(name)@\(host)")` → home-instance `CommunityID` →
  `setSubscribed(serverCommunityId:, subscribed: true)`. On failure, revert the
  pill and surface an alert via `AlertService`. Unjoin is the inverse.
- **Initial joined-state:** derived best-effort from the account's existing
  subscriptions; unknown rows default to "Join".

## Shared component kit

Today `InstanceDetailViewController` keeps every building block private. Extract
the shared pieces into small reusable views under
`Spud/Scenes/Account/InstanceDetail/Components/` so both view controllers compose
them (mirrors the design's `IDK` kit and keeps each file focused):

- `InstanceBannerHeaderView` — banner image + gradient + overlaid glass nav
  buttons + icon/letter mark + name/host identity.
- `ScoreRingView` — extracted from the existing VC unchanged.
- `InstanceHealthPill` — the tinted icon+label pill (level → colour).
- `InstanceStatStrip` / stat-tile + `MetaRow` helpers — extracted.
- `WrapView` — extracted flow layout (pills, chips).
- `InstanceAdminsView` — admins list + "Admin list unavailable" (nil) and red
  "No admins are publicly listed — operator is anonymous" (empty) states, with
  `PersonAvatar` mark + role chip.
- `InstanceCommunityRowView` — community icon + `c/name` + "subs · active/wk" +
  Join/Joined pill (or chevron in onboarding's top-3 list).
- `InstanceAboutServerView` — collapsible Markdown sidebar: clamps to ~124pt
  with a bottom gradient fade when collapsed, "Read more"/"Show less" toggle,
  Reduce-Motion-aware expand. Renders via SpudMarkdownKit.
- `InstanceHealthColors` — `HealthLevel`/registration → `UIColor` + SF Symbol
  helpers (extracted from the VC's private helpers).

Final decomposition may merge trivially-small files; the rule is one clear
purpose per file and no duplication between the two screens.

## Screen 1 — onboarding (`InstanceDetailViewController`, modify)

Insert, above the sticky action bar and after the tag chips:

1. **Admins** (`InstanceAdminsView`) — section head "Admins" + count.
2. **Communities** (`InstanceCommunityRowView` ×3) — section head "Communities"
   + count, top 3 rows (chevron, not Join), then a "Browse all N communities →"
   row pushing `InstanceCommunitiesView`.

Data: on `viewDidLoad`, ensure a signed-out account for `record.baseurl`, trigger
`fetchSiteInfo`, and observe admins; load the top-3 community rows from the
directory. Both degrade to the unavailable/anonymous states. Identity, health
band, stat grid and details remain synchronous from `ExplorerInstanceRecord`.

Add a `showsActions: Bool = true` init flag; when `false`, the sticky action bar
is omitted (used by the explore screen's Health cross-link so a signed-in user is
not shown Create/Sign-in/Browse).

## Screen 2 — explore (`InstanceExploreViewController`, new)

New file `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift`
+ `InstanceExploreViewModel.swift` (`@Observable`). A plain scroll view (no
sticky action bar), composed top to bottom:

1. `InstanceBannerHeaderView` (banner + back/share/ellipsis glass nav + identity).
2. One-paragraph description.
3. `InstanceAboutServerView` — collapsible Markdown sidebar (hidden if no sidebar).
4. 4-stat strip: Members · Active/mo · Communities · Posts.
5. **Health** cross-link card (`ScoreRingView` 40pt + trust label + "uptime ·
   since created" + "Health ›") → pushes `InstanceDetailViewController(record:,
   showsActions: false)`.
6. `InstanceAdminsView`.
7. **Communities** — full list (`InstanceCommunityRowView` with Join), a "Top"
   sort affordance, and a "Browse all N communities →" footer →
   `InstanceCommunitiesView`.

Init takes the `ExplorerInstanceRecord` (identity/stats/health, like onboarding)
plus the nested dependencies needed for navigation + the account/Lemmy/image/
alert services. The view model owns: the signed-out `LemmyService` for the host,
the `SiteRecord`/admins observation, the community rows, and the Join state +
mutations.

## Navigation / routing

- **Community header:** make the `!name@instance` handle in `CommunityHeaderView`
  tappable (tap gesture + `.button` trait + a11y label "Open <host>"). Surface a
  `onInstanceTapped` callback; `CommunityViewController` resolves the host from
  `CommunityViewModel.actorId` and pushes `InstanceExploreViewController`.
- **PostDetail:** `PostDetailViewController.openInstance(_:)` pushes
  `InstanceExploreViewController` instead of `InstanceDetailViewController`.
- **Discover:** the instance-detail tap in `DiscoverViewController` pushes
  `InstanceExploreViewController`.
- **Unchanged:** `SiteListViewController` and `OnboardingHomeBaseViewController`
  keep `InstanceDetailViewController` (the signup-style screen).

Dependency composition for the new VC follows the existing pattern
(`HasAccountService & HasImageService & HasAlertService` + the nested Login/
Register/Community deps required by its push targets).

## States & accessibility

- Identity, stats, health, details render instantly from `ExplorerInstanceRecord`.
- Sidebar + admins load async with a per-section loading placeholder →
  content / "unavailable"; never a blank.
- Communities render from the directory; empty → "Community list unavailable".
- Join: optimistic with haptics; sign-in gate when signed out; revert + alert on
  error.
- VoiceOver labels/traits on the new handle tap target, admin rows, Join pills,
  the Health cross-link, and Read more/Show less. Full Dynamic Type; light, dark,
  and True Black via existing semantic tokens; honors Reduce Motion for the
  sidebar expand.

## Testing

- **Snapshot — onboarding:** extend `InstanceDetailSnapshotTests` so the existing
  state matrix (open/application/closed/nsfw/suspicious/tiny/missing × light/dark)
  now includes the Admins + top-3 Communities sections. Existing reference images
  are **re-recorded** (the screen grew). Fixtures need `admins`/`communities`
  populated, plus the anonymous (empty admins) and unavailable (nil) variants.
- **Snapshot — explore:** new `InstanceExploreSnapshotTests` covering: sidebar
  collapsed vs expanded; admins present / anonymous / unavailable; communities
  present / unavailable; a joined vs not-joined row; light + dark. Pinned
  `ViewImageConfig` (iPhone 13 Pro) so references are device-independent; nil
  image URLs so placeholder marks render deterministically.
- **Unit (`SpudDataKitTests`):** `SiteAdminRecord` round-trip; `SiteImporter`
  admin upsert/replace from a faked `GetSiteResponse`; `SiteAdminObservations`
  emits on change; admin role mapping; community-row mapping; join-state
  derivation.

## Non-goals

- Native modlog screen (the row is omitted this build).
- Live `listCommunities(type: Local)` — the bundled directory is the source.
- Concept B (card sheet), Concept C (compact sheet), the suspicious hard-confirm
  interstitial.
- iPad-specific layout beyond what the existing split view provides.
- Server-side "posts/wk" community metric (not in the dataset; show active/wk).
