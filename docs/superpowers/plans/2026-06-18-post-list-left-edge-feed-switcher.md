# Post List Left-Edge Feed Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach the feed switcher (All / Local / Subscribed / Saved / Browse all communities) by swiping in from the left edge of the post list instead of tapping the navbar title.

**Architecture:** Pre-push the feed switcher beneath the post list in the Posts-tab navigation stack (`[feedSwitcher, postList]`), so the left-edge swipe is the **system interactive back gesture** — no custom gesture, no custom transition. The existing `ForwardNavigationGestureDriver` already keeps the system back gesture live (`viewControllers.count > 1`) and its `ForwardStackReducer` already makes the pop / re-push coherent. The modal "leading drawer" is removed entirely.

**Tech Stack:** UIKit, `UISplitViewController`, GRDB-backed view models, XcodeGen project generation, XCTest.

Spec: `docs/superpowers/specs/2026-06-18-post-list-left-edge-feed-switcher-design.md`

## Global Constraints

- Working directory for every command: `/Users/denis/dev/info.ddenis/Spud/Spud` (the Spud repo; the workspace root is not a git repo).
- After **adding, deleting, or renaming** any source file, run `make project` (XcodeGen) before building — the `.xcodeproj` is generated and gitignored.
- Build (auto-picks the booted simulator): `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
- Run the unit test target: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/ForwardStackReducerTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
- Format before staging: `mint run swiftformat <changed paths>` (the pre-commit hook lints only).
- Swift 6 language mode on the Spud target; **no emojis** in code/comments/commits; conventional commit subjects.
- **Reuse the same `PostListViewController` instance** when re-pushing — object identity is what lets `ForwardStackReducer` consume it cleanly and what preserves the feed observation. Never construct a second post list.
- Stage explicit paths only — never `git add -A`. Do not touch `.remember/remember.md`, and leave the unrelated pre-existing edits to `CLAUDE.md` and `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` unstaged.
- End every commit message body with these two trailers:

  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP
  ```

- Branch is already `feat/post-list-edge-feed-switcher` (verify with `git branch --show-current` before each commit; the checkout is shared with other agents).

---

## File Structure

- `Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift` — **new** (renamed from `QuickSwitchDrawerViewController.swift`). Full-screen pushed list; reads the active feed via a provider; fires selection callbacks without dismissing.
- `Spud/Scenes/MainWindow/QuickSwitch/QuickSwitchDrawerViewController.swift` — **deleted**.
- `Spud/Scenes/MainWindow/QuickSwitch/LeadingDrawerPresentation.swift` — **deleted** (modal presentation, now dead).
- `Spud/Scenes/PostList/PostListViewController.swift` — **modified**: remove the modal-drawer + chevron-title machinery, plain title, supplement the back button, expose `currentFeedType`.
- `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` — **modified**: build the switcher, pre-push `[feedSwitcher, postList]`, wire callbacks, retain the post list.
- `SpudTests/ForwardStackReducerTests.swift` — **modified**: add the pop-then-restore round-trip test.

---

### Task 1: Lock in the pop / re-push reducer invariant

The whole feature leans on `ForwardStackReducer` turning a pop-to-switcher followed by a re-push of the **same** post list instance into a clean (empty) forward stack. Encode that round trip as a regression test before building on it. It passes against the current reducer.

**Files:**
- Test: `SpudTests/ForwardStackReducerTests.swift`

**Interfaces:**
- Consumes: `ForwardStackReducer.reduce(forwardStack:lastStack:newStack:animated:)` (existing, generic over `AnyObject`).
- Produces: nothing consumed by later tasks (guard test only).

- [ ] **Step 1: Add the round-trip test**

Insert this method inside `final class ForwardStackReducerTests` (after `test_restorePush_consumesFirst`), where `a` stands for the feed switcher and `b` for the post list:

```swift
    func test_feedSwitcher_popThenRestorePush_roundTripsToEmpty() {
        // Start on [switcher(a), postList(b)] with nothing pending.
        // 1) Swipe back: postList is popped, becoming forward-restorable.
        let afterPop = ForwardStackReducer.reduce(
            forwardStack: [], lastStack: [a, b], newStack: [a], animated: true
        )
        XCTAssertEqual(afterPop, [b])

        // 2) Pick a feed (or forward-swipe): the SAME postList is re-pushed and
        //    consumed, leaving a clean forward stack.
        let afterRestore = ForwardStackReducer.reduce(
            forwardStack: afterPop, lastStack: [a], newStack: [a, b], animated: true
        )
        XCTAssertEqual(afterRestore, [])
    }
```

