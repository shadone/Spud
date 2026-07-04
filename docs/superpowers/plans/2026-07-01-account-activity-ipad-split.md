# Account → Activity — Phase 3 (iPad split + footprint rail) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On iPad regular width, present Account → Activity as a two-column split — the Activity timeline (primary) beside the Summary dashboard pinned in the detail column — and add the iPhone "Your footprint" summary rail above the timeline.

**Architecture:** Mirror the already-merged `CommunityReadingSplitViewController` container pattern: a plain `UIViewController` that embeds a child `UISplitViewController(style: .doubleColumn)` (UIKit refuses to push a split VC onto a nav stack). Primary column hosts the existing `ActivityViewController`; the detail column is a nav stack rooted at the existing `SummaryViewController`, so tapping a post/comment pushes its detail over Summary with a free "‹ Summary" back button. Routing reuses the merged `SplitTabResolver` / `MainWindow.pushIntoCurrentContext`. On iPhone (and any collapsed split) the timeline shows the footprint rail and a Summary nav button instead, byte-for-byte the current behavior plus the rail.

**Tech Stack:** UIKit, Swift 6, `@Observable`/`@MainActor`, GRDB (in-memory for tests), Swift Testing (unit), pointfreeco/swift-snapshot-testing (snapshots), SBTUITestTunnel (UI tests).

## Global Constraints

- **Routing keys on `splitViewController.isCollapsed`, never `horizontalSizeClass`** — a split's primary column reports `.compact` even when the window is regular. The ONE exception is the *entry decision* (whether to build the split at all) in `AccountViewController.openActivity()`, which gates on `traitCollection.horizontalSizeClass == .regular` exactly like `SubscriptionsViewController` / `DiscoverViewController` do (the split is a full-screen nav root there, not a split column).
- **iPhone / compact must stay behavioral-identity** except for the new footprint rail. The split is iPad-regular-only.
- **Determinism:** any relative-time or date logic takes an injected reference date (`asOf`); snapshots must never read the wall clock. `SummaryViewController` already has `asOf: Date = Date()` — pass a fixed date in every snapshot.
- **Reuse, don't fork:** reuse `SummaryViewModel`'s stat pipeline (`PersonFormatter` / `CommentsFormatter`) for the rail's quick stats — do NOT recompute or fork formatters (a forked-formatter regression already happened once this initiative).
- **No emojis** in code, comments, or docs.
- **SwiftFormat before the final verify, never after:** `mint run swiftformat <explicit paths>`. Beware `--enable isEmpty` rewriting `x.count == 0` on a type without `isEmpty` (breaks the build); guard with `// swiftformat:disable:next isEmpty` if needed.
- **Swift Testing:** `struct` suites, `@Test func`, `#expect`/`#require`. Tests run in PARALLEL — a suite touching process-global state needs `@Suite(.serialized)`. `import Testing` does not re-export Foundation — add `import Foundation` for `Date`/`URL`.
- **Staging:** stage explicit paths only (`git add <path>` …), never `git add -A` (git-annex snapshot PNGs show cosmetic ` M`). `git status -uall` to see untracked.
- **Build/test from the repo root** (this worktree root — `project.yml` + `Makefile` live here). Run `make project` first if `Spud.xcodeproj` is absent (it is gitignored/generated). Headless xcodebuild needs `-skipPackagePluginValidation -skipMacroValidation`.

### Canonical commands (run from repo root)

```bash
make project   # (re)generate the gitignored Spud.xcodeproj from project.yml — run once / after target changes

# Build
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation build

# Unit tests (SpudTests + SpudDataKit + SpudUtilKit + UI live in the Spud test plan)
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 test

# A single unit target / suite
#   add -only-testing:SpudTests/SplitTabResolverTests  (etc.)

# Snapshot tests — pin the OS. Installed runtime is 26.3.1; OS=26.3 may not resolve.
# Prefer the booted iPhone 17 Pro sim, or pin OS=26.3.1.
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -skipPackagePluginValidation -skipMacroValidation test
```

