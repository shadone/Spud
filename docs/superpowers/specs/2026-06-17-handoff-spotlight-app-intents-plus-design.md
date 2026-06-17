# Handoff / Spotlight / App Intents completion

Date: 2026-06-17
Status: Design approved, ready for implementation plan

## Problem

Spud now has App Intents, App Shortcuts, link handling, and a community
`IndexedEntity`, but three "deep integration" gaps remain:

1. **No `NSUserActivity` / Handoff.** `Info.plist` declares `NSUserActivityTypes =
   [ViewTopPostsIntent]`, but no code creates or continues a user activity, and
   `SceneDelegate` has no `scene(_:continue:)` handler. So there is no Handoff
   across devices, no Siri prediction from browsing, no Spotlight entry for content
   you actually viewed, and no activity-based state restoration.
2. **App Intents are incomplete.** No "Open Saved" feed, no account switching, and
   the per-community Siri donation was deliberately skipped.
3. **Spotlight only knows subscriptions.** Saved posts and history — both locally
   tracked in `postInteraction` — are not indexed, so they are not findable from
   system search.

This effort closes all three. They share one through-line: every system surface
(deep links [done], App Intents [done], `NSUserActivity` continuation, Spotlight
item taps) funnels into `AppCoordinator.open` via a `info.ddenis.spud://internal/…`
routing URL.

## Decisions (confirmed)

- **Routing key:** the canonical `ap_id` URL wrapped in `.objectAtURL` for posts /
  people (Handoff- and cross-account-safe, reuses the existing `resolve_object`
  path); `.community(name, instance)` for communities (federation-safe, no
  network). One resolve round-trip on open is acceptable.
- **Proactive Spotlight scope:** **saved posts + history** (both in
  `postInteraction`), in addition to the viewed-item activities from Slice 1 and
  the community `IndexedEntity` already shipped.
- **AppIntents extension:** deferred (YAGNI for a pre-ship app; in-app target
  works).
- **Activities vended on:** post, community, and person screens.
- **Eligibility:** Handoff + Search + Prediction on every vended activity.
- **Placement:** new App Intents / entity files under `Spud/Intents/`; activity +
  Spotlight helpers under `Spud/Integration/` (new group), app target only.

## Architecture / components

```
                    info.ddenis.spud://internal/…  (one routing URL everywhere)
   deep links ─┐    App Intents ─┐    NSUserActivity ─┐    Spotlight tap ─┐
               └──────────────────┴───────────────────┴───────────────────┘
                                          │
                       SceneDelegate (openURLContexts / continue:)
                                          │
                                AppCoordinator.open / navigate
```

| Component | File | Responsibility |
|---|---|---|
| `SpudUserActivity` | `Spud/Integration/SpudUserActivity.swift` (new) | Factory: builds an `NSUserActivity` for a post / community / person — routing URL in `userInfo`, title + keywords, eligibility flags, `persistentIdentifier`. Plus a decoder: activity → routing `URL`. |
| Activity vending | `PostDetailViewController`, `CommunityViewController`, `PersonViewController` (modify) | Set `userActivity` + `becomeCurrent()` in `viewDidAppear`; `resignCurrent()` on disappear. |
| Continuation | `Spud/App/SceneDelegate.swift` (modify) | New `scene(_:continue:)` — decode our activity types **and** `CSSearchableItemActionType` (identifier = routing URL) → `AppCoordinator.open`. |
| Info.plist | `Spud/Resources/Info.plist` (modify) | Replace stale `NSUserActivityTypes` with the real activity types. |
| `AppNavigation` `.savedFeed` | `Spud/App/AppNavigation.swift` (modify) | New case → `MainWindow.selectSavedFeed()`. |
| `OpenSavedAppIntent` | `Spud/Intents/OpenSavedAppIntent.swift` (new) | Sign-in-gated; opens the Saved feed. |
| `AccountAppEntity` + query | `Spud/Intents/AccountAppEntity.swift` (new) | `AppEntity` + query over `observeAccounts` (off-main read). |
| `SwitchAccountAppIntent` | `Spud/Intents/SwitchAccountAppIntent.swift` (new) | `AccountService.setDefaultAccount` + rebuild UI for the new default. |
| `OpenCommunityAppIntent` donation | `Spud/Intents/OpenCommunityAppIntent.swift` (modify) | Donate via `IntentDonationManager`. |
| `SpudAppShortcuts` | `Spud/Intents/SpudAppShortcuts.swift` (modify) | Add Open Saved + Switch Account. |
| `ContentSpotlightIndexer` | `Spud/Integration/ContentSpotlightIndexer.swift` (new) | Index saved + recent history `postInteraction` rows as `CSSearchableItem`. |
| Saved/history sync read | `SpudDataKit/Services/AppDatabase/SpotlightContentQueries.swift` (new) | One-shot read of indexable rows (saved + recent), off-main. |

## Slice 1 — NSUserActivity / Handoff

- `SpudUserActivity` activity types: `info.ddenis.Spud.viewPost`, `.viewCommunity`,
  `.viewPerson`. Each factory sets:
  - `userInfo["url"]` = the routing URL string (post/person: `.objectAtURL(ap_id)`;
    community: `.community(name, instance)`),
  - `title` (post title / `!community` / `@user`), `keywords`,
  - `isEligibleForHandoff = true`, `isEligibleForSearch = true`,
    `isEligibleForPrediction = true`,
  - `persistentIdentifier` = the routing URL string (so identical content
    deduplicates and can be deleted).
- View controllers vend on appear. For a post the canonical URL is built the same
  way `sharePost()` does (`ShareURL.forPost(originalPostUrl:serverPostId:instanceActorId:)`).