- [ ] **Step 2: Run the test, expect PASS**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/ForwardStackReducerTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: the `ForwardStackReducerTests` suite passes, including `test_feedSwitcher_popThenRestorePush_roundTripsToEmpty`.

- [ ] **Step 3: Format and commit**

```bash
mint run swiftformat SpudTests/ForwardStackReducerTests.swift
git add SpudTests/ForwardStackReducerTests.swift
git commit -m "test(navigation): cover feed-switcher pop/restore round trip

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

---

### Task 2: Pre-push the feed switcher and remove the modal drawer

The atomic core. The rename, the pre-push, the modal removal, and the dead-file deletion all break/fix the build together, so they ship as one task gated by a green build plus on-simulator verification. Reuse the same post list instance throughout.

**Files:**
- Create: `Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift`
- Delete: `Spud/Scenes/MainWindow/QuickSwitch/QuickSwitchDrawerViewController.swift`
- Delete: `Spud/Scenes/MainWindow/QuickSwitch/LeadingDrawerPresentation.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (lines ~157-164, ~294-360)
- Modify: `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift` (lines ~27-28, ~47-70)

**Interfaces:**
- Produces — `FeedSwitcherViewController`:
  - `init(currentFeedType: @escaping @MainActor () -> FeedType?, defaultSortType: @escaping @MainActor () -> Components.Schemas.SortType)` — the closures are `@MainActor` because they read main-actor state (`PostListViewController.currentFeedType`, `AccountServiceType.defaultSortType`) under Swift 6.
  - `var onSelectFeedType: ((FeedType) -> Void)?`
  - `var onBrowseAllCommunities: (() -> Void)?`
- Produces — `PostListViewController`:
  - `var currentFeedType: FeedType { get }`
  - existing `func showFeed(_ feedType: FeedType)` (unchanged) drives the in-place switch.
- Consumes: `AccountServiceType.defaultSortType(forAccountKeychainId:) -> Components.Schemas.SortType`; `FeedType.frontpage(listingType:sortType:)` / `.saved(sortType:)`; `Components.Schemas.ListingType` (`.All` / `.Local` / `.Subscribed`).

- [ ] **Step 1: Create `FeedSwitcherViewController.swift`**

Create `Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift` with exactly:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// The feed switcher. Lists the standard feeds (All / Local / Subscribed /
/// Saved) and a link into the Communities tab. It sits beneath the post list in
/// the Posts-tab navigation stack, so swiping in from the left edge (the system
/// back gesture) reveals it. Navigation only — no subscription management lives
/// here (that is the Communities tab's job), per the Scout navigation direction.
final class FeedSwitcherViewController: UIViewController {
    /// Invoked with the chosen feed type. The presenter switches the Posts feed
    /// and re-pushes the post list.
    var onSelectFeedType: ((FeedType) -> Void)?

    /// Invoked when the user taps "Browse all communities".
    var onBrowseAllCommunities: (() -> Void)?

    private enum FeedKind {
        case frontpage(Components.Schemas.ListingType)
        case saved
        case browseCommunities
    }

    private struct Row {
        let title: String
        let symbolName: String
        let kind: FeedKind
    }

    /// Reads the feed currently shown by the post list, so the matching row gets
    /// a checkmark. Evaluated each time the switcher appears (it is long-lived).
    private let currentFeedType: @MainActor () -> FeedType?

    /// Resolves the default sort applied to a freshly chosen feed. Evaluated at
    /// selection time so a changed preference is honoured.
    private let defaultSortType: @MainActor () -> Components.Schemas.SortType

