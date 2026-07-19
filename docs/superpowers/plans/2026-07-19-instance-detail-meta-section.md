# Instance-Detail Meta Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An "About this instance" card on the instance-detail screen listing the viewed instance's classified meta communities, with tap-to-open and a long-press context menu (Open / Subscribe / Favourite / Notify / Mute / Share / Copy Link / Block).

**Architecture:** Spec: `docs/superpowers/specs/2026-07-19-instance-detail-meta-section-design.md`. Zero new resolution machinery — `MetaCommunityService.refreshInstance(host:siteName:forAccountKeychainId:)` already handles arbitrary hosts and `observeMetaCommunities(forAccountId:instanceHost:)` already serves them; the screen fire-and-forgets a refresh for the viewed host (gated on a default account existing) and renders an observation-driven card above its Communities card. Actions ride the long-press `CommunityContextMenuBuilder`, extended with an optional Favourite action whose copy is centralized and shared with `CommunityViewController`.

**Tech Stack:** UIKit (card/stack screen), GRDB observations, Swift Testing, swift-snapshot-testing, XcodeGen.

## Global Constraints

- Repo: `/Users/denis/dev/info.ddenis/Spud/Spud`, branch off local `main` (@ 79dd59ab or later); execution in a worktree — worktree-rooted paths ONLY.
- After ADDING any file: `make project` before building. Adding `HasMetaCommunityService` to `InstanceDetailViewController.OwnDependencies` CASCADES into manual `NestedDependencies` chains and test doubles — a missed double is an undefined-symbol LINKER error when TEST targets build (`make build` alone passes). Build the full test plan after the dependency change and stub every affected double.
- Section gate: the card exists ONLY when a default (non-service) account exists. Acting account = that default account; all actions go through its `AccountScope`.
- Menu order in the builder's open group: Open Community, Subscribe/Unsubscribe, Add to Favorites/Remove from Favorites (only when the host provides favourite state), Notify About New Posts.
- Favorites copy EXACTLY: "Add to Favorites" / "Remove from Favorites"; symbols `star` (add) / `star.slash` (remove) — these currently live inline in `CommunityViewController.favoriteMenuActions()` (~line 398) and MUST end up in exactly one place (`CommunityFavoriteLabel`), consumed by both surfaces.
- Block from the new menu must ALSO remove a live new-posts follow (fourth block call site — same fire-and-forget shape as the three existing sites; see `git log --grep "block removes"`).
- Notify copy/symbols from `CommunityNotifyLabel`; subscribe copy from `CommunitySubscribeButtonLabel`; the meta badge glyph is the shared "Instance community" `building.2.fill` treatment (see `SearchCommunityCell`'s UIKit badge).
- Swift Testing (`import Testing` does not re-export Foundation); reminder-table reads bind `Date`s, never epoch doubles; no emojis; conventional commits; `mint run swiftformat <paths>` BEFORE each task's final verify; explicit `git add` paths (never -A; never sweep annex-` M` snapshot refs you didn't record — `git annex restage` clears the cosmetic noise).
- Targeted test run shape: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/<Suite> -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test` (trust the `✔ Test run ... passed` lines). Known flakes: SpudDataKitTests one real-network offline flake; SpudTests VM CancellationError parallelism flakes; NodeInfoBlockUITests environmental AutoFill red — isolate-and-rerun before judging a genuine failure.
- Reference sim iPhone 17 Pro / iOS 26.3.x for snapshots (`make snapshot` fails fast on the wrong sim); never boot a second simulator; record one class at a time, stage only intentionally recorded refs.

---

### Task 1: CommunityFavoriteLabel + optional Favourite action in the builder

**Files:**
- Create: `Spud/Utils/CommunityFavoriteLabel.swift`
- Modify: `Spud/Utils/ContextMenus/CommunityContextMenuBuilder.swift` (host protocol + menu), `Spud/Scenes/Community/Content/CommunityViewController.swift:398-415` (consume the label)
- Test: `SpudTests/CommunityFavoriteLabelTests.swift` (create), the existing `CommunityContextMenuBuilderTests` suite (extend)

**Interfaces:**
- Produces: `enum CommunityFavoriteLabel { static func title(isFavorited: Bool) -> String; static func symbol(isFavorited: Bool) -> String }`; `CommunityContextMenuHost` gains `func communityFavoriteState(_ result: SearchCommunityResult) -> Bool?` (protocol-extension default returning `nil` = surface offers no Favourite) and `func communityToggleFavorite(_ result: SearchCommunityResult)` (default no-op); the builder inserts the Favourite `UIAction` between the subscribe and notify actions ONLY when `communityFavoriteState` returns non-nil.

- [ ] **Step 1: Failing label + builder tests.** `CommunityFavoriteLabelTests`: title/symbol per state ("Add to Favorites"/`star` when not favorited; "Remove from Favorites"/`star.slash` when favorited). Extend `CommunityContextMenuBuilderTests` (grep it under `SpudTests/`, follow its recording-host fake): (a) default host (no override) -> menu contains NO Favorites action; (b) host returning `false` -> action present, title "Add to Favorites", tapping dispatches `communityToggleFavorite`; (c) host returning `true` -> title "Remove from Favorites". Run; expect FAIL (type/method not found).

- [ ] **Step 2: Implement the label** (mirror `CommunityNotifyLabel`'s header style):

```swift
/// Centralized copy + symbols for the community Favourite action, shared by
/// the community screen's overflow menu and the community context-menu
/// builder so the wording can't drift.
enum CommunityFavoriteLabel {
    static func title(isFavorited: Bool) -> String {
        isFavorited
            ? NSLocalizedString("Remove from Favorites", comment: "Menu action to unfavorite a community")
            : NSLocalizedString("Add to Favorites", comment: "Menu action to favorite a community")
    }