- `SceneDelegate.scene(_:continue:)` decodes:
  - our activity types → `userInfo["url"]`,
  - `CSSearchableItemActionType` → `userInfo[CSSearchableItemActivityIdentifier]`,
  then `URL(string:)` → `AppCoordinator.open(url, in: window)` (or store pending if
  no window, mirroring the intent router).

## Slice 2 — App Intents completion

- `OpenSavedAppIntent` (no params, `openAppWhenRun`) → `AppCoordinator.navigate(.savedFeed)`.
  `MainWindow.selectSavedFeed()` selects Posts tab and `showFeed(.saved(sortType:
  defaultOrHot))`. Signed-out reuses the in-app gate (the Saved feed/compose path
  already gates).
- `AccountAppEntity`: `id` = `accountKeychainId`; title = account display name +
  instance host. `AccountEntityQuery` reads signed-in accounts off-main (mirror
  `followedCommunitiesForDefaultAccountSync`'s pattern with a new sync read over
  `AccountRecord`). `suggestedEntities()` = all signed-in accounts.
- `SwitchAccountAppIntent` (`@Parameter account: AccountAppEntity`,
  `openAppWhenRun`) → on the main actor, `accountService.setDefaultAccount(forAccountKeychainId:
  account.id)`; the existing default-account observation rebuilds the UI.
- `OpenCommunityAppIntent.perform()` adds `IntentDonationManager.shared.donate(intent:
  self)` (verify the API shape; wrap in a `Task`/`try?` as the SDK requires).
- `SpudAppShortcuts`: add Open Saved ("Open my \(.applicationName) saved posts") and
  Switch Account ("Switch to \(\.$account) in \(.applicationName)").

## Slice 3 — Spotlight indexing of saved + history

- `SpotlightContentQueries.indexableContentRowsSync(forAccountKeychainId:limit:)` —
  one-shot read of `postInteraction` rows that are `isSaved` OR among the N most
  recent by `lastOpenedAt`, returning the fields needed to build items (title /
  `titleSnapshot`, `originalPostUrl`, `thumbnailUrl`, community name, serverPostId).
- `ContentSpotlightIndexer.reindex(appDatabase:)` maps rows → `CSSearchableItem`
  (`uniqueIdentifier` = routing URL, `domainIdentifier = "content"`,
  `attributeSet.title/contentDescription/thumbnailURL`) and calls
  `CSSearchableIndex.default().indexSearchableItems(_:)`. Reset via
  `deleteSearchableItems(withDomainIdentifiers: ["content"])` before a full
  reindex to drop stale entries.
- Hooks: launch + foreground (alongside `CommunitySpotlightIndexer`), and on
  save/unsave (the existing save write path or a `postInteraction` observation).
- Taps route through Slice 1's `scene(_:continue:)`.

## Error handling / edge cases

- **Signed-out:** Open Saved + Switch Account targets open the app and reuse the
  in-app sign-in gate / no-op when there's nothing to switch to.
- **Cross-account / cross-device Handoff:** continuation resolves the canonical URL
  under the receiving device's default account (works because the key is the
  `ap_id`, not a local id).
- **Cold launch:** `scene(_:continue:)` stores a pending navigation if the window
  isn't ready (reuse the intent router's pending slot / `AppCoordinator.open`
  tolerance).
- **Index hygiene:** cap history items (e.g. 100 most recent); `domainIdentifier`
  reset prevents unbounded/stale growth; community index (separate domain) is
  untouched.
- **Unresolvable content:** `.objectAtURL` resolve failure already shows a warning
  haptic (no dead screen).

## Testing

- **`SpudUserActivity` (unit):** post/community/person factories produce the right
  activity type, routing URL, and eligibility; the decoder round-trips
  activity → URL for both our types and `CSSearchableItemActionType`.
- **Continuation routing (unit):** decoded URL dispatches to the correct
  `AppCoordinator.open` path (extend the existing `AppNavigationRoutingTests` /
  add an `open`-routing test with a fake window).
- **`AccountEntityQuery` (unit):** in-memory GRDB seeded with two accounts →
  `suggestedEntities()` returns them; `entities(for:)` round-trips.
- **`SpotlightContentQueries` (unit):** seeded `postInteraction` rows → returns
  saved + recent, capped, with the indexable fields.
- **`ContentSpotlightIndexer` (unit):** row → `CSSearchableItem` mapping
  (identifier = routing URL, title, thumbnail).
- **Manual:** Handoff a post phone→iPad; "Hey Siri" prediction after repeated use;
  a saved post and a viewed post both appear in Spotlight and open; Switch Account
  changes the active account.

## Out of scope (YAGNI)

- Notifications / background refresh.
- An AppIntents extension (background entity resolution).
- Comment-level activities or Spotlight items.
- Post / comment App Intent **entities** (only community + account are modeled).
- Mac Catalyst-specific Handoff tuning.

## Open risks / verify during implementation

- **`ShareURL.forPost` reuse** from a generic context (it currently reads
  `headerRow?.originalPostUrl` + `accountInstanceActorIdSync`) — confirm the same
  inputs are reachable where the activity is vended.
- **`IntentDonationManager.donate` signature** on the pinned SDK (async? throwing?).
- **`CSSearchableItem` thumbnail** — set `thumbnailURL` (remote) vs `thumbnailData`;
  confirm remote URL is honored, else skip the thumbnail.
- **Saved enumeration** — confirm `postInteraction.isSaved` reflects the app's
  Save/Follow semantics (the "Follow = Save" unification) so "saved" indexes the
  right set.
- **`scene(_:continue:)` + pending nav** — confirm reuse of the intent router's
  pending-navigation slot vs a parallel mechanism; keep one.