    private let sections: [[Row]]

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = Theme.groupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return tableView
    }()

    init(
        currentFeedType: @escaping @MainActor () -> FeedType?,
        defaultSortType: @escaping @MainActor () -> Components.Schemas.SortType
    ) {
        self.currentFeedType = currentFeedType
        self.defaultSortType = defaultSortType
        sections = [
            [
                Row(
                    title: NSLocalizedString("All", comment: "Feed switcher: all federated content"),
                    symbolName: "globe",
                    kind: .frontpage(.All)
                ),
                Row(
                    title: NSLocalizedString("Local", comment: "Feed switcher: this instance only"),
                    symbolName: "house",
                    kind: .frontpage(.Local)
                ),
                Row(
                    title: NSLocalizedString("Subscribed", comment: "Feed switcher: subscribed communities"),
                    symbolName: "star",
                    kind: .frontpage(.Subscribed)
                ),
                Row(
                    title: NSLocalizedString("Saved", comment: "Feed switcher: saved posts"),
                    symbolName: "bookmark",
                    kind: .saved
                ),
            ],
            [
                Row(
                    title: NSLocalizedString("Browse all communities", comment: "Feed switcher row opening the Communities tab"),
                    symbolName: "person.3",
                    kind: .browseCommunities
                ),
            ],
        ]
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.groupedBackground

        title = NSLocalizedString("Feeds", comment: "Feed switcher screen title")
        navigationItem.largeTitleDisplayMode = .never

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The active feed may have changed since the switcher was last shown;
        // refresh so the checkmark lands on the current feed.
        tableView.reloadData()
    }

    /// Whether a feeds row matches the currently displayed feed (so it gets a
    /// checkmark). Compared by kind, ignoring sort.
    private func isActive(_ row: Row) -> Bool {
        guard let active = currentFeedType() else { return false }
        switch (row.kind, active) {
        case let (.frontpage(lhs), .frontpage(rhs, _)):
            return lhs == rhs
        case (.saved, .saved):
            return true
        default:
            return false
        }
    }
}

extension FeedSwitcherViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        sections.count
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? NSLocalizedString("Feeds", comment: "Feed switcher section header") : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = sections[indexPath.section][indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.image = UIImage(systemName: row.symbolName)
        content.imageProperties.tintColor = view.tintColor
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.secondaryGroupedBackground

        switch row.kind {
        case .browseCommunities:
            cell.accessoryType = .disclosureIndicator
        case .frontpage, .saved:
            cell.accessoryType = isActive(row) ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        Haptics.tap()

        let row = sections[indexPath.section][indexPath.row]
        switch row.kind {
        case let .frontpage(listingType):
            onSelectFeedType?(.frontpage(listingType: listingType, sortType: defaultSortType()))
        case .saved:
            onSelectFeedType?(.saved(sortType: defaultSortType()))
        case .browseCommunities:
            onBrowseAllCommunities?()
        }
    }
}
```

- [ ] **Step 2: Delete the old drawer and presentation files**

```bash
git rm Spud/Scenes/MainWindow/QuickSwitch/QuickSwitchDrawerViewController.swift
git rm Spud/Scenes/MainWindow/QuickSwitch/LeadingDrawerPresentation.swift
```

- [ ] **Step 3: Strip the drawer machinery from `PostListViewController` properties**

In `Spud/Scenes/PostList/PostListViewController.swift`, replace the property block (currently ~157-164):

```swift
    /// Whether this feed is the Posts-tab root, and so shows the tappable
    /// quick-switch title (chevron) that opens the read-only feed drawer.
    private let showsQuickSwitch: Bool

    /// Retained because UIKit holds the transitioning delegate weakly.
    private let drawerTransitioningDelegate = LeadingDrawerTransitioningDelegate()

    private lazy var quickSwitchTitleButton: UIButton = makeQuickSwitchTitleButton()
```

with:

```swift
    /// Whether this feed is the Posts-tab primary feed that sits atop the feed
    /// switcher in the navigation stack. When true the system back button
    /// ("Feeds") is kept visible alongside the leading compose button.
    private let showsQuickSwitch: Bool
```

- [ ] **Step 4: Replace the title / drawer methods in `PostListViewController`**

Replace the block from `// MARK: Quick-switch drawer` through the end of `quickSwitchTapped()` (currently ~294-360) with:

```swift
    // MARK: Feed title

    private func configureTitle() {
        applyNavigationTitle()
        if showsQuickSwitch {
            // The primary feed sits atop the feed switcher in the Posts-tab
            // stack. Keep the system back button ("Feeds") visible next to the
            // leading compose button instead of letting compose replace it.
            navigationItem.leftItemsSupplementBackButton = true
        }
    }

    private func applyNavigationTitle() {
        navigationItem.title = viewModel.navigationTitle
    }

    /// The feed currently displayed. The feed switcher reads this to mark the
    /// active row.
    var currentFeedType: FeedType {
        viewModel.feed.feedType
    }
```