    static func symbol(isFavorited: Bool) -> String {
        isFavorited ? "star.slash" : "star"
    }
}
```

Keep the `comment:` strings byte-identical to `CommunityViewController`'s existing ones so localization keys don't fork.

- [ ] **Step 3: Builder + host.** In `CommunityContextMenuBuilder.swift`: add the two host methods with a protocol extension providing the defaults (doc comment: nil state = the surface doesn't offer Favourite; Search inherits the default today). In `menu(for:subscribedState:host:)`, after `subscribeAction` and before the notify action:

```swift
        var openChildren: [UIMenuElement] = [openAction, subscribeAction]
        if let favorited = host.communityFavoriteState(result) {
            openChildren.append(UIAction(
                title: CommunityFavoriteLabel.title(isFavorited: favorited),
                image: UIImage(systemName: CommunityFavoriteLabel.symbol(isFavorited: favorited))
            ) { [weak host] _ in host?.communityToggleFavorite(result) })
        }
        openChildren.append(notifyAction)
        let openGroup = UIMenu(options: .displayInline, children: openChildren)
```

- [ ] **Step 4: `CommunityViewController.favoriteMenuActions()`** replaces its inline strings/symbols with `CommunityFavoriteLabel.title(isFavorited: favorited)` / `.symbol(isFavorited: favorited)` — behavior unchanged.

- [ ] **Step 5: Run, format, commit.** Targeted suites, then `make test-only ONLY=SpudTests`. `mint run swiftformat Spud/ SpudTests/ && make project` (new file). Commit: `feat: optional Favorites action in community context menu`.

---

### Task 2: Instance-detail wiring + "About this instance" card

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Observations.swift` (or a sibling queries file, matching local convention) — add `defaultAccountKeychainIdSync()`
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` (deps, body stack, loadSecondaryData, render + tap)
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceMetaCommunityRowView.swift`
- Modify: every `Dependencies`/double the `HasMetaCommunityService` cascade reaches (compiler/linker will name them; expect `SnapshotDependencies`-style doubles needing `var metaCommunityService: MetaCommunityServiceType { <stub> }`)
- Test: `SpudDataKitTests` (new sync accessor), `SpudSnapshotTests/InstanceDetailSnapshotTests.swift` (extend), a `SpudTests` VC-level gating test if the existing harness constructs this VC (check for an `InstanceDetail*Tests` fixture; if none exists, do NOT build a new harness — the gating is asserted structurally by the snapshot's absence state and reviewer)

**Interfaces:**
- Consumes: `MetaCommunityServiceType.refreshInstance(host:siteName:forAccountKeychainId:)`; `AppDatabase.observeMetaCommunities(forAccountId:instanceHost:) -> AsyncStream<[MetaCommunityListItem]>`; `accountRowIdSync(forKeychainId:)`; `InstanceSectionHeader`; the VC's existing `makeCard()`/`pinToCard` helpers and `observationTasks` lifecycle.
- Produces: `AppDatabase.defaultAccountKeychainIdSync() -> String?`; `InstanceMetaCommunityRowView(item: MetaCommunityListItem, accent: UIColor, onTap: @escaping () -> Void)`; `InstanceDetailViewController.renderMetaCommunities(_ items: [MetaCommunityListItem])` and a stored `metaItems: [MetaCommunityListItem]` Task 3 reads; `metaContainer: UIStackView` placed immediately BEFORE `communitiesContainer` in `makeBody()`.

- [ ] **Step 1: `defaultAccountKeychainIdSync()`** — TDD in `SpudDataKitTests`: seed two accounts (one service, one default) in `AppDatabase.inMemory()`, expect the default's keychain id; empty DB -> nil. Implement by reusing the EXACT selection logic `observeDefaultAccount()` uses (`Observations.swift:34` — read it and share/extract its query rather than re-deriving; nonisolated sync read via `writer.read`, logged-nil on error like sibling `*Sync` helpers).

- [ ] **Step 2: Dependency + cascade.** Add `HasMetaCommunityService` to `InstanceDetailViewController.OwnDependencies` (`InstanceDetailViewController.swift:20-24`) + a `metaCommunityService` accessor beside the others. Run `make test` (full plan BUILD) and fix every double/`NestedDependencies` the linker or compiler names — additive stubs only.

- [ ] **Step 3: Row view.** `InstanceMetaCommunityRowView`: same metrics as `InstanceCommunityRowView` (38pt icon mark, 12 spacing, margins 10/13; reuse its hue-icon approach — extract or duplicate the small `iconMark` helper per local judgment, but note `InstanceCommunityRowView.iconMark` is `private static`, so prefer extracting a shared file-internal helper into the Components folder over copy-paste). Content: `c/<name>` bold label + the shared meta badge glyph (a `UIImageView(systemName: "building.2.fill")`, tinted `.tertiaryLabel`, sized like `SearchCommunityCell`'s badge — read that cell first) horizontally after the name; subtitle = `item.title` (hidden when nil/empty — NOT the directory-stats subtitle, meta items carry no counts); trailing chevron. Whole row tappable (`UIControl`/tap recognizer) calling `onTap`; a11y: one combined element, label "c/<name>, Instance community", `.button` trait.

- [ ] **Step 4: Wire the screen.** In `makeBody()` (line ~361), create `metaContainer` (vertical stack, spacing 8, `isHidden = true`) and add it BEFORE `communitiesContainer`. In `loadSecondaryData()` (line ~803), after the existing community render:

```swift
        if let userKeychainId = appDatabase.defaultAccountKeychainIdSync(),
           let accountId = appDatabase.accountRowIdSync(forKeychainId: userKeychainId)
        {
            let metaService = metaCommunityService
            let host = record.baseurl
            let siteName: String? = record.name
            observationTasks.append(Task { @MainActor [weak self] in
                // Fire-and-forget: the observation below renders whatever the
                // refresh (or a previous day's cache) yields; a miss just
                // leaves the section absent.
                await metaService.refreshInstance(host: host, siteName: siteName, forAccountKeychainId: userKeychainId)
            })
            let appDatabase = appDatabase
            observationTasks.append(Task { @MainActor [weak self] in
                for await items in appDatabase.observeMetaCommunities(forAccountId: accountId, instanceHost: host) {
                    if Task.isCancelled { break }
                    guard let self else { break }
                    renderMetaCommunities(items)
                }
            })
        }
```

(Verify `record.baseurl` is the bare host and `record.name` the instance's human name — both are `ExplorerInstanceRecord` fields used elsewhere in this file; adjust to the actual property names.) `renderMetaCommunities`: store `metaItems = items`; `metaContainer.isHidden = items.isEmpty`; clear + rebuild — `InstanceSectionHeader` "About this instance" with `count: items.count`, then a `makeCard()` containing the rows separated by the same 0.5pt inset hairlines the Communities card uses (`renderCommunities`, line ~863-891, is the template). Row `onTap` opens the community:

```swift
        guard
            let window = view.window as? MainWindow,
            let itemHost = URL(string: item.communityActorId)?.host,
            let instance = InstanceActorId(from: "https://\(itemHost)"), instance.isValid
        else { return }
        AppCoordinator.shared.open(URL.SpudInternalLink.community(name: item.name, instance: instance).url, in: window)
```

(The host for the link comes from the ITEM's own `communityActorId` URL host — a meta community is by definition local to the viewed instance, but deriving it from the actorId means the link can never disagree with the resolved row. Verify the `SpudInternalLink.community` signature against `InboxViewController.openReminder`'s branch, which does exactly this.)

- [ ] **Step 5: Snapshot.** Extend `InstanceDetailSnapshotTests`: a state with a seeded default account + two mirrored `community` rows + two `instanceMetaCommunity` cache rows for the record's host (read the suite's existing seeding helpers first; it drives this exact VC with `SnapshotDependencies`). Assert via the suite's existing tall-capture pattern (`snapshotContentHeight`). Record -> verify on the reference sim; stage only the new refs.

- [ ] **Step 6: Run, format, commit.** `make test-only ONLY=SpudDataKitTests`, full `make test` (cascade check), snapshot class record+verify. `mint run swiftformat SpudDataKit/ Spud/ SpudDataKitTests/ SpudSnapshotTests/ && make project`. Commit: `feat: About this instance meta section on instance detail`.

---

### Task 3: Long-press context menu on meta rows

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` (host conformance + row menu attachment), `Spud/Scenes/Account/InstanceDetail/Components/InstanceMetaCommunityRowView.swift` (context-menu hook if needed)
- Create: `Spud/Scenes/Account/InstanceDetail/MetaCommunityMenuAdapter.swift` (the `MetaCommunityListItem -> SearchCommunityResult` mapping, pure + testable)
- Test: `SpudTests/MetaCommunityMenuAdapterTests.swift` (create); extend the builder suite only if a gap appears

**Interfaces:**
- Consumes: Task 1's optional-favourite builder; Task 2's `metaItems` + row view; `CommunityContextMenuBuilder.menu(for:subscribedState:host:)`; `CommunityContextMenuHost` incl. the notify methods (existing) and favourite methods (Task 1); `AccountScope` via `accountService.scope(forAccountKeychainId: <default account>)`; favourite/mute sync queries (`favoriteCommunitySync`/`unfavoriteCommunitySync`/`isCommunityFavoritedSync`, `muteCommunitySync`/`unmuteCommunitySync`/`isCommunityMutedSync` — all keyed `(forKeychainId:communityActorId:)`); `activeReminderKindsSync` + `setCommunityFollow`/`removeCommunityFollow`; `CommunityNotifyLabel`.
- Produces: `MetaCommunityMenuAdapter.searchResult(for item: MetaCommunityListItem) -> SearchCommunityResult?` (nil when the actorId has no parseable host).

- [ ] **Step 1: Failing adapter tests.** Mapping: `serverCommunityId == Lemmy.CommunityID(item.id)`, `name`, `qualifiedName == "name@<actorId host>"`, `instance` built from the actorId's host, `iconUrl` from the string, `communityUrl == item.communityActorId`, `subscribersText == ""` (menu never renders it), `isNsfw == false` (menu never reads it — document both defaults), `followState` mapped from `item.subscribedState` (check for an existing `CommunitySubscribedState <-> FollowState` mapping near `Community.swift:137`'s `init(followState:)` and reuse/invert it; write the explicit 5-case switch only if none exists). Nil when actorId host unparseable. Run; expect FAIL.

- [ ] **Step 2: Implement the adapter** (pure enum/struct, `@testable`-visible). Then conform `InstanceDetailViewController: CommunityContextMenuHost`, resolving the acting scope once per action from the stored default-account keychain id (capture it in Task 2's gate and store as `metaActingKeychainId: String?`):
  - `communityOpen` -> the Task 2 tap path.
  - `communitySetSubscribed` -> `scope.lemmyService.setSubscribed(serverCommunityId:subscribed:)` in a weak-self Task, `try?` (outbox-owned), `Haptics.tap()`.
  - `communityIsMuted`/`communityMute`/`communityUnmute` -> the actorId-keyed sync queries (mirror `SearchViewController`'s host methods ~955-1047 — read them first and match their shapes, including any duration handling).
  - `communityShare`/`communityCopyLink` -> mirror Search's (share sheet / pasteboard on `communityUrl`).
  - `communityBlock` -> mirror Search's block flow AND append the fire-and-forget follow removal (fourth site — copy the exact `Task { [accountScope] in try? await ... removeCommunityFollow(...) }` + why-comment shape from `SearchViewController.communityBlock`).
  - `communityFavoriteState` -> `appDatabase.isCommunityFavoritedSync(forKeychainId:communityActorId:)`; `communityToggleFavorite` -> favorite/unfavorite sync + `Haptics.tap()`.
  - `communityIsNotifying`/`communityToggleNotify` -> mirror `SearchViewController`'s implementations (tap-time re-read; identity: `title ?? name` for the follow's title, host from the actorId URL, icon from the item; toasts via `CommunityNotifyLabel`).
  Attach a `UIContextMenuInteraction` to each meta row (menu built at interaction time: `CommunityContextMenuBuilder.menu(for: adapterResult, subscribedState: item.subscribedState, host: self)`); skip attaching when the adapter returns nil.

- [ ] **Step 3: Sign-in gating check.** The builder's subscribe action must reflect this screen's acting account: verify what Search does for a signed-out account (does the host hide subscribe, or does the action no-op?) and match it exactly; state your finding in the report.

- [ ] **Step 4: Run, format, commit.** Adapter suite + `make test-only ONLY=SpudTests`; `make build`. `mint run swiftformat Spud/ SpudTests/ && make project` (new file). Commit: `feat: community context menu on instance-detail meta rows`.

---

### Task 4: Docs + full verification sweep

**Files:**
- Modify: `docs/features/instance-browsing.md` (the section + Given/When/Then scenarios: see the section when viewing an instance in-app; tap opens the community; long-press menu incl. Favourite + Notify; absent pre-account), `docs/features/instance-meta-communities.md` (remove the DEFERRED Task-12 note, document the new surface, reconcile `Related:`), `docs/features/reminders.md` (entry-point list gains the instance-detail menu — count becomes six), `docs/features/search.md` (note the builder's Favourite item is host-optional and Search does not show it), `docs/features/README.md` (BOTH the capability table rows touching instance detail / meta communities / reminders AND the by-area map)

- [ ] **Step 1: Docs.** Follow each file's conventions (`Surfaces:`/`Status:`/`Related:`, `## What it does`, `## Behavior and rules`, `## Scenarios`, `## Not supported / out of scope`); no `.swift` links; no emojis; verify every behavior claim against the shipped code (copy strings, gate rule, menu contents). `grep -rn "DEFERRED" docs/features/instance-meta-communities.md` must come back empty afterwards.
- [ ] **Step 2: Full sweep.** `mint run swiftformat .` then inspect `git status -u` for unexpected rewrites; `make test` (known flakes: isolate-and-rerun); `make snapshot` (pre-existing refs must not change; `git annex restage` clears cosmetic ` M`).
- [ ] **Step 3: Commit.** `docs: document the instance-detail meta section`.

---

## Execution notes

- Worktree off local `main`: `git worktree add -b feat/instance-detail-meta-section <path> main` from the main checkout; `make project` in the worktree before first build.
- Re-check `main..feat/instance-detail-meta-section` overlap right before merging (shared checkout; run `git annex restage` first if merging with `main` checked out).
- Snapshot work happens on the booted reference iPhone 17 Pro only.