A convenience wrapper exists: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` (no `--testPlan`; falls back to xcodebuild for snapshot plans). Use `ddenis:xcode-skill` for xcresult parsing.

---

## File Structure

**New files:**
- `Spud/Scenes/Activity/ActivityFootprintRailView.swift` — the iPhone "Your footprint" rail card (UIView).
- `Spud/Scenes/Activity/ActivityFootprintRail.swift` — pure visibility helper + the `FootprintStat` value type (so the rule is unit-testable without UIKit hosting).
- `Spud/Scenes/Activity/ActivitySummaryReadingSplitViewController.swift` — the iPad container + embedded split.
- `SpudTests/ActivityFootprintRailTests.swift` — visibility-rule unit tests.
- `SpudTests/ActivitySummaryReadingSplitViewControllerTests.swift` — container-construction unit tests.
- `SpudSnapshotTests/ActivityIPadSplitSnapshotTests.swift` — iPad two-column structure snapshot.
- `SpudSnapshotTests/ActivityFootprintRailSnapshotTests.swift` — rail card + composite-header snapshots (the handoff's required header snapshot).

**Modified files:**
- `Spud/Scenes/Activity/ActivityViewController.swift` — header composition (filter bar + optional rail), `summaryIsPinned` input, Summary-button visibility, rail tap → `openSummary()`.
- `Spud/Scenes/MainWindow/SplitTabResolver.swift` — new `DetailRouteTarget.activitySummary` case + detection.
- `Spud/Scenes/MainWindow/MainWindow.swift` — handle the new case in `pushIntoCurrentContext()`.
- `Spud/Scenes/Account/AccountViewController.swift` — `openActivity()` gates the split on regular width.
- `SpudTests/SplitTabResolverTests.swift` — new resolver-case test.
- `docs/features/account-activity.md` + `docs/features/README.md` — document the split + rail.

**Reference (read as templates, do not edit):**
- `Spud/Scenes/Community/CommunityReadingSplitViewController.swift` — the container/embedded-split/back-button/nav-hide recipe.
- `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` — `setViewController(_, for: .compact)` + collapse/expand handling.
- `SpudTests/SplitTabResolverTests.swift` (`FakeDependencies`, lines ~33-162) — DI test harness.
- `SpudSnapshotTests/IPadLayoutSnapshotTests.swift` — `SnapshotDependencies`, in-memory seeding, `.iPadPro11(.landscape)` config.
- `Spud/Scenes/Activity/Summary/SummaryViewModel.swift` + `SummaryStatTilesView.swift` — the stat model the rail reuses.

---

## Task 1: Footprint rail — visibility rule + value type (pure, TDD)

A pure, UIKit-free helper so the show/hide rule is unit-testable. The rule (from the design: the rail shows only in the default glance state):

> Show the rail when **not** in a pinned-Summary split **and** the active filters equal the default set **and** there is no search query **and** the timeline has content.

**Files:**
- Create: `Spud/Scenes/Activity/ActivityFootprintRail.swift`
- Test: `SpudTests/ActivityFootprintRailTests.swift`

**Interfaces:**
- Produces:
  - `struct FootprintStat: Equatable, Sendable { let value: String; let label: String }`
  - `enum ActivityFootprintRail { static func isVisible(summaryIsPinned: Bool, activeFilters: Set<ActivityFilterType>, defaultFilters: Set<ActivityFilterType>, hasSearchQuery: Bool, hasContent: Bool) -> Bool }`
- Consumes: `ActivityFilterType` (from `SpudDataKit`, already `public`).

- [ ] **Step 1: Write the failing test**

```swift
// SpudTests/ActivityFootprintRailTests.swift
import Testing
@testable import Spud
@testable import SpudDataKit

struct ActivityFootprintRailTests {
    private let def: Set<ActivityFilterType> = [.post, .comment, .save]

    @Test func visibleInDefaultGlanceState() {
        #expect(ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: true))
    }