Leave `switchFeed(to:)` and `showFeed(_:)` (the methods immediately after) unchanged.

- [ ] **Step 5: Add a retained post list property to `MainWindowSplitViewController`**

In `Spud/Scenes/MainWindow/MainWindowSplitViewController.swift`, after the two navigation-controller properties (~27-28), add:

```swift
    /// Retained so it survives being popped off the stack to reveal the feed
    /// switcher beneath it, and so the same instance is re-pushed — preserving
    /// the feed observation and letting the forward-stack reducer consume it.
    private var postListViewController: PostListViewController!
```

- [ ] **Step 6: Pre-push the switcher in `MainWindowSplitViewController.init`**

Replace the block that builds the post list and sets the primary/compact column (currently ~47-70, from `let feed = ...` through the two `enableForwardNavigationGesture()` calls) with:

```swift
        let accountService = self.accountService
        let feed = accountService.createDefaultFeed(forAccountKeychainId: accountKeychainId)

        let postListVC = PostListViewController(
            feed: feed,
            accountKeychainId: accountKeychainId,
            showsQuickSwitch: true,
            dependencies: self.dependencies.nested
        )
        postListViewController = postListVC

        // The feed switcher sits beneath the post list in the Posts-tab stack, so
        // the system left-edge back gesture reveals it (no custom gesture). The
        // post list is shown on top; swiping back pops to the switcher.
        let nav = postListNavigationController
        let feedSwitcher = FeedSwitcherViewController(
            currentFeedType: { [weak postListVC] in postListVC?.currentFeedType },
            defaultSortType: { accountService.defaultSortType(forAccountKeychainId: accountKeychainId) }
        )
        feedSwitcher.onSelectFeedType = { [weak postListVC, weak nav] feedType in
            guard let postListVC, let nav else { return }
            // Switch first so the list animates back in already showing the new feed.
            postListVC.showFeed(feedType)
            nav.pushViewController(postListVC, animated: true)
        }
        feedSwitcher.onBrowseAllCommunities = { [weak self, weak postListVC, weak nav] in
            guard let self else { return }
            // Restore the Posts tab to its feed before leaving, so returning to
            // the tab does not land on the bare switcher.
            if let postListVC, let nav, nav.topViewController !== postListVC {
                nav.pushViewController(postListVC, animated: false)
            }
            self.tabBarController?.selectedIndex = 1
        }
        postListNavigationController.setViewControllers([feedSwitcher, postListVC], animated: false)

        // Setup the post detail (the secondary part of split view controller)
        let postDetailVC = PostDetailOrEmptyViewController(
            accountKeychainId: accountKeychainId,
            dependencies: self.dependencies.nested
        )
        postDetailNavigationController.setViewControllers([postDetailVC], animated: false)

        setViewController(postListNavigationController, for: .primary)
        setViewController(postDetailNavigationController, for: .secondary)
        setViewController(postListNavigationController, for: .compact)

        // Right-edge forward gesture (restore a popped screen) on both columns' stacks.
        postListNavigationController.enableForwardNavigationGesture()
        postDetailNavigationController.enableForwardNavigationGesture()
```

(If the `postDetailVC` / `setViewController` / `enableForwardNavigationGesture` lines already follow verbatim, only replace up to and including the `setViewControllers([feedSwitcher, postListVC], ...)` line and leave the rest in place — do not duplicate them.)

- [ ] **Step 7: Regenerate the project**

Run: `make project`
Expected: XcodeGen regenerates `Spud.xcodeproj` with the new file present and the two deleted files gone, no error.

- [ ] **Step 8: Build**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds with no new errors (the pre-existing single benign `Duplicate -rpath` warning is acceptable). If the build reports an unresolved reference to `LeadingDrawer*`, `QuickSwitchDrawerViewController`, `quickSwitchTitleButton`, `makeQuickSwitchTitleButton`, `updateQuickSwitchTitle`, or `quickSwitchTapped`, find and remove that leftover reference.

- [ ] **Step 9: Verify on the simulator (iPhone)**

