# App Intents + App Shortcuts (Siri / Spotlight / Action button)

Date: 2026-06-17
Status: Design approved, ready for implementation plan

## Problem

Spud's App Intents surface is effectively empty. The only `AppIntent` is
`ViewTopPostsAppIntent` (a `WidgetConfigurationIntent` whose `perform()` is a
`// TODO` stub), and there is **no `AppShortcutsProvider`** — so nothing is exposed
to Siri, Spotlight Top Hits, the Action button, or the Shortcuts app. A legacy
SiriKit donation (`INInteraction` of the `.intentdefinition` `ViewTopPostsIntent`)
lingers in `PostListViewController` but only "donates" the old intent; it runs no
app action. For a native iOS app this is the single biggest system-integration
gap after link handling.

This effort adds a real set of App Intents, parameterized where it helps, plus an
`AppShortcutsProvider` that gives them Siri phrases and system surfacing — and a
`CommunityAppEntity` so users can open a subscribed community by name/voice, with
those communities indexed into Spotlight.

## Decisions (confirmed)

- **Intent set:** Open Feed, Search Lemmy, New Post, Open Inbox, Open Community.
- **Navigation:** a typed navigation router on `AppCoordinator` with deferred
  replay for cold launch (not the `info.ddenis.spud://` URL scheme — that stays for
  content links).
- **Community entity:** `CommunityAppEntity` + `EntityStringQuery` backed by the
  shared App-Group GRDB (subscriptions), **also** conforming to `IndexedEntity`
  (iOS 18) so subscribed communities are indexed into Spotlight.
- **Open Feed** is a dedicated `OpenFeedAppIntent` (not the widget-config
  `ViewTopPostsAppIntent`), keeping widget configuration and app navigation
  separate.
- **Legacy:** remove the app's `INInteraction` donation; **keep** the widget's
  `ViewTopPostsIntent` `.intentdefinition` (still the older-OS widget config path).
- **Account:** all intents operate on the current default account, like the widget.
- **Placement:** the new intents/entity/provider live in the **Spud app target**
  (they reference `AppCoordinator`/`MainWindow`), reusing the shared
  `IntentFeedTypeAppEnum` / `IntentSortTypeAppEnum` from `Shared/Intents`. They are
  NOT added to `Shared/Intents` (which compiles into the widget too).

## Architecture / components

```
Siri / Spotlight / Action button / Shortcuts
        │  (invokes an AppIntent, openAppWhenRun = true)
        ▼
<Intent>.perform()  ──►  AppCoordinator.shared.navigate(AppNavigation)
        │                         │
        │            activeWindow live?  ── yes ─►  MainWindow.<select/display>(…)
        │                         └── no ──►  store pendingNavigation
        ▼                                            │
   .result()                          SceneDelegate connect/active
                                          └─► MainWindow.drainPendingNavigation()
```

| Component | File (new unless noted) | Responsibility |
|---|---|---|
| `AppNavigation` | `Spud/App/AppNavigation.swift` | Typed enum of navigation targets: `.feed(listing:sort:)`, `.search(query:)`, `.newPost`, `.inbox`, `.community(name:instance:)`. (Posts/people already covered by `display(...)`.) |
| `AppCoordinator` nav router | `Spud/App/AppCoordinator.swift` (modify) | `weak var activeWindow`, `var pendingNavigation`, `func navigate(_:)`, `func setActiveWindow(_:)`, `func drainPendingNavigation(into:)`. |
| `SceneDelegate` | `Spud/App/SceneDelegate.swift` (modify) | On `willConnectTo` / `sceneDidBecomeActive`, register the window as active and drain any pending navigation. |
| `MainWindow` nav methods | `Spud/Scenes/MainWindow/MainWindow.swift` (modify) | `selectFeed(listing:sort:)`, `selectSearch(query:)`, `presentNewPost()`, `selectInbox()`, reusing existing tab/compose/display plumbing. |
| `OpenFeedAppIntent` | `Spud/Intents/OpenFeedAppIntent.swift` | params `feedType` (default `.subscribed`), optional `sortType`. |
| `SearchLemmyAppIntent` | `Spud/Intents/SearchLemmyAppIntent.swift` | param `query: String`. |
| `NewPostAppIntent` | `Spud/Intents/NewPostAppIntent.swift` | no params. |
| `OpenInboxAppIntent` | `Spud/Intents/OpenInboxAppIntent.swift` | no params. |
| `OpenCommunityAppIntent` | `Spud/Intents/OpenCommunityAppIntent.swift` | param `community: CommunityAppEntity`. |
| `CommunityAppEntity` + query | `Spud/Intents/CommunityAppEntity.swift` | `AppEntity` + `IndexedEntity` + `EntityStringQuery`. |
| `SpudAppShortcuts` | `Spud/Intents/SpudAppShortcuts.swift` | `AppShortcutsProvider` with phrases/icons. |
| Community Spotlight index | `Spud/Intents/CommunitySpotlightIndexer.swift` | indexes subscribed communities via `CSSearchableIndex.default().indexAppEntities(...)` at launch + on subscription change. |
| Legacy donation removal | `PostListViewController.swift` (modify) | delete `donateIntent()` + `import Intents`. |

