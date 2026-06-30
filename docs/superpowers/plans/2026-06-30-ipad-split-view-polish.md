# iPad / split-view polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iPad regular size class a first-class layout — adaptive widths, correct iPad presentation idioms, a feed-switcher popover, and a 2-column Communities reading split — without changing iPhone/compact behavior.

**Architecture:** Three independent tiers. Tier A is pure SwiftUI/UIKit layout adaptivity gated on the regular size class. Tier B replaces the Posts feed-switcher back-stack with a navbar-title popover in regular width. Tier C makes the Communities tab host a 2-column `[community feed | post detail]` reading context on iPad, and generalizes the `MainWindow` detail router so any split tab (not just Posts) receives detail pushes.

**Tech Stack:** Swift 6 / UIKit + SwiftUI, GRDB, `@Observable` view models, `pointfreeco/swift-snapshot-testing`, `SBTUITestTunnel` UI tests, XcodeGen-generated project.

## Global Constraints

- **Swift 6.0 language mode + complete strict concurrency** on every shipped target. New view-model logic is `@Observable`; reactive via AsyncSequence/Observation (no Combine, no Core Data).
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- **iPhone / compact behavior must be byte-for-byte unchanged.** Every change is gated on `horizontalSizeClass == .regular` or relies on automatic split-view collapse.
- **Build wrapper:** `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` (incremental, parses errors). Pass `--simulator "iPhone 17 Pro"` unless a sim is already booted; target the BOOTED sim by `id=` to avoid the "Busy / preflight" contention flake.
- **Unit tests are Swift Testing** (`import Testing`, `struct` suites, `@Test`, `#expect`/`#require`; `import Foundation` explicitly when using `URL`/`Date`). Run via `-only-testing:SpudTests` in the `Spud` test plan. Run SwiftFormat (`mint run swiftformat <paths>`) BEFORE the final verify, never after.
- **Snapshot tests** (`SpudSnapshots.xctestplan`): app-level/full-screen refs are device+runtime-sensitive (iPhone 17 Pro / iOS 26.3.1 only). NEW iPad configs use `.image(on: .iPadPro11(.landscape), traits:)` / `.iPadPro11(.portrait)` — these pin an explicit size+traits, so they are device-independent (any sim; first run records missing refs + fails, rerun verifies). Record/verify ONE class at a time; `git add` only the explicit refs you recorded (the suite carries dozens of cosmetically-`M` annex refs that are not your change). No existing iPad snapshot config exists — these are the first.
- **New source files require `make project`** (XcodeGen) before they compile.
- **Run from** `/Users/denis/dev/info.ddenis/Spud/Spud`. Work in an isolated worktree off `main`; verify `git branch --show-current` before every commit.
- **Docs discipline:** every user-facing change updates `docs/features/` + the README capability table AND the by-area map (Task D1 covers this for the whole iteration).

---

## File Structure

**Tier A**
- Modify `Spud/Scenes/Discover/DiscoverView.swift` — rails → adaptive grid (regular); directory `LazyVStack` width cap.
- Modify `Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift` — banner content width cap + downsample-width cap.
- Modify `Spud/Scenes/Account/AccountView.swift` — center + cap the full-bleed banner row in regular width.
- Modify `Spud/Scenes/Composer/ComposerViewController.swift`, `Spud/Scenes/Composer/NewPostViewController.swift` — set `modalPresentationStyle = .pageSheet` before the detent block.
- Modify `Spud/Scenes/Account/AccountList/AccountListViewController.swift`, `Spud/Scenes/Account/AccountViewController.swift` — popover on iPad, sheet on compact.
- Create `Spud/Utils/AdaptiveLayout.swift` — small pure helpers (width cap, presentation-style decision) so the size-class logic is unit-testable.

**Tier B**
- Modify `Spud/Scenes/PostList/PostListViewController.swift` — title-control popover affordance + size-class handling.
- Modify `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` — size-class-aware primary stack (no FeedSwitcher beneath PostList in regular).

**Tier C**
- Create `Spud/Scenes/Community/CommunityReadingSplitViewController.swift` — the per-community 2-column reading container (spike-validated mechanic).
- Modify `Spud/Scenes/Subscriptions/SubscriptionsViewController.swift` — open a community via the reading split on iPad.
- Modify `Spud/Scenes/MainWindow/MainWindow.swift` — generalize `pushIntoCurrentContext` / `pushDetail` to any active split tab.

**Tests / docs**
- Create `SpudSnapshotTests/IPadLayoutSnapshotTests.swift`.
- Create/modify a `SpudUITests` case for the Communities split path.
- Create `Spud/SpudTests/AdaptiveLayoutTests.swift` (unit).
- Create `docs/features/ipad-layout.md`; modify `docs/features/README.md`.

---

## Task 1 (A): Adaptive-layout helpers (pure, unit-tested)

Extract the size-class decisions into pure functions first so later tasks have a tested foundation and the UI code stays declarative.