    @Test func hiddenWhenSummaryPinned() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: true, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: true))
    }

    @Test func hiddenWhenFiltersNonDefault() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: [.comment], defaultFilters: def,
            hasSearchQuery: false, hasContent: true))
    }

    @Test func hiddenWhileSearching() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: true, hasContent: true))
    }

    @Test func hiddenWhenEmpty() {
        #expect(!ActivityFootprintRail.isVisible(
            summaryIsPinned: false, activeFilters: def, defaultFilters: def,
            hasSearchQuery: false, hasContent: false))
    }

    @Test func footprintStatEquates() {
        #expect(FootprintStat(value: "12", label: "Posts") == FootprintStat(value: "12", label: "Posts"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudTests/ActivityFootprintRailTests test`
Expected: FAIL — `cannot find 'ActivityFootprintRail' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Spud/Scenes/Activity/ActivityFootprintRail.swift
import Foundation
import SpudDataKit

/// One quick stat shown in the footprint rail (mirrors a Summary stat tile).
struct FootprintStat: Equatable, Sendable {
    let value: String
    let label: String
}

/// Pure visibility rule for the iPhone "Your footprint" rail. Kept UIKit-free
/// so the rule is unit-testable. The rail is a default-state glance only; it is
/// suppressed on iPad where the Summary is pinned in the detail column.
enum ActivityFootprintRail {
    static func isVisible(
        summaryIsPinned: Bool,
        activeFilters: Set<ActivityFilterType>,
        defaultFilters: Set<ActivityFilterType>,
        hasSearchQuery: Bool,
        hasContent: Bool
    ) -> Bool {
        guard !summaryIsPinned else { return false }
        guard activeFilters == defaultFilters else { return false }
        guard !hasSearchQuery else { return false }
        return hasContent
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: same `-only-testing:SpudTests/ActivityFootprintRailTests test`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Activity/ActivityFootprintRail.swift SpudTests/ActivityFootprintRailTests.swift
git commit -m "feat(activity): footprint rail visibility rule + FootprintStat"
```

---

## Task 2: Footprint rail view + ActivityViewController integration (iPhone)

Build the rail card and wire it into the timeline header. Reuse `SummaryViewModel` for the four quick stats (no forked formatters). Compose an explicitly-sized `tableHeaderView` containing the filter bar plus the optional rail (the Phase-1 collapse-prone surface — size it explicitly).

**Files:**
- Create: `Spud/Scenes/Activity/ActivityFootprintRailView.swift`
- Modify: `Spud/Scenes/Activity/ActivityViewController.swift`
- Test: `SpudSnapshotTests/ActivityFootprintRailSnapshotTests.swift`

**Interfaces:**
- Consumes: `FootprintStat` (Task 1); `ActivityFootprintRail.isVisible(...)` (Task 1); existing `SummaryViewModel` (init `(accountId:personRowId:asOf:dependencies:)`, exposes `var stats: [SummaryStat]` — confirm the property name by reading `SummaryViewModel.swift`/`SummaryStatTilesView.swift`; map each to `FootprintStat(value:label:)`).
- Produces:
  - `final class ActivityFootprintRailView: UIView` with `var onTapSummary: (() -> Void)?` and `func configure(stats: [FootprintStat], accent: UIColor)`.
  - On `ActivityViewController`: `func setSummaryIsPinned(_ pinned: Bool)` (default state is `false`), used by Task 3's container.

**Design reference (from `screens-activity.jsx` → `SummaryRail`):** card with `t.elev` background, 14pt corner radius, hairline border, ~11x13 padding. Header row: spud-glyph + "Your footprint" (13pt, weight 700) on the left, "Summary ›" (12pt, weight 600, accent) on the right. Below: a single row of up to four columns, each a left-aligned value (17pt, weight 800, monospaced digits) over a label (10pt, secondary). Whole card is tappable → `onTapSummary`.

- [ ] **Step 1: Write the failing snapshot test**

```swift
// SpudSnapshotTests/ActivityFootprintRailSnapshotTests.swift
import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

final class ActivityFootprintRailSnapshotTests: XCTestCase {
    private func makeRail() -> ActivityFootprintRailView {
        let rail = ActivityFootprintRailView()
        rail.configure(
            stats: [
                .init(value: "128", label: "Posts"),
                .init(value: "1.2k", label: "Comments"),
                .init(value: "342", label: "Saved"),
                .init(value: "5.0k", label: "Votes"),
            ],
            accent: UIColor(red: 0, green: 0.59, blue: 0.53, alpha: 1) // Lemmy teal
        )
        rail.frame = CGRect(x: 0, y: 0, width: 390, height: 84)
        return rail
    }

    func test_footprintRail_light() {
        let rail = makeRail()
        assertSnapshot(of: rail, as: .image(traits: .init(userInterfaceStyle: .light)), named: "light")
    }

    func test_footprintRail_dark() {
        let rail = makeRail()
        assertSnapshot(of: rail, as: .image(traits: .init(userInterfaceStyle: .dark)), named: "dark")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudSnapshotTests/ActivityFootprintRailSnapshotTests test`
Expected: FAIL — `cannot find 'ActivityFootprintRailView'`.

- [ ] **Step 3: Implement `ActivityFootprintRailView`**

Build the UIView per the design reference above. Use the app's existing theming/appearance source (read how `ActivityFilterBarView.swift` obtains accent + semantic colors and match it — do NOT hardcode beyond the snapshot fixture). Lay out with Auto Layout; the card content must fit within a host-provided width and report an intrinsic/explicit height (target ~84pt at default Dynamic Type). Make the whole card a single tap target wired to `onTapSummary`. Add a VoiceOver-friendly accessibility element: combined label e.g. "Your footprint. 128 posts, 1.2 thousand comments, 342 saved, 5 thousand votes.", trait `.button`, that triggers `onTapSummary` (so the rail is one accessible action, not five stray labels).

- [ ] **Step 4: Integrate into `ActivityViewController`**

Read `ActivityViewController.swift` first (header is currently `tableView.tableHeaderView = filterBarView`, ~50pt, lines ~282-283; Summary button wired ~244-248 → `openSummary()` ~693-704; filter toggles + search drive `viewModel`).

Make these changes:
1. Add stored `private var summaryIsPinned = false` and `func setSummaryIsPinned(_ pinned: Bool) { guard summaryIsPinned != pinned; summaryIsPinned = pinned; updateSummaryButtonVisibility(); rebuildTableHeader() }`.
2. Add a lazily-built `ActivityFootprintRailView` whose `onTapSummary = { [weak self] in self?.openSummary() }`.
3. Add a `SummaryViewModel` instance (same init the Summary screen uses — `accountId`, `personRowId`, `dependencies`) observed for `stats`; on change, map the first four to `[FootprintStat]`, call `railView.configure(stats:accent:)`, and `rebuildTableHeader()`. Start its observation in `viewDidLoad`/`viewWillAppear` consistent with how the VM is started in `SummaryViewController`.
4. `rebuildTableHeader()`: build a container `UIView` holding the filter bar; when `ActivityFootprintRail.isVisible(summaryIsPinned:activeFilters:defaultFilters:hasSearchQuery:hasContent:)` is true, also add the rail beneath it. **Set the container frame height explicitly** to the summed subview heights (filter bar height + rail height + insets), assign to `tableView.tableHeaderView`, then re-assign after `layoutIfNeeded()` so the table picks up the height (the standard tableHeaderView sizing dance). `defaultFilters` is the existing default set the VM seeds (read it from the VM / `ActivityFilterType` defaults — reuse, don't redefine). `hasContent` = `!viewModel.items.isEmpty`. `hasSearchQuery` = `!viewModel.searchQuery.isEmpty`.
5. Call `rebuildTableHeader()` wherever the inputs change: after filter toggles, after search-query changes, when `viewModel.items` transitions empty↔non-empty, and from `setSummaryIsPinned`.
6. `updateSummaryButtonVisibility()`: show the Summary nav button only when `!summaryIsPinned` (on iPad-pinned, Summary is already on screen). Default `false` → button shown, unchanged on iPhone.

iPhone behavior is unchanged except the rail now appears in the default state.

- [ ] **Step 5: Run to verify the snapshot test passes (record references)**

Run the Step-2 command with the recording env if first run (`SNAPSHOT_TESTING_RECORD=all` or the repo's recording convention — check `IPadLayoutSnapshotTests` for how refs are recorded). Re-run WITHOUT recording to confirm a clean pass.
Expected: PASS, two reference PNGs written under `SpudSnapshotTests/__Snapshots__/ActivityFootprintRailSnapshotTests/`.

- [ ] **Step 6: Build for iPhone + run the Activity unit tests**

Run the build command, then `-only-testing:SpudTests` Activity-related suites (and `-only-testing:SpudSnapshotTests/ActivitySnapshotTests` to confirm the existing 13 Activity snapshots still pass — the header change must not regress them; the rail is off by default in those fixtures unless they use the default-filter + content state, so re-record only if intentionally changed and justify).
Expected: build PASS; tests PASS.

- [ ] **Step 7: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Scenes/Activity/ActivityFootprintRailView.swift Spud/Scenes/Activity/ActivityViewController.swift SpudSnapshotTests/ActivityFootprintRailSnapshotTests.swift
git add Spud/Scenes/Activity/ActivityFootprintRailView.swift Spud/Scenes/Activity/ActivityViewController.swift SpudSnapshotTests/ActivityFootprintRailSnapshotTests.swift SpudSnapshotTests/__Snapshots__/ActivityFootprintRailSnapshotTests
git commit -m "feat(activity): Your footprint rail above the iPhone timeline"
```

If the existing Activity snapshot refs were re-recorded, stage and `git annex restage` them and explain why in the commit body.

---

## Task 3: iPad container — `ActivitySummaryReadingSplitViewController`

The container that makes the timeline + Summary sit side by side at regular width. Mirror `CommunityReadingSplitViewController` for the container/embedded-split/nav-hide/back-button recipe.

**Files:**
- Create: `Spud/Scenes/Activity/ActivitySummaryReadingSplitViewController.swift`
- Test: `SpudTests/ActivitySummaryReadingSplitViewControllerTests.swift`

**Interfaces:**
- Consumes: `ActivityViewController` (init `(accountKeychainId:initialFilters:dependencies:)` + `setSummaryIsPinned(_:)` from Task 2); `SummaryViewController` (init `(accountId:personRowId:asOf:dependencies:)`); the project's `Dependencies` surface used by both (read both VCs' inits for exact param names/types — `accountKeychainId: String`, `accountId: Int64`, `personRowId: Int64?`, `initialFilters: Set<ActivityFilterType>`).
- Produces:
  - `final class ActivitySummaryReadingSplitViewController: UIViewController`
    - `init(accountKeychainId: String, accountId: Int64, personRowId: Int64?, initialFilters: Set<ActivityFilterType>, dependencies: Dependencies)`
    - `func showDetail(_ viewController: UIViewController)` — collapsed → push on primary; expanded → set detail nav to `[summary, viewController]` (Summary stays the back target).
    - `var activityViewController: ActivityViewController { get }` and `var summaryViewController: SummaryViewController { get }` (for tests).

**Recipe (differences from `CommunityReadingSplitViewController`):**
- `embeddedSplit = UISplitViewController(style: .doubleColumn)`; `primaryNav = UINavigationController(rootViewController: activityViewController)`; `detailNav = UINavigationController(rootViewController: summaryViewController)`.
- `embeddedSplit.setViewController(primaryNav, for: .primary)`, `setViewController(detailNav, for: .secondary)`, `setViewController(primaryNav, for: .compact)`; `preferredDisplayMode = .oneBesideSecondary`; `preferredSplitBehavior = .tile`.
- `viewDidLoad`: child-add handshake (`add(child:)`, edge constraints, `didMove(toParent:)`); `primaryNav.delegate = self`; `embeddedSplit.delegate = self`; call `activityViewController.setSummaryIsPinned(!embeddedSplit.isCollapsed)`.
- `viewWillAppear`: `navigationController?.setNavigationBarHidden(true, animated:)`; `viewWillDisappear` (only when actually leaving): restore.
- `UINavigationControllerDelegate.willShow`: on the primary nav's root only, inject a left "Account" back button (mirror `makeBackButton()` but titled/targeted to pop the hosting nav: `navigationController?.popViewController`). Read the Community `makeBackButton()` for the exact `UIBarButtonItem(title:image:...)` chevron treatment and re-title to "Account".
- `showDetail(_:)`:
  ```swift
  func showDetail(_ viewController: UIViewController) {
      if embeddedSplit.isCollapsed {
          primaryNav.pushViewController(viewController, animated: true)
      } else {
          let nav = UINavigationController(rootViewController: viewController)
          nav.enableForwardNavigationGesture()
          detailNav.setViewControllers([summaryViewController, viewController], animated: true)
          _ = nav // not used in expanded mode; detail stays one nav rooted at Summary
      }
  }
  ```
  (Push onto the existing `detailNav` so the auto back button reads "Summary"; replacing item-over-Summary keeps a single post in detail.)
- `UISplitViewControllerDelegate`:
  - `splitViewControllerDidExpand(_:)` → `activityViewController.setSummaryIsPinned(true)`.
  - `splitViewControllerDidCollapse(_:)` → `activityViewController.setSummaryIsPinned(false)`; reset `detailNav.setViewControllers([summaryViewController], animated: false)` so a re-expand shows Summary, and the merged column shows only the timeline.
  - `splitViewController(_:topColumnForCollapsingToProposedTopColumn:)` → return `.primary` (collapse to the timeline, not Summary).

- [ ] **Step 1: Write the failing test**

```swift
// SpudTests/ActivitySummaryReadingSplitViewControllerTests.swift
import Testing
import UIKit
@testable import Spud
@testable import SpudDataKit

@MainActor
struct ActivitySummaryReadingSplitViewControllerTests {
    private func make() -> ActivitySummaryReadingSplitViewController {
        ActivitySummaryReadingSplitViewController(
            accountKeychainId: "test",
            accountId: 1,
            personRowId: 1,
            initialFilters: [.post, .comment, .save],
            dependencies: FakeDependencies() // reuse the harness from SplitTabResolverTests
        )
    }

    @Test func primaryIsActivity_detailRootIsSummary() {
        let vc = make()
        vc.loadViewIfNeeded()
        #expect(vc.activityViewController is ActivityViewController)
        #expect(vc.summaryViewController is SummaryViewController)
    }

    @Test func showDetailExpanded_keepsSummaryAsBackTarget() {
        let vc = make()
        vc.loadViewIfNeeded()
        // Force expanded geometry so isCollapsed == false.
        vc.view.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        vc.view.layoutIfNeeded()
        let detail = UIViewController()
        vc.showDetail(detail)
        // detail nav is rooted at Summary with the post on top.
        #expect(vc.detailNavViewControllersForTesting.first === vc.summaryViewController)
        #expect(vc.detailNavViewControllersForTesting.last === detail)
    }
}
```

(Add a tiny `var detailNavViewControllersForTesting: [UIViewController] { detailNav.viewControllers }` test seam, or assert via a public accessor — choose the lighter touch. If `FakeDependencies` needs a couple more conformances to build these VCs, extend it; it already constructs `CommunityReadingSplitViewController` in `SplitTabResolverTests`.)

- [ ] **Step 2: Run to verify it fails**

Run: `... -only-testing:SpudTests/ActivitySummaryReadingSplitViewControllerTests test`
Expected: FAIL — type not found.

- [ ] **Step 3: Implement the container** per the recipe above (read `CommunityReadingSplitViewController.swift` as the template).

- [ ] **Step 4: Run to verify it passes**

Run: same `-only-testing` command.
Expected: PASS.

- [ ] **Step 5: Build (iPhone) to confirm no compile regressions**

Run the build command. Expected: PASS.

- [ ] **Step 6: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Scenes/Activity/ActivitySummaryReadingSplitViewController.swift SpudTests/ActivitySummaryReadingSplitViewControllerTests.swift
git add Spud/Scenes/Activity/ActivitySummaryReadingSplitViewController.swift SpudTests/ActivitySummaryReadingSplitViewControllerTests.swift
git commit -m "feat(activity): iPad timeline+Summary split container"
```

---

## Task 4: Routing — resolver case, MainWindow handling, Account entry gate

Wire the container into the merged routing so tapping a post/comment in the timeline fills the iPad detail column, and so Account → Activity builds the split at regular width.

**Files:**
- Modify: `Spud/Scenes/MainWindow/SplitTabResolver.swift`
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift`
- Modify: `Spud/Scenes/Account/AccountViewController.swift`
- Test: `SpudTests/SplitTabResolverTests.swift`

**Interfaces:**
- Consumes: `ActivitySummaryReadingSplitViewController.showDetail(_:)` (Task 3).
- Produces: `DetailRouteTarget.activitySummary(ActivitySummaryReadingSplitViewController)`.

- [ ] **Step 1: Write the failing resolver test** (mirror `resolvesCommunityReadingSplitOnTopOfNavStack`)

```swift
// add to SpudTests/SplitTabResolverTests.swift
@Test
func resolvesActivitySummarySplitOnTopOfNavStack() throws {
    let split = ActivitySummaryReadingSplitViewController(
        accountKeychainId: "test", accountId: 1, personRowId: 1,
        initialFilters: [.post, .comment, .save], dependencies: FakeDependencies())
    let nav = UINavigationController(rootViewController: UIViewController())
    nav.pushViewController(split, animated: false)
    let postsSplit = UISplitViewController(style: .doubleColumn)
    let target = SplitTabResolver.target(for: nav, postsSplit: postsSplit)
    guard case let .activitySummary(resolved) = target else {
        Issue.record("expected .activitySummary, got \(target)"); return
    }
    #expect(resolved === split)
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `... -only-testing:SpudTests/SplitTabResolverTests/resolvesActivitySummarySplitOnTopOfNavStack test`
Expected: FAIL — no `.activitySummary` case.

- [ ] **Step 3: Add the resolver case**

In `SplitTabResolver.swift`, extend the enum and the `nav.viewControllers.last` branch (check `ActivitySummaryReadingSplitViewController` *before* the generic `.plainNav` fallback, alongside the `CommunityReadingSplitViewController` check):

```swift
enum DetailRouteTarget {
    case postsSplit
    case community(CommunityReadingSplitViewController)
    case activitySummary(ActivitySummaryReadingSplitViewController)
    case plainNav(UINavigationController)
    case none
}
// ... inside target(for:postsSplit:), in the `if let nav = selected as? UINavigationController` block:
if let community = nav.viewControllers.last as? CommunityReadingSplitViewController {
    return .community(community)
}
if let activity = nav.viewControllers.last as? ActivitySummaryReadingSplitViewController {
    return .activitySummary(activity)
}
return .plainNav(nav)
```

- [ ] **Step 4: Run to verify the resolver test passes** — Expected: PASS (also confirm the existing 4 resolver tests still pass: `-only-testing:SpudTests/SplitTabResolverTests`).

- [ ] **Step 5: Handle the new case in MainWindow**

In `MainWindow.pushIntoCurrentContext(_:)` add:

```swift
case let .activitySummary(split):
    split.showDetail(viewController)
```

- [ ] **Step 6: Gate the entry in AccountViewController**

In `AccountViewController.openActivity()` (currently always pushes `ActivityViewController`), branch on regular width:

```swift
private func openActivity(initialFilters: Set<ActivityFilterType> = ...) {
    let nav = navigationController
    if traitCollection.horizontalSizeClass == .regular {
        let split = ActivitySummaryReadingSplitViewController(
            accountKeychainId: keychainId,
            accountId: accountId,
            personRowId: personRowId,
            initialFilters: initialFilters,
            dependencies: dependencies.nested
        )
        nav?.pushViewController(split, animated: true)
    } else {
        let activityVC = ActivityViewController(
            accountKeychainId: keychainId,
            initialFilters: initialFilters,
            dependencies: dependencies.nested
        )
        nav?.pushViewController(activityVC, animated: true)
    }
}
```

Read `AccountViewController.swift` for the exact local names (`keychainId`, `accountId`, `personRowId`, `dependencies.nested`, the existing `initialFilters` plumbing). Keep the deep-link entry points (Saved / Your posts / Your comments → Activity scope) working through whichever branch is taken.

- [ ] **Step 7: Build + run the full unit test plan**

Run the build command, then the full unit-test command (`-testPlan Spud`). Expected: build PASS; all unit tests PASS (existing ~606 SpudDataKit + SpudTests, plus the new suites).

- [ ] **Step 8: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Scenes/MainWindow/SplitTabResolver.swift Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/Account/AccountViewController.swift SpudTests/SplitTabResolverTests.swift
git add Spud/Scenes/MainWindow/SplitTabResolver.swift Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/Account/AccountViewController.swift SpudTests/SplitTabResolverTests.swift
git commit -m "feat(activity): route Activity detail into the iPad split; build split at regular width"
```

---

## Task 5: iPad structure snapshot + (best-effort) UITest

Deterministic structural proof that at regular width the Activity area is two columns (timeline + Summary). Snapshot is the reliable proof (no auth, in-memory data, fixed `asOf`); a UITest is best-effort because the live screen is auth-gated.

**Files:**
- Create: `SpudSnapshotTests/ActivityIPadSplitSnapshotTests.swift`
- (Best-effort) Modify: `SpudUITests/IPadSplitUITests.swift`

- [ ] **Step 1: Write the iPad split snapshot test**

Mirror `IPadLayoutSnapshotTests` (`SnapshotDependencies`, in-memory `AppDatabase`, seed authored posts/comments + local activity, build the VCs, host `ActivitySummaryReadingSplitViewController`, snapshot on `.iPadPro11(.landscape)`). Pass a **fixed `asOf`** to the Summary so the heatmap/relative time is deterministic. Reuse the seeding helpers from `ActivitySnapshotTests` / `SummarySnapshotTests` (read them) rather than re-seeding from scratch.

```swift
// shape (fill in seeding from the existing Activity/Summary snapshot harnesses)
func test_activitySplit_ipad_landscape_dark() async throws {
    let appDatabase = try AppDatabase.inMemory()
    try await seedActivity(into: appDatabase)            // reuse existing helper
    let deps = SnapshotDependencies(appDatabase: appDatabase /* ... */)
    let split = ActivitySummaryReadingSplitViewController(
        accountKeychainId: "snap", accountId: 1, personRowId: 1,
        initialFilters: [.post, .comment, .save], dependencies: deps)
    // give Summary a fixed asOf via the container or a test init seam
    try await waitUntil { /* timeline + stats populated */ }
    assertSnapshot(of: split,
        as: .image(on: .iPadPro11(.landscape), traits: .init(userInterfaceStyle: .dark)),
        named: "dark")
}
```

If `ActivitySummaryReadingSplitViewController` has no way to inject `asOf`, add an optional `asOf: Date = Date()` init param threaded to the `SummaryViewController` (matches Summary's existing seam) — small, justified change; if so, update Task 3's init signature note.

- [ ] **Step 2: Run, record refs, re-run to confirm deterministic pass**

Run the snapshot command twice (record, then verify) — and a third time at a **different wall-clock** to prove determinism (the initiative was bitten by wall-clock-nondeterministic snapshots). Expected: identical PASS each time.

- [ ] **Step 3: (Best-effort) iPad UITest**

If `IPadSplitUITests` / SBTUITestTunnel already has a signed-in-account stub or a debug launch-arg that lands in a signed-in Account tab, add `test_accountActivity_showsTwoColumnSplit()` mirroring `test_discoverCommunity_showsTwoColumnSplit` (assert: a Summary element exists in the secondary column, the "Account" back button exists in primary, primary.midX < secondary.midX). If reaching a signed-in Activity needs infrastructure that does not exist, **do not build it here** — add an `XCTSkip("Activity is auth-gated; covered by ActivityIPadSplitSnapshotTests + manual on-device verify")` stub and `log()` the gap. Do not silently omit it.

- [ ] **Step 4: SwiftFormat + commit**

```bash
mint run swiftformat SpudSnapshotTests/ActivityIPadSplitSnapshotTests.swift SpudUITests/IPadSplitUITests.swift
git add SpudSnapshotTests/ActivityIPadSplitSnapshotTests.swift SpudSnapshotTests/__Snapshots__/ActivityIPadSplitSnapshotTests SpudUITests/IPadSplitUITests.swift
git commit -m "test(activity): iPad two-column split snapshot (+ best-effort UITest)"
```

---

## Task 6: Documentation

Per the docs discipline: update the per-capability doc AND the README index (capability table + by-area map); re-verify adjacent docs; no `.swift` links.

**Files:**
- Modify: `docs/features/account-activity.md`
- Modify: `docs/features/README.md`
- Re-verify (read; edit only if now inaccurate): the iPad adaptive-layout feature doc (the one added by the ipad-split-polish merge — find it in `docs/features/`).

- [ ] **Step 1: Update `account-activity.md`**

Add an "iPad — split view" subsection: at regular width Account → Activity is a two-column split — timeline in the primary column, the Summary dashboard pinned in the detail column; tapping a post/comment opens it in the detail column over Summary with a back affordance; on iPhone / collapsed width it stays a single column with the Summary reached via the nav button and the new "Your footprint" rail above the timeline. Add a "Your footprint rail" note under the timeline behavior: a default-state-only glance (default filters, no search, has content) showing four quick stats and a Summary entry point; suppressed when Summary is pinned (iPad). Keep `Surfaces: iphone, ipad`.

- [ ] **Step 2: Update `docs/features/README.md`** — reflect the new iPad split + rail in the capability table row and the by-area map (Account / Activity). No source-file links.

- [ ] **Step 3: Re-verify the adjacent iPad adaptive-layout doc** — read it; if it enumerates which screens have splits, add Activity. Fix only genuine inaccuracies.

- [ ] **Step 4: Commit**

```bash
git add docs/features/account-activity.md docs/features/README.md docs/features/<ipad-doc>.md
git commit -m "docs(activity): document iPad split + footprint rail"
```

---

## Final verification (whole-branch, before merge handoff)

Not a task — the closing gate (do this yourself, not via the implementer who wrote the code):

1. `make project` then full build (iPhone 17 Pro) — clean, **zero new warnings** introduced by the branch.
2. Full unit plan: `-testPlan Spud` — all green (note the SpudDataKit Swift-Testing count vs the 606 baseline).
3. Snapshot plan: `-testPlan SpudSnapshots` on iPhone 17 Pro pinned OS — all green; re-run the two NEW snapshot suites at a **different wall-clock** to prove determinism.
4. Confirm iPhone/compact is behavioral-identity apart from the rail (diff the ActivityViewController header path; the existing 13 Activity snapshots unchanged unless deliberately re-recorded).
5. Whole-branch independent review (fresh reviewer / `ddenis:swiftui-pro` + `ddenis:code-reviewer`): correctness of collapse/expand handling, no `horizontalSizeClass`-for-routing, a11y on the rail, no forked formatters, docs accuracy.
6. SwiftFormat was run before this verify (not after). `git status -uall` clean except intended files.

## Self-review notes (spec coverage)

- iPad split (timeline primary + Summary detail pinned, master-detail with Summary as home) → Tasks 3+4 (+5 proof). ✓
- Tapping a post/comment opens in detail over Summary with back affordance → Task 3 `showDetail` (detailNav rooted at Summary) + Task 4 routing. ✓
- "Your footprint" rail on iPhone, default-state only, reuses Summary stats → Tasks 1+2. ✓
- Summary button hidden when pinned; rail hidden when pinned → Task 2 (`setSummaryIsPinned`). ✓
- Collapse/expand correctness (multitasking) → Task 3 delegate methods. ✓
- iPhone/compact unchanged → Global Constraints + Task 2/4 branching. ✓
- Determinism, reuse-not-fork, no-emoji, SwiftFormat-timing, explicit staging → Global Constraints, enforced per task. ✓
- Docs → Task 6. ✓