## The intents

All conform to `AppIntent`, set `static var openAppWhenRun = true`, and return
`.result()` after calling the router. `perform()` runs on `@MainActor`.

- **`OpenFeedAppIntent`** — `title` "Open Feed". `@Parameter feedType:
  IntentFeedTypeAppEnum` (default `.subscribed`); `@Parameter sortType:
  IntentSortTypeAppEnum?` (optional). `perform()` →
  `AppCoordinator.shared.navigate(.feed(listing: .init(from: feedType), sort:
  sortType.map { .init(from: $0) }))`.
- **`SearchLemmyAppIntent`** — `@Parameter(title: "Query") query: String`. →
  `.navigate(.search(query: query))`.
- **`NewPostAppIntent`** — → `.navigate(.newPost)`. The existing compose path shows
  the sign-in gate for a signed-out account.
- **`OpenInboxAppIntent`** — → `.navigate(.inbox)`.
- **`OpenCommunityAppIntent`** — `@Parameter community: CommunityAppEntity`. →
  `.navigate(.community(name: community.name, instance: community.instance))`.
  Donates itself via `IntentDonationManager` when run so Siri learns frequent
  communities.

## CommunityAppEntity + query

```swift
struct CommunityAppEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Community"
    static var defaultQuery = CommunityEntityQuery()

    var id: String                 // "name@instanceHost" — stable, federation-aware
    let name: String
    let instance: InstanceActorId
    let iconURL: URL?

    var displayRepresentation: DisplayRepresentation {
        .init(title: "\(name)", subtitle: "\(instance.host)", image: iconURL.map { .init(url: $0) })
    }
}

struct CommunityEntityQuery: EntityStringQuery {
    func entities(for ids: [String]) async throws -> [CommunityAppEntity]   // resolve by id
    func entities(matching string: String) async throws -> [CommunityAppEntity] // name search
    func suggestedEntities() async throws -> [CommunityAppEntity]           // default account subscriptions
}
```

- The query reads the **shared App-Group GRDB** through a read-only SpudDataKit
  accessor (the same store the widget reads), constructed independently of the full
  `AppCoordinator` startup so it works in a background intents process. Mirror
  `SpudWidget/DependencyContainer.swift`'s pattern for building read services
  against the App Group.
- `suggestedEntities()` returns the default account's subscribed communities (so
  Siri/Shortcuts pre-suggest them); `entities(matching:)` filters subscriptions by
  name (case-insensitive contains).
- **Spotlight:** `CommunitySpotlightIndexer` calls
  `CSSearchableIndex.default().indexAppEntities(subscribedCommunities)` at launch
  and whenever subscriptions change (hook the existing subscribe/unsubscribe path
  or a GRDB observation). Tapping a Spotlight result routes through
  `OpenCommunityAppIntent`.

## AppShortcutsProvider