Boot one iPhone simulator (keep only one booted — multiple booted sims flake). Launch Spud and confirm:
- The post list shows on launch with its feed title; the leading bar shows the compose pencil **and** a "‹ Feeds" back button on a frontpage feed (All/Local/Subscribed); on the Saved feed the back button shows without compose.
- Swiping in from the left edge pops to the **Feeds** screen, with a checkmark on the current feed.
- Tapping a different feed returns to the post list showing that feed; swiping back again shows the checkmark moved to it.
- From the Feeds screen, swiping in from the **right** edge restores the current feed (forward gesture).
- Tapping a post opens the detail; from the detail, the left-edge swipe goes back to the post list (not the switcher).
- "Browse all communities" switches to the Communities tab; returning to the Posts tab shows the feed (not the bare switcher).

Capture a screenshot of the revealed Feeds screen for the review.

- [ ] **Step 10: Verify on the simulator (iPad)**

On an iPad simulator, confirm the switcher appears in the primary (sidebar) column on a left-edge swipe, feed selection updates the list, and the detail (secondary) column is unaffected by switching feeds.

- [ ] **Step 11: Format and commit**

```bash
mint run swiftformat \
  Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift \
  Spud/Scenes/PostList/PostListViewController.swift \
  Spud/Scenes/MainWindow/MainWindowSplitViewController.swift
git add Spud/Scenes/MainWindow/QuickSwitch/FeedSwitcherViewController.swift \
        Spud/Scenes/MainWindow/QuickSwitch/QuickSwitchDrawerViewController.swift \
        Spud/Scenes/MainWindow/QuickSwitch/LeadingDrawerPresentation.swift \
        Spud/Scenes/PostList/PostListViewController.swift \
        Spud/Scenes/MainWindow/MainWindowSplitViewController.swift
git commit -m "feat(post-list): reveal the feed switcher with a left-edge swipe

Pre-push the feed switcher beneath the post list in the Posts-tab stack so
the system back gesture reveals it; remove the modal leading-drawer presented
from the navbar title tap. Rename QuickSwitchDrawerViewController to
FeedSwitcherViewController and delete the now-dead LeadingDrawerPresentation.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

---

### Task 3 (optional): Snapshot the feed switcher screen

Add a deterministic snapshot of `FeedSwitcherViewController` as a pushed screen. Optional — manual verification in Task 2 is the primary gate, and snapshot refs use git-annex (record one class at a time; see `Spud/CLAUDE.md`).

**Files:**
- Test: `SpudSnapshotTests/FeedSwitcherSnapshotTests.swift` (new)

- [ ] **Step 1: Write the snapshot test**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SnapshotTesting
@testable import Spud
import XCTest

final class FeedSwitcherSnapshotTests: XCTestCase {
    func test_feedSwitcher_subscribedActive() {
        let sut = FeedSwitcherViewController(
            currentFeedType: { .frontpage(listingType: .Subscribed, sortType: .Active) },
            defaultSortType: { .Active }
        )
        assertSnapshot(of: sut, as: .image(on: .iPhone13Pro), named: "subscribed-active")
    }
}
```

- [ ] **Step 2: Record then verify**

Run (records missing refs on first pass, then re-run to verify):
`xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/FeedSwitcherSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 14 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: first run fails ("No reference"), second run passes. Do not `git annex restage` between record and verify (see `Spud/CLAUDE.md`).

- [ ] **Step 3: Commit**

```bash
git add SpudSnapshotTests/FeedSwitcherSnapshotTests.swift SpudSnapshotTests/__Snapshots__/FeedSwitcherSnapshotTests
git commit -m "test(post-list): snapshot the feed switcher screen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

---

## Notes for the implementer

- `Components.Schemas.ListingType` cases are capitalized (`.All`, `.Local`, `.Subscribed`); `Components.Schemas.SortType` likewise (e.g. `.Active`). These come from `import LemmyKit`.
- `Haptics.tap()` is available in the Spud app target (the old drawer used it).
- The title is kept up to date by the existing `titleObservationTask`, which calls `applyNavigationTitle()`; the simplified `applyNavigationTitle()` keeps that working.
- Do **not** add any `UIScreenEdgePanGestureRecognizer` — the left-edge gesture is the system back gesture, already enabled by `ForwardNavigationGestureDriver` because the stack depth is 2.
- If the build surfaces a reference to a removed symbol, it is a leftover call site to delete — there were no references to the drawer symbols outside `PostListViewController` and `LeadingDrawerPresentation.swift` at planning time.