**Files:**
- Create: `Spud/Utils/AdaptiveLayout.swift`
- Test: `SpudTests/AdaptiveLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum AdaptiveLayout` with:
    - `static func cappedContentWidth(available: CGFloat, max: CGFloat) -> CGFloat` → `min(available, max)`
    - `static func bannerDownsampleWidth(screenWidth: CGFloat, cap: CGFloat = 600) -> CGFloat` → `min(screenWidth, cap)`
    - `static func modalPresentationStyle(for sizeClass: UIUserInterfaceSizeClass) -> UIModalPresentationStyle` → `.popover` for `.regular`, `.pageSheet` otherwise
  - Constants: `static let contentMaxWidth: CGFloat = 600`, `static let directoryMaxWidth: CGFloat = 700`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
import UIKit
@testable import Spud

struct AdaptiveLayoutTests {
    @Test func cappedContentWidth_capsWideCanvas() {
        #expect(AdaptiveLayout.cappedContentWidth(available: 1024, max: 600) == 600)
    }

    @Test func cappedContentWidth_passesThroughNarrow() {
        #expect(AdaptiveLayout.cappedContentWidth(available: 390, max: 600) == 390)
    }

    @Test func bannerDownsampleWidth_capsToDefault() {
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 1366) == 600)
        #expect(AdaptiveLayout.bannerDownsampleWidth(screenWidth: 390) == 390)
    }

    @Test func modalPresentationStyle_popoverOnRegular_sheetOnCompact() {
        #expect(AdaptiveLayout.modalPresentationStyle(for: .regular) == .popover)
        #expect(AdaptiveLayout.modalPresentationStyle(for: .compact) == .pageSheet)
        #expect(AdaptiveLayout.modalPresentationStyle(for: .unspecified) == .pageSheet)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/AdaptiveLayoutTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `Cannot find 'AdaptiveLayout' in scope`.

- [ ] **Step 3: Create the helper**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Pure size-class layout decisions shared by the iPad-adaptive surfaces, kept
/// free of view state so they can be unit-tested without a running view
/// hierarchy.
enum AdaptiveLayout {
    /// Default maximum readable content width for centered iPad layouts.
    static let contentMaxWidth: CGFloat = 600
    /// Maximum width for full-width directory/list content on a wide canvas.
    static let directoryMaxWidth: CGFloat = 700

    /// Clamps an available width to a maximum so content does not stretch
    /// full-bleed on a wide (iPad) canvas.
    static func cappedContentWidth(available: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(available, max)
    }

    /// The downsample target width for a wide banner image: the screen width,
    /// capped so an iPad does not fetch a needlessly huge bitmap.
    static func bannerDownsampleWidth(screenWidth: CGFloat, cap: CGFloat = contentMaxWidth) -> CGFloat {
        Swift.min(screenWidth, cap)
    }

    /// Modal presentation style for a row-anchored chooser: a popover in the
    /// regular size class (iPad), a draggable bottom sheet in compact (iPhone).
    static func modalPresentationStyle(for sizeClass: UIUserInterfaceSizeClass) -> UIModalPresentationStyle {
        sizeClass == .regular ? .popover : .pageSheet
    }
}
```

- [ ] **Step 4: Regenerate project and run test to verify it passes**

Run: `make project && xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/AdaptiveLayoutTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: `✔ Test run with 4 tests ... passed`.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Utils/AdaptiveLayout.swift SpudTests/AdaptiveLayoutTests.swift
git add Spud/Utils/AdaptiveLayout.swift SpudTests/AdaptiveLayoutTests.swift project.yml
git commit -m "feat: add AdaptiveLayout size-class helpers"
```

---

## Task 2 (A): Discover adaptive grid + directory width cap (#3, #8)

Make Discover use the wide canvas: horizontal rails become an adaptive grid in the regular size class; the "All communities" directory rows stop stretching full-bleed.

**Files:**
- Modify: `Spud/Scenes/Discover/DiscoverView.swift` (rails `rail`/`instanceRail`/`packsRail` ~`252-329`; card frames `530`, `590`; directory `LazyVStack` ~`83-96`, `372-402`)
- Test: `SpudSnapshotTests/IPadLayoutSnapshotTests.swift` (created here, extended later)

**Interfaces:**
- Consumes: `AdaptiveLayout.directoryMaxWidth` from Task 1.
- Produces: nothing other tasks consume.

- [ ] **Step 1: Add an iPad snapshot of Discover populated**

Create `SpudSnapshotTests/IPadLayoutSnapshotTests.swift`. Match the existing snapshot style (a `UIHostingController` for SwiftUI, `assertSnapshot(matching:as: .image(on: .iPadPro11(.landscape), traits:))`). Build the Discover view with the project's existing Discover snapshot fixture/view-model factory (mirror whatever `DiscoverView`'s existing snapshot test — if any — or a sibling SwiftUI snapshot test uses to construct it; reuse the fixture, do not invent a new data path).

```swift
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Spud

final class IPadLayoutSnapshotTests: XCTestCase {
    // Reuse the project's Discover fixture/view-model construction here
    // (see the existing Discover snapshot test or DiscoverView previews).
    func test_discover_populated_ipad_landscape() {
        let view = makeDiscoverFixtureView() // build via existing fixture
        let host = UIHostingController(rootView: AnyView(view))
        assertSnapshot(
            matching: host,
            as: .image(on: .iPadPro11(.landscape), traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light"
        )
    }
}
```

- [ ] **Step 2: Run to record the BEFORE ref (documents the gap)**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/IPadLayoutSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL "No reference … recorded" (records the current sparse layout).

- [ ] **Step 3: Make the rails adaptive in regular width**

In `DiscoverView`, add `@Environment(\.horizontalSizeClass) private var hSizeClass`. For each rail body (`packsRail`, `rail(...)`, `instanceRail`), branch: keep the current `ScrollView(.horizontal)` for `.compact`; in `.regular`, render the same cards in a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 12)], spacing: 12)` showing the full `rows`/`instances` (not just `prefix(railCarouselCount)`), still inside the rail's `VStack` with its `railHeader`. Example for `rail(...)`:

```swift
if hSizeClass == .regular {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 11)], spacing: 11) {
        ForEach(rows.prefix(DiscoverViewModel.railCarouselCount)) { row in
            DiscoverTrendCard(
                row: row,
                accent: accent,
                momentum: momentum,
                onTap: { viewModel.open(row) },
                subscriptionState: viewModel.subscriptionState(for: row),
                onSubscribe: { viewModel.toggleSubscription(row) },
                blurNsfw: viewModel.blurNsfw
            )
        }
    }
    .padding(.horizontal, 16)
} else {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 11) { /* existing card ForEach unchanged */ }
        .padding(.horizontal, 16)
    }
}
```

The cards keep `.frame(width: 178, ...)`; `.adaptive(minimum: 178)` lets the grid pack as many per row as fit. Apply the equivalent branch to `packsRail` (using `PackCard`) and `instanceRail` (using `InstanceCard`).

- [ ] **Step 4: Cap the directory column width**

Wrap the directory `LazyVStack` (the "All communities" list, ~`372-402`) so it is centered and capped in regular width:

```swift
LazyVStack(spacing: 0) { /* existing rows */ }
    .frame(maxWidth: hSizeClass == .regular ? AdaptiveLayout.directoryMaxWidth : .infinity)
    .frame(maxWidth: .infinity) // center within the wide canvas
```

If `directoryHeader` sits above the same column, give it the same cap so header and rows align.

- [ ] **Step 5: Re-record and verify**

Run the Step 2 command twice (first re-records the now-adaptive layout, second verifies). Confirm the recorded PNG shows multi-column rails and a centered, capped directory.

- [ ] **Step 6: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Discover/DiscoverView.swift SpudSnapshotTests/IPadLayoutSnapshotTests.swift
git add Spud/Scenes/Discover/DiscoverView.swift SpudSnapshotTests/IPadLayoutSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/IPadLayoutSnapshotTests/test_discover_populated_ipad_landscape.light.png
git commit -m "feat: adaptive Discover grid + directory width cap on iPad"
```

---

## Task 3 (A): Profile banner width + downsample caps (#4, #7)

Stop the Edit-Profile / Account banner from rendering as a full-width filmstrip and over-fetching its downsample on iPad.

**Files:**
- Modify: `Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift` (body `~75-87`; `loadBanner()` `~287-299`)
- Modify: `Spud/Scenes/Account/AccountView.swift` (banner row `~28-35`)
- Test: `SpudSnapshotTests/IPadLayoutSnapshotTests.swift`

**Interfaces:**
- Consumes: `AdaptiveLayout.contentMaxWidth`, `AdaptiveLayout.bannerDownsampleWidth(screenWidth:)` from Task 1.

- [ ] **Step 1: Add an iPad snapshot of the Account banner header**

Add to `IPadLayoutSnapshotTests`, reusing `ProfileBannerSnapshotTests`'s `makeBannerView` fixture pattern (placeholder URLs render deterministically):

```swift
func test_profileBanner_ipad_landscape_light() {
    let view = makeProfileBannerFixture() // mirror ProfileBannerSnapshotTests.makeBannerView(withImages:)
    let host = UIHostingController(rootView: AnyView(view))
    host.view.frame = CGRect(origin: .zero, size: ViewImageConfig.iPadPro11(.landscape).size ?? .zero)
    host.view.layoutIfNeeded()
    assertSnapshot(
        matching: host,
        as: .image(on: .iPadPro11(.landscape), traits: UITraitCollection(userInterfaceStyle: .light)),
        named: "light"
    )
}
```

- [ ] **Step 2: Run to record the BEFORE ref**

Run the IPadLayoutSnapshotTests command (Task 2 Step 2). Expected: FAIL "No reference" (records the full-bleed banner).

- [ ] **Step 3: Cap the rendered banner width (regular only)**

In `AccountView.swift`, the banner row uses `.listRowInsets(EdgeInsets())` to bleed full-width. Add `@Environment(\.horizontalSizeClass) private var hSizeClass` and center+cap in regular:

```swift
profileHeader
    .frame(maxWidth: hSizeClass == .regular ? AdaptiveLayout.contentMaxWidth : .infinity)
    .frame(maxWidth: .infinity, alignment: .center)
    .listRowInsets(EdgeInsets())
```

(Keep `.listRowInsets(EdgeInsets())` so compact stays full-bleed; the inner `maxWidth` cap only engages in regular.)

- [ ] **Step 4: Cap the downsample width**

In `ProfileBannerHeaderView.loadBanner()`, replace the raw screen width with the capped helper:

```swift
let target = CGSize(width: AdaptiveLayout.bannerDownsampleWidth(screenWidth: UIScreen.main.bounds.width) * 3, height: 300)
```

(Keep the `* 3` retina factor; only the base width is capped.)

- [ ] **Step 5: Re-record and verify**

Run the IPadLayoutSnapshotTests command twice. Confirm the banner is centered within a ~600pt column, not full-bleed.

- [ ] **Step 6: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift Spud/Scenes/Account/AccountView.swift SpudSnapshotTests/IPadLayoutSnapshotTests.swift
git add Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift Spud/Scenes/Account/AccountView.swift \
        SpudSnapshotTests/IPadLayoutSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/IPadLayoutSnapshotTests/test_profileBanner_ipad_landscape_light.light.png
git commit -m "feat: cap profile banner width + downsample on iPad"
```

> Note for reviewer: `PersonHeaderView` loads its banner externally (no inline `UIScreen.main` downsample), so #7 does not apply there. If `PersonHeaderView`'s banner is full-bleed on iPad, apply the same `contentMaxWidth` display cap; otherwise leave it.

---

## Task 4 (A): Composer / NewPost sheet detents on iPad (#6)

Set `modalPresentationStyle = .pageSheet` before configuring detents so they apply on iPad (today the default `.formSheet` makes `sheetPresentationController` nil and the detents silently drop). `AccountListViewController` already proves this exact pattern.

**Files:**
- Modify: `Spud/Scenes/Composer/ComposerViewController.swift` (`~250-254`)
- Modify: `Spud/Scenes/Composer/NewPostViewController.swift` (`~582-587`, `~620-624`)
- Test: `SpudTests/AdaptiveLayoutTests.swift` (assert the factory output)

**Interfaces:**
- Consumes: nothing new.

- [ ] **Step 1: Write a failing test on the factory's presentation style**

Add to `AdaptiveLayoutTests` (or a focused `ComposerPresentationTests`). Use whichever `NewPostViewController` factory builds the sheet (`makeSheet(...)`); construct it with an in-memory `AppDatabase` + fake dependencies as other VC tests do, and assert:

```swift
@MainActor
@Test func newPostSheet_isPageSheet_soDetentsApplyOnIPad() throws {
    let nav = NewPostViewController.makeSheet(/* fixture args */)
    #expect(nav.modalPresentationStyle == .pageSheet)
    #expect(nav.sheetPresentationController != nil)
}
```

- [ ] **Step 2: Run to verify it fails**

Run the SpudTests command. Expected: FAIL — `modalPresentationStyle` is `.automatic`/`.formSheet`, `sheetPresentationController` nil under the default.

- [ ] **Step 3: Set the presentation style before the detent block**

In each factory path, immediately after `let navigationController = UINavigationController(rootViewController: ...)` and before `if let sheet = navigationController.sheetPresentationController {`:

```swift
navigationController.modalPresentationStyle = .pageSheet
if let sheet = navigationController.sheetPresentationController {
    sheet.detents = [.large()]      // or [.medium(), .large()] where present
    sheet.prefersGrabberVisible = true
}
```

Apply to: `ComposerViewController.swift:252` block and both `NewPostViewController.swift` blocks (`583`, `621`).

- [ ] **Step 4: Run to verify it passes**

Run the SpudTests command. Expected: PASS.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Composer/ComposerViewController.swift Spud/Scenes/Composer/NewPostViewController.swift SpudTests/AdaptiveLayoutTests.swift
git add Spud/Scenes/Composer/ComposerViewController.swift Spud/Scenes/Composer/NewPostViewController.swift SpudTests/AdaptiveLayoutTests.swift
git commit -m "fix: apply composer/new-post sheet detents on iPad"
```

---

## Task 5 (A): Account switcher popover on iPad (#5)

Present the account switcher as a popover anchored to the "Switch account" affordance on iPad; keep the draggable bottom sheet on iPhone.

> Reviewer context: `AccountListViewController.init` currently pins `.pageSheet` "on every device" with a comment whose real purpose was making detents apply on iPad. A popover does not use detents, so this supersedes that rationale; update the comment, don't leave it contradictory.

**Files:**
- Modify: `Spud/Scenes/Account/AccountList/AccountListViewController.swift` (`init` `~59-71`; `configureSheet` `~122-128`)
- Modify: `Spud/Scenes/Account/AccountViewController.swift` (`accountsTapped` `~267-273`)
- Test: covered by `AdaptiveLayout.modalPresentationStyle` unit test (Task 1) + the UITest (Task 9).

**Interfaces:**
- Consumes: `AdaptiveLayout.modalPresentationStyle(for:)` from Task 1.

- [ ] **Step 1: Make presentation size-class driven at the call site**

In `AccountViewController.accountsTapped`, set the style from the current trait collection and anchor the popover to the tapped control. `accountsTapped` is triggered from a control (bar button or row) — capture that source. Replace the body:

```swift
@objc
private func accountsTapped(_ sender: Any?) {
    Haptics.tap()
    let accountListViewController = AccountListViewController(dependencies: dependencies.nested)
    accountListViewController.modalPresentationStyle =
        AdaptiveLayout.modalPresentationStyle(for: traitCollection.horizontalSizeClass)
    if let popover = accountListViewController.popoverPresentationController {
        if let barButton = sender as? UIBarButtonItem {
            popover.sourceItem = barButton
        } else if let view = sender as? UIView {
            popover.sourceItem = view
        } else {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.minY + 44, width: 0, height: 0)
        }
    }
    present(accountListViewController, animated: true)
}
```

(If `accountsTapped` is currently parameterless, update its `#selector` registration to pass the sender, or capture the known source control directly.)

- [ ] **Step 2: Stop the VC from force-pinning `.pageSheet`**

In `AccountListViewController.init`, remove the unconditional `modalPresentationStyle = .pageSheet` (the call site now decides). Update the comment to explain the presenter chooses popover (regular) vs sheet (compact). Keep `configureSheet()` — it is a no-op when presented as a popover (`sheetPresentationController` is nil), so detents still apply when the call site chose `.pageSheet`.

- [ ] **Step 3: Build + run the existing account UITest in compact**

Run: `python3 .../build_and_test.py --scheme Spud`
Expected: builds clean; compact (iPhone) account switching unchanged (bottom sheet).

- [ ] **Step 4: Manually verify on an iPad sim (popover)**

Boot an iPad sim (by id), open Account → Switch account, confirm a popover anchored to the control (not a bottom sheet). Capture a screenshot for the PR.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Account/AccountList/AccountListViewController.swift Spud/Scenes/Account/AccountViewController.swift
git add Spud/Scenes/Account/AccountList/AccountListViewController.swift Spud/Scenes/Account/AccountViewController.swift
git commit -m "feat: account switcher as popover on iPad"
```

---

## Task 6 (B): Feed switcher popover on iPad (#1)

In regular width, picking a feed becomes a navbar-title popover instead of popping the always-visible primary column to the feed switcher.

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (title `~430-436`; trailing items `~412-426`; add size-class handling)
- Modify: `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` (`~60-94`)
- Test: `SpudUITests` (Task 9) + manual sim.

**Interfaces:**
- Consumes: `FeedSwitcherViewController` (existing, `Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift`) and its `onSelectFeedType` / `onBrowseAllCommunities` callbacks.
- Produces: `PostListViewController.feedSwitcherPopoverRequested` closure hook (set by `MainWindowSplitViewController`) — `var onPresentFeedSwitcher: ((_ anchor: UIView) -> Void)?`.

- [ ] **Step 1: Add a tappable title control + popover hook (regular only)**

In `PostListViewController`, add a `UIButton` (configured `.plain`, title = `viewModel.navigationTitle`, trailing `chevron.down` image, `.preferredSymbolConfiguration` small) stored as `private lazy var titleButton`. Add:

```swift
/// Set by the owning split controller to present the feed switcher as a popover
/// anchored to `anchor`. Only used in the regular size class.
var onPresentFeedSwitcher: ((_ anchor: UIView) -> Void)?

private func applyTitleControl() {
    if traitCollection.horizontalSizeClass == .regular {
        titleButton.setTitle(viewModel.navigationTitle, for: .normal)
        navigationItem.titleView = titleButton
        navigationItem.title = nil
    } else {
        navigationItem.titleView = nil
        navigationItem.title = viewModel.navigationTitle
    }
}

@objc private func titleTapped() {
    Haptics.tap()
    onPresentFeedSwitcher?(titleButton)
}
```

Call `applyTitleControl()` from `applyNavigationTitle()` and from `traitCollectionDidChange(_:)` (when `horizontalSizeClass` changed).

- [ ] **Step 2: Present the feed switcher as a popover from the split controller**

In `MainWindowSplitViewController`, wire `postListVC.onPresentFeedSwitcher`:

```swift
postListVC.onPresentFeedSwitcher = { [weak self, weak postListVC] anchor in
    guard let self, let postListVC else { return }
    let feedSwitcher = FeedSwitcherViewController(
        currentFeedType: { [weak postListVC] in postListVC?.currentFeedType },
        defaultSortType: { accountService.defaultSortType(forAccountKeychainId: accountKeychainId) }
    )
    feedSwitcher.onSelectFeedType = { [weak postListVC] feedType in
        postListVC?.showFeed(feedType)
        postListVC?.dismiss(animated: true)
    }
    feedSwitcher.onBrowseAllCommunities = { [weak self] in
        self?.tabBarController?.selectedIndex = 1
        postListVC.dismiss(animated: true)
    }
    feedSwitcher.modalPresentationStyle = .popover
    feedSwitcher.popoverPresentationController?.sourceView = anchor
    feedSwitcher.popoverPresentationController?.sourceRect = anchor.bounds
    postListVC.present(feedSwitcher, animated: true)
}
```

(Reuse the same callback bodies as the existing index-0 `feedSwitcher`. Extract a shared `makeFeedSwitcher(...)` helper if it reduces duplication — DRY.)

- [ ] **Step 3: Don't pop to the feed switcher in regular width**

Make the primary stack size-class-aware: in regular, the primary column root should be the PostList alone (no FeedSwitcher beneath it), so the system back-swipe never reveals the switcher in the persistent primary column. Keep the compact column's `[feedSwitcher, postListVC]` stack (the beneath-the-list backstack is the right iPhone idiom). Implement by setting the primary column's view controllers to `[postListVC]` and the compact column's to `[feedSwitcher, postListVC]` via the split's separate column setup, and reconcile on collapse/expand in the existing `UISplitViewControllerDelegate` (`MainWindow` is the delegate). Verify expand→collapse→expand keeps a single PostList instance (it is retained via `postListViewController`).

- [ ] **Step 4: Build**

Run: `python3 .../build_and_test.py --scheme Spud`
Expected: builds clean, 0 new warnings.

- [ ] **Step 5: Manual verify on iPad + iPhone**

iPad: tap the feed-name title → popover with the feed list; selecting a feed updates the list; the primary column never disappears. iPhone: unchanged (left-edge swipe reveals the switcher beneath).

- [ ] **Step 6: Format + commit**

```bash
mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/MainWindow/MainWindowSplitViewController.swift
git add Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/MainWindow/MainWindowSplitViewController.swift
git commit -m "feat: feed switcher as navbar popover on iPad"
```

---

## Task 7 (C): Communities reading split — spike + scaffold

**SPIKE FIRST (gates the rest of Tier C).** Validate the containment mechanic on an iPad sim before building behavior on it.

**Files:**
- Create: `Spud/Scenes/Community/CommunityReadingSplitViewController.swift`
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewController.swift` (`handle(item:)` `.community` branch `~149-160`)
- Test: scaffolding verified on sim + a snapshot in Task 9.

**Interfaces:**
- Produces:
  - `final class CommunityReadingSplitViewController: UISplitViewController` with
    `init(communityName: String, instance: InstanceActorId, accountKeychainId: String, dependencies: Dependencies)` where `Dependencies` = `CommunityOrLoadingViewController.Dependencies & PostDetailOrEmptyViewController.Dependencies`.
  - Exposes `var detailNavigationController: UINavigationController { get }` and `func showDetail(_ vc: UIViewController)` so the router (Task 8) can push a post into the secondary column.

- [ ] **Step 1: Spike — pick the containment mechanic**

On an iPad sim, prototype the smaller of the two candidates and keep whichever collapses cleanly (single navbar, no double bars) on compact:
1. A nested `UISplitViewController` whose `.primary` is a nav stack rooted at `CommunityOrLoadingViewController` (resolves to `CommunityViewController`), `.secondary` is `PostDetailOrEmptyViewController(accountKeychainId:dependencies:)` (empty state), `.compact` reuses the primary nav stack. Push this split onto the Communities tab's nav stack.
2. If the nested-pushed split shows double nav bars or breaks collapse, fall back to presenting it full-screen, or route community reading through the existing Posts split (the spec's Option-3 escape hatch) and FLAG for re-decision.

Record the chosen mechanic in a top-of-file comment.

- [ ] **Step 2: Implement `CommunityReadingSplitViewController`**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import UIKit

/// iPad reading context for a single community: the community screen (header +
/// feed) in the primary column, the selected post in the secondary. Collapses
/// to a single-column push stack in compact (iPhone), matching the pre-split
/// behavior. Containment mechanic: <chosen in Step 1>.
final class CommunityReadingSplitViewController: UISplitViewController {
    typealias Dependencies =
        CommunityOrLoadingViewController.Dependencies &
        PostDetailOrEmptyViewController.Dependencies

    private let primaryNav = UINavigationController()
    let detailNavigationController = UINavigationController()

    init(
        communityName: String,
        instance: InstanceActorId,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        super.init(style: .doubleColumn)

        let communityVC = CommunityOrLoadingViewController(
            communityName: communityName,
            instance: instance,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        primaryNav.setViewControllers([communityVC], animated: false)
        primaryNav.enableForwardNavigationGesture()

        let empty = PostDetailOrEmptyViewController(
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        detailNavigationController.setViewControllers([empty], animated: false)
        detailNavigationController.enableForwardNavigationGesture()

        setViewController(primaryNav, for: .primary)
        setViewController(detailNavigationController, for: .secondary)
        setViewController(primaryNav, for: .compact)

        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows a post in the secondary column (or pushes onto the primary stack
    /// when collapsed), mirroring `MainWindow.pushDetail`.
    func showDetail(_ viewController: UIViewController) {
        if isCollapsed {
            primaryNav.pushViewController(viewController, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: viewController)
            nav.enableForwardNavigationGesture()
            showDetailViewController(nav, sender: self)
        }
    }
}
```

- [ ] **Step 3: Open a community via the reading split on iPad**

In `SubscriptionsViewController.handle(item:)` `.community` branch, branch on size class — push the reading split in regular, keep the existing full-screen `CommunityOrLoadingViewController` push in compact (the latter still works and avoids a nested split inside a compact nav stack):

```swift
case let .community(row):
    if traitCollection.horizontalSizeClass == .regular {
        let split = CommunityReadingSplitViewController(
            communityName: row.name,
            instance: row.instanceActorId,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(split, animated: true)
    } else {
        let communityVC = CommunityOrLoadingViewController(
            communityName: row.name,
            instance: row.instanceActorId,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(communityVC, animated: true)
    }
```

- [ ] **Step 4: Regenerate, build, verify on sim**

Run: `make project && python3 .../build_and_test.py --scheme Spud`
Then on an iPad sim: Communities → tap a community → confirm 2-column (community feed + "No posts selected" placeholder). On an iPhone sim: confirm single-column push unchanged.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Scenes/Community/CommunityReadingSplitViewController.swift Spud/Scenes/Subscriptions/SubscriptionsViewController.swift
git add Spud/Scenes/Community/CommunityReadingSplitViewController.swift Spud/Scenes/Subscriptions/SubscriptionsViewController.swift project.yml
git commit -m "feat: Communities 2-column reading split scaffold on iPad"
```

---

## Task 8 (C): Generalize the detail router to any active split tab

`pushIntoCurrentContext` / `pushDetail` only know the Posts tab. Generalize so a post opened while a `CommunityReadingSplitViewController` is active lands in ITS secondary column, not the Posts tab.

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (`pushIntoCurrentContext` `~618-628`; `pushDetail` `~498-514`)
- Create: helper `Spud/Scenes/MainWindow/SplitTabResolver.swift` (pure, testable)
- Test: `SpudTests/SplitTabResolverTests.swift`

**Interfaces:**
- Consumes: `CommunityReadingSplitViewController.showDetail(_:)` from Task 7.
- Produces: `enum SplitTabResolver { static func activeSplit(for selected: UIViewController?, postsSplit: UISplitViewController) -> UISplitViewController? }`.

- [ ] **Step 1: Write the failing resolver test**

```swift
import Testing
import UIKit
@testable import Spud

@MainActor
struct SplitTabResolverTests {
    @Test func resolvesPostsSplitWhenSelected() {
        let posts = UISplitViewController(style: .doubleColumn)
        #expect(SplitTabResolver.activeSplit(for: posts, postsSplit: posts) === posts)
    }

    @Test func resolvesNestedSplitInsideNavStack() {
        let posts = UISplitViewController(style: .doubleColumn)
        let nested = UISplitViewController(style: .doubleColumn)
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.pushViewController(nested, animated: false)
        #expect(SplitTabResolver.activeSplit(for: nav, postsSplit: posts) === nested)
    }

    @Test func returnsNilForPlainNavStack() {
        let posts = UISplitViewController(style: .doubleColumn)
        let nav = UINavigationController(rootViewController: UIViewController())
        #expect(SplitTabResolver.activeSplit(for: nav, postsSplit: posts) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: SpudTests command with `-only-testing:SpudTests/SplitTabResolverTests`. Expected: FAIL — `Cannot find 'SplitTabResolver'`.

- [ ] **Step 3: Implement the resolver**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Finds the split view controller that should receive a detail push for the
/// currently selected tab: the Posts split when it is selected, or a nested
/// split (e.g. a community reading split) sitting on top of another tab's
/// navigation stack. Returns nil for a plain single-column tab.
enum SplitTabResolver {
    static func activeSplit(
        for selected: UIViewController?,
        postsSplit: UISplitViewController
    ) -> UISplitViewController? {
        if selected === postsSplit { return postsSplit }
        if let nav = selected as? UINavigationController,
           let nested = nav.viewControllers.last as? UISplitViewController {
            return nested
        }
        return nil
    }
}
```

- [ ] **Step 4: Route through the resolver**

In `MainWindow.pushIntoCurrentContext`:

```swift
private func pushIntoCurrentContext(_ viewController: UIViewController) {
    let selected = tabBarController.selectedViewController
    if let split = splitViewController,
       let active = SplitTabResolver.activeSplit(for: selected, postsSplit: split) {
        if active === split {
            pushDetail(viewController: viewController)
        } else if let community = active as? CommunityReadingSplitViewController {
            community.showDetail(viewController)
        } else {
            pushDetail(viewController: viewController)
        }
    } else if let navigationController = selected as? UINavigationController {
        navigationController.pushViewController(viewController, animated: true)
    } else {
        tabBarController.selectedIndex = 0
        pushDetail(viewController: viewController)
    }
}
```

- [ ] **Step 5: Regenerate + run resolver test + build**

Run: `make project && xcodebuild ... -only-testing:SpudTests/SplitTabResolverTests ... test` then `build_and_test.py --scheme Spud`.
Expected: tests PASS; build clean.

- [ ] **Step 6: Verify the full path on an iPad sim**

Communities → community → tap a post → it opens in the community split's SECONDARY column (not the Posts tab). Tap a user/community link inside → routes within the same context.

- [ ] **Step 7: Format + commit**

```bash
mint run swiftformat Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/MainWindow/SplitTabResolver.swift SpudTests/SplitTabResolverTests.swift
git add Spud/Scenes/MainWindow/MainWindow.swift Spud/Scenes/MainWindow/SplitTabResolver.swift SpudTests/SplitTabResolverTests.swift project.yml
git commit -m "feat: route detail pushes into any active split tab"
```

---

## Task 9 (C): Tests — Communities split snapshot + UITest

Snapshots render VCs in isolation and miss routing/column wiring (the navbar child-VC lesson), so add a UITest that walks the real iPad path.

**Files:**
- Modify: `SpudSnapshotTests/IPadLayoutSnapshotTests.swift`
- Create/modify: a `SpudUITests` case (e.g. `IPadSplitUITests.swift`)

**Interfaces:**
- Consumes: `CommunityReadingSplitViewController`, the SBT stub fixtures (reuse existing community fixtures; cross-check required fields against generated `Types.swift` — `visibility`, `banned_from_community`, `subscribers_local`).

- [ ] **Step 1: Snapshot the community reading split (empty + loaded detail)**

Add to `IPadLayoutSnapshotTests`: build a `CommunityReadingSplitViewController` with in-memory `AppDatabase` + fake deps (seed a community + a post so the feed renders), snapshot on `.iPadPro11(.landscape)` for both the empty-detail and post-selected states. Seed the DB then poll asynchronously until the feed renders (do NOT `RunLoop.main.run` busy-spin — it starves the GRDB observation; see `PendingPostSnapshotTests`).

- [ ] **Step 2: Record + verify the snapshot**

Run the IPadLayoutSnapshotTests command twice. `git add` only the new refs.

- [ ] **Step 3: Write the iPad split UITest**

```swift
func test_iPad_CommunitiesTab_opensTwoColumnReadingSplit() {
    // Launch on an iPad sim; stub the community + feed responses (reuse existing fixtures).
    // Communities tab -> tap a subscribed community.
    // Assert the community feed AND the "No posts selected" detail placeholder are both visible.
    // Tap a post in the feed.
    // Assert the post detail appears in the secondary column while the feed stays visible.
}
```

Reuse the existing SBT launch/stub helpers; match query-matcher rules (drop the leading `&`).

- [ ] **Step 4: Run the UITest on an iPad sim**

Run: `xcodebuild -project Spud.xcodeproj -scheme SpudUITests -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' test` (pin a real iPad sim; target by id if one is booted).
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudSnapshotTests/IPadLayoutSnapshotTests.swift SpudUITests/IPadSplitUITests.swift \
        SpudSnapshotTests/__Snapshots__/IPadLayoutSnapshotTests/test_communitySplit_*.png project.yml
git commit -m "test: iPad Communities reading split snapshot + UITest"
```

---

## Task 10 (Docs): Feature docs + README

**Files:**
- Create: `docs/features/ipad-layout.md`
- Modify: `docs/features/README.md` (capability table + by-area map)
- Modify: any adjacent doc describing the Communities tab / feed switcher / Discover to note iPad behavior.

**Interfaces:** none (docs).

- [ ] **Step 1: Write `docs/features/ipad-layout.md`**

Follow `docs/features/_TEMPLATE.md`: `Status: shipped` (set when merged), `Surfaces: ipad`. Document the rules (regular size class only; compact unchanged) and Given/When/Then scenarios: adaptive Discover grid, capped banners, composer detents, account popover, feed-switcher popover, and the Communities 2-column reading split (browse full-width → tap community → 2-column → tap post → detail column). No `.swift` links.

- [ ] **Step 2: Update the README capability table AND by-area map**

Add an "iPad layout" row to the capability table and a corresponding entry in the "Feature coverage by area" map. Reconcile the Communities / feed-switcher / Discover entries to note iPad behavior.

- [ ] **Step 3: Commit**

```bash
git add docs/features/ipad-layout.md docs/features/README.md docs/features/<adjacent>.md
git commit -m "docs: iPad layout feature doc + README"
```

---

## Final verification (broad review)

- [ ] Build clean (`build_and_test.py --scheme Spud`, 0 new warnings) + widget (`--scheme SpudWidgetExtension`).
- [ ] Full unit test plan green (`-testPlan Spud`).
- [ ] iPad snapshot suite records/verifies clean; `git status` shows only the refs you intended.
- [ ] iPhone regression pass: feed switcher (left-edge swipe), Communities single-column push, account bottom sheet, composer detents — all unchanged on a compact sim.
- [ ] iPad manual pass: Discover grid, capped banners, account popover, feed-switcher title popover, Communities reading split (community → post → detail column).
- [ ] SwiftFormat clean (`mint run swiftformat .` lint) BEFORE the final verify.
- [ ] Whole-branch review by a fresh Opus reviewer subagent.

## Self-review notes (spec coverage)

- #1 → Task 6. #2 → Tasks 7-9. #3 → Task 2. #4 → Task 3. #5 → Task 5. #6 → Task 4. #7 → Task 3. #8 → Task 2.
- Router generalization → Task 8. Empty detail state → Task 7. iPad snapshot configs + UITest → Task 9. Docs → Task 10.
- Containment-mechanic spike → Task 7 Step 1, with the Option-3 fallback documented.