```swift
struct SpudAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenFeedAppIntent(), phrases: [
            "Open \(\.$feedType) in \(.applicationName)",
            "Open my \(.applicationName) feed",
        ], shortTitle: "Open Feed", systemImageName: "list.bullet.rectangle")
        AppShortcut(intent: SearchLemmyAppIntent(), phrases: [
            "Search \(.applicationName) for \(\.$query)",
        ], shortTitle: "Search", systemImageName: "magnifyingglass")
        AppShortcut(intent: NewPostAppIntent(), phrases: [
            "New post in \(.applicationName)",
        ], shortTitle: "New Post", systemImageName: "square.and.pencil")
        AppShortcut(intent: OpenInboxAppIntent(), phrases: [
            "Open my \(.applicationName) inbox",
        ], shortTitle: "Inbox", systemImageName: "tray")
        AppShortcut(intent: OpenCommunityAppIntent(), phrases: [
            "Open \(\.$community) in \(.applicationName)",
        ], shortTitle: "Open Community", systemImageName: "person.3")
    }
}
```

(Phrase wording finalized during implementation; `\(.applicationName)` is required
in every phrase.)

## MainWindow navigation methods

Reuse existing plumbing:
- `selectFeed(listing:sort:)` — select Posts tab (index 0); set the feed. Reuse how
  the Posts tab's `PostListViewModel` switches feed (or rebuild the feed for the
  default account). Investigate the cleanest in-place feed switch during impl.
- `selectSearch(query:)` — select Search tab (index 2); set the search controller's
  text and trigger `viewModel.queryChanged(query)`.
- `presentNewPost()` — reuse `composeTapped`'s path: sign-in gate, then present
  `NewPostViewController.makeSheet(...)` on the active tab.
- `selectInbox()` — select Inbox tab (index 3).

## Error handling / edge cases

- **Cold launch / no window:** `navigate(_:)` stores `pendingNavigation`;
  `SceneDelegate` drains it once the window is active. One-slot (latest wins).
- **Signed-out:** New Post and any account-requiring action open the app and reuse
  the existing in-app sign-in gate. Open Feed/Inbox/Search work signed-out
  (Subscribed/Mod map to All for a signed-out account, as the widget already does).
- **Unresolvable community:** if a `CommunityAppEntity` no longer resolves, open the
  app and surface the existing toast (no dead screen).
- **Background intents process:** the entity query must not assume UI is running;
  it only touches the read-only DB accessor.

## Testing

- **Routing (unit):** `AppCoordinator.navigate(_:)` dispatch — each `AppNavigation`
  case lands on the correct `MainWindow` method (fake window); pending-navigation
  stored when no window, drained on activate.
- **Entity query (unit):** `CommunityEntityQuery` against an in-memory GRDB seeded
  with subscriptions — `suggestedEntities()` returns them, `entities(matching:)`
  filters by name, `entities(for:)` round-trips ids.
- **Enum mappings (unit):** `IntentFeedTypeAppEnum`→`ListingType` and
  `IntentSortTypeAppEnum`→`SortType` (extend existing converters if needed).
- **Manual:** Shortcuts app shows all five actions; "Hey Siri, open Subscribed in
  Spud" / "Search Spud for …" work; a subscribed community appears in Spotlight and
  opens; Action-button assignment works.

## Out of scope (YAGNI)

- Notifications / background refresh (separate effort).
- Full Spotlight `CSSearchableItem` indexing of posts/history beyond the
  `IndexedEntity` community ride-along.
- A `PostAppEntity` / "open post" intent (link handling already covers post URLs).
- Migrating the widget off the legacy `.intentdefinition`.
- Per-intent result snippets/dialogs (intents just open the app).

## Open risks / verify during implementation

- **In-place feed switch:** confirm the Posts tab can switch its feed for the
  default account cleanly from `selectFeed`, vs. needing to rebuild the
  `PostListViewController`. Pick the simplest correct path.
- **Entity query out-of-process data access:** confirm a read-only SpudDataKit
  accessor can be built against the App Group without full `AppCoordinator`
  startup (mirror the widget). 
- **`IndexedEntity` API shape on the pinned SDK:** confirm
  `CSSearchableIndex.indexAppEntities` signature and the `attributeSet` mapping.
- **`AppShortcutsProvider` discovery:** confirm the app-target provider is picked up
  without a separate AppIntents extension on the pinned toolchain.
- **Default-account resolution in intents:** reuse
  `AccountService.currentDefaultAccountKeychainId()`; confirm it's safe to call from
  the intents process.
