# Quick Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sliders button beside Compose in the post-list nav bar that opens a popover to customize the feed — density, thumbnail position, vote-button visibility, and sort — without leaving the feed.

**Architecture:** A new `UIBarButtonItem` presents a SwiftUI popover (`UIHostingController`) backed by a small `@Observable QuickSwitchViewModel`. The view model writes display prefs straight through `PreferencesService`; the post list already observes those streams and re-flows visible cells, so no new live-update wiring is needed. Sort reuses the controller's existing `sortTypeChanged(to:)` path. The sort grouping shared by the existing toolbar `UIMenu` and the new SwiftUI sort list is extracted into a `PostSortMenu` value to remove duplication.

**Tech Stack:** Swift 6, UIKit + SwiftUI (`UIHostingController`), Observation framework, GRDB-backed app (not touched here), XCTest. Spec: `docs/superpowers/specs/2026-06-18-quick-switch-design.md`.

## Global Constraints

- Repo root for all paths and commands: `/Users/denis/dev/info.ddenis/Spud/Spud`.
- Spud + SpudTests targets are Swift 6.0 language mode; iOS 18+ SDK.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `refactor:`, `test:`); small focused commits.
- `Spud.xcodeproj` is generated and gitignored — after creating/deleting files run `make project` (XcodeGen) before building.
- SwiftFormat is authoritative; run `mint run swiftformat <paths>` on changed files before staging.
- Build: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`. Raw `xcodebuild` needs `-skipPackagePluginValidation -skipMacroValidation`.
- Unit tests run on the `Spud` test plan; default simulator `iPhone 17 Pro` (or the booted sim).
- Staging: never `git add -A`; stage explicit paths. Use `git status -uall` to see untracked files. Never stage `.remember/remember.md`.
- LemmyKit is a pinned remote SPM package — no LemmyKit changes in this plan.

---

## Setup (before Task 1)

- [ ] **Create the feature branch** (the working branch is `main`; branch first)

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git checkout -b feat/quick-switch
git branch --show-current   # expect: feat/quick-switch
```

---

## Task 1: Shared sort grouping (`PostSortMenu`)

Extract the duplicated sort-type groups into one value, then point the existing toolbar menu at it. This is a pure-data unit (TDD) plus a no-behavior-change refactor of `PostListViewController`.

**Files:**
- Create: `Spud/Scenes/PostList/PostSortMenu.swift`
- Test: `SpudTests/PostSortMenuTests.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (`setupSortTypeMenu` ~590-603, `rebuildSortTypeMenu` ~620-629)

**Interfaces:**
- Produces: `enum PostSortMenu` with `static let actives/tops/comments: [Components.Schemas.SortType]` and `static var all: [Components.Schemas.SortType]` (`actives + tops + comments`). Consumed by Task 3 (sort list) and Task 4.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/PostSortMenuTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import XCTest
@testable import Spud

final class PostSortMenuTests: XCTestCase {
    func testActivesOrder() {
        XCTAssertEqual(
            PostSortMenu.actives,
            [.Active, .Hot, .New, .Old, .Controversial, .Scaled]
        )
    }

    func testTopsOrder() {
        XCTAssertEqual(
            PostSortMenu.tops,
            [
                .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
                .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
            ]
        )
    }

    func testCommentsOrder() {
        XCTAssertEqual(PostSortMenu.comments, [.MostComments, .NewComments])
    }

    func testAllConcatenatesGroupsInOrder() {
        XCTAssertEqual(
            PostSortMenu.all,
            PostSortMenu.actives + PostSortMenu.tops + PostSortMenu.comments
        )
        XCTAssertEqual(PostSortMenu.all.count, 18)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostSortMenuTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAILS to compile — "cannot find 'PostSortMenu' in scope".

- [ ] **Step 3: Create `PostSortMenu`**

Create `Spud/Scenes/PostList/PostSortMenu.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

/// The post-list sort options, grouped the way they appear in the sort menu.
/// The toolbar pull-down (`PostListViewController`) and the Quick Switch sort
/// picker share this single definition. Order within each group is the
/// display order.
enum PostSortMenu {
    static let actives: [Components.Schemas.SortType] = [
        .Active, .Hot, .New, .Old, .Controversial, .Scaled,
    ]

    static let tops: [Components.Schemas.SortType] = [
        .TopSixHour, .TopTwelveHour, .TopDay, .TopWeek, .TopMonth,
        .TopThreeMonths, .TopSixMonths, .TopNineMonths, .TopYear, .TopAll,
    ]

    static let comments: [Components.Schemas.SortType] = [
        .MostComments, .NewComments,
    ]

    /// All sorts in display order: actives, then Top, then comments.
    static var all: [Components.Schemas.SortType] {
        actives + tops + comments
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostSortMenuTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS (4 tests).

- [ ] **Step 5: Refactor the toolbar menu to use `PostSortMenu`**

In `Spud/Scenes/PostList/PostListViewController.swift`, in `setupSortTypeMenu()`, replace the three local arrays + the loop (the `let actives…`, `let tops…`, `let comments…`, and `for sortType in actives + tops + comments`) with:

```swift
        for sortType in PostSortMenu.all {
            _ = makeAction(for: sortType)
        }
```

In `rebuildSortTypeMenu(activeSortType:)`, delete the three local arrays and reference `PostSortMenu.actives` / `PostSortMenu.tops` / `PostSortMenu.comments` directly in the `children:` array:

```swift
        let sortTypeMenu = UIMenu(
            title: "",
            options: .singleSelection,
            children: [
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.actives.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "Top", options: .singleSelection, children: PostSortMenu.tops.compactMap { sortTypeMenuActionsBySortType[$0] }),
                UIMenu(title: "", options: .displayInline, children: PostSortMenu.comments.compactMap { sortTypeMenuActionsBySortType[$0] }),
            ]
        )
```

- [ ] **Step 6: Build + re-run the test (refactor is behavior-preserving)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostSortMenuTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build succeeds; tests PASS.

- [ ] **Step 7: Format + commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostList/PostSortMenu.swift SpudTests/PostSortMenuTests.swift Spud/Scenes/PostList/PostListViewController.swift
git add Spud/Scenes/PostList/PostSortMenu.swift SpudTests/PostSortMenuTests.swift Spud/Scenes/PostList/PostListViewController.swift
git commit -m "refactor(post-list): extract shared PostSortMenu sort grouping"
```

---

## Task 2: `QuickSwitchViewModel`

The popover's view model. Seeds the three display prefs from `PreferencesService`, writes changes back through it (each with a haptic), and routes sort selection to an injected callback.

**Files:**
- Create: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift`
- Test: `SpudTests/QuickSwitchViewModelTests.swift`

**Interfaces:**
- Consumes: `PreferencesServiceType` (existing), `PostDensity` / `ThumbnailPosition` (SpudUIKit), `Components.Schemas.SortType` (LemmyKit), `Haptics` (existing).
- Produces:
  - `@MainActor @Observable final class QuickSwitchViewModel`
  - `init(preferencesService: PreferencesServiceType, currentSort: Components.Schemas.SortType, onSelectSort: @escaping (Components.Schemas.SortType) -> Void)`
  - stored: `var postDensity: PostDensity`, `var thumbnailPosition: ThumbnailPosition`, `var showVoteButtons: Bool`, `var currentSort: Components.Schemas.SortType`
  - constant: `let allPostDensities: [PostDensity]`, `let allThumbnailPositions: [ThumbnailPosition]`
  - methods: `updatePostDensity(_:)`, `updateThumbnailPosition(_:)`, `updateShowVoteButtons(_:)`, `selectSort(_:)`
  - Consumed by Task 3 (views) and Task 4 (controller).

- [ ] **Step 1: Write the failing test**

Create `SpudTests/QuickSwitchViewModelTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import XCTest
@testable import Spud

@MainActor
final class QuickSwitchViewModelTests: XCTestCase {
    private func makeViewModel(
        preferences: PreferencesService,
        currentSort: Components.Schemas.SortType = .Hot,
        onSelectSort: @escaping (Components.Schemas.SortType) -> Void = { _ in }
    ) -> QuickSwitchViewModel {
        QuickSwitchViewModel(
            preferencesService: preferences,
            currentSort: currentSort,
            onSelectSort: onSelectSort
        )
    }

    func testSeedsFromPreferences() {
        let prefs = PreferencesService()
        prefs.postDensity = .compact
        prefs.thumbnailPosition = .right
        prefs.showVoteButtons = false

        let viewModel = makeViewModel(preferences: prefs, currentSort: .New)

        XCTAssertEqual(viewModel.postDensity, .compact)
        XCTAssertEqual(viewModel.thumbnailPosition, .right)
        XCTAssertEqual(viewModel.showVoteButtons, false)
        XCTAssertEqual(viewModel.currentSort, .New)
    }

    func testUpdatePostDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.postDensity = .comfortable
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostDensity(.compact)

        XCTAssertEqual(viewModel.postDensity, .compact)
        XCTAssertEqual(prefs.postDensity, .compact)
    }

    func testUpdateThumbnailPositionWritesThrough() {
        let prefs = PreferencesService()
        prefs.thumbnailPosition = .left
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateThumbnailPosition(.hidden)

        XCTAssertEqual(viewModel.thumbnailPosition, .hidden)
        XCTAssertEqual(prefs.thumbnailPosition, .hidden)
    }

    func testUpdateShowVoteButtonsWritesThrough() {
        let prefs = PreferencesService()
        prefs.showVoteButtons = true
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateShowVoteButtons(false)

        XCTAssertEqual(viewModel.showVoteButtons, false)
        XCTAssertEqual(prefs.showVoteButtons, false)
    }

    func testSelectSortInvokesCallbackAndUpdatesCurrent() {
        let prefs = PreferencesService()
        var selected: Components.Schemas.SortType?
        let viewModel = makeViewModel(
            preferences: prefs,
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )

        viewModel.selectSort(.New)

        XCTAssertEqual(selected, .New)
        XCTAssertEqual(viewModel.currentSort, .New)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/QuickSwitchViewModelTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAILS to compile — "cannot find 'QuickSwitchViewModel' in scope".

- [ ] **Step 3: Implement `QuickSwitchViewModel`**

Create `Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit

/// Backs the Quick Switch popover. Reads the current feed-display preferences
/// from ``PreferencesService`` and writes changes straight back through it, so
/// the live post list (which observes the same streams) re-flows immediately.
///
/// The popover is short-lived and the only writer while open, so — unlike
/// ``PreferencesViewModel`` — it does not mirror the preference streams; it
/// seeds once at init. Sort is per-feed, so it is not a preference: selection
/// is routed back to the controller via ``onSelectSort``.
@MainActor
@Observable
final class QuickSwitchViewModel {
    private let preferencesService: PreferencesServiceType
    private let onSelectSort: (Components.Schemas.SortType) -> Void

    let allPostDensities: [PostDensity] = PostDensity.allCases
    let allThumbnailPositions: [ThumbnailPosition] = ThumbnailPosition.allCases

    var postDensity: PostDensity
    var thumbnailPosition: ThumbnailPosition
    var showVoteButtons: Bool
    var currentSort: Components.Schemas.SortType

    init(
        preferencesService: PreferencesServiceType,
        currentSort: Components.Schemas.SortType,
        onSelectSort: @escaping (Components.Schemas.SortType) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onSelectSort = onSelectSort
        self.currentSort = currentSort
        postDensity = preferencesService.postDensity
        thumbnailPosition = preferencesService.thumbnailPosition
        showVoteButtons = preferencesService.showVoteButtons
    }

    func updatePostDensity(_ value: PostDensity) {
        postDensity = value
        preferencesService.postDensity = value
        Haptics.tap()
    }

    func updateThumbnailPosition(_ value: ThumbnailPosition) {
        thumbnailPosition = value
        preferencesService.thumbnailPosition = value
        Haptics.tap()
    }

    func updateShowVoteButtons(_ value: Bool) {
        showVoteButtons = value
        preferencesService.showVoteButtons = value
        Haptics.tap()
    }

    func selectSort(_ value: Components.Schemas.SortType) {
        currentSort = value
        onSelectSort(value)
        Haptics.tap()
    }
}
```

Note: if the build reports `Haptics` not found, add `import SpudUIKit` is already present; otherwise it is in the app target and needs no import. Do not add an unused import — if `Haptics` resolves without it, leave imports as written (SpudUIKit is required for `PostDensity`/`ThumbnailPosition` regardless).

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/QuickSwitchViewModelTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS (5 tests).

- [ ] **Step 5: Format + commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift SpudTests/QuickSwitchViewModelTests.swift
git add Spud/Scenes/PostList/QuickSwitch/QuickSwitchViewModel.swift SpudTests/QuickSwitchViewModelTests.swift
git commit -m "feat(post-list): add QuickSwitchViewModel for the feed quick-switch popover"
```

---

## Task 3: SwiftUI popover views + force-popover delegate

The popover UI. No unit tests (SwiftUI views); verified by compilation and a `#Preview`. Three files.

**Files:**
- Create: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift`
- Create: `Spud/Scenes/PostList/QuickSwitch/QuickSwitchSortView.swift`
- Create: `Spud/Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift`

**Interfaces:**
- Consumes: `QuickSwitchViewModel` (Task 2), `PostSortMenu` (Task 1), `Components.Schemas.SortType.itemForMenu` (existing extension), `PreferencesService` (for the preview).
- Produces: `struct QuickSwitchView: View` (init `QuickSwitchView(viewModel:)`), `struct QuickSwitchSortView: View`, `final class ForcePopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate`. Consumed by Task 4.

- [ ] **Step 1: Create `ForcePopoverDelegate`**

Create `Spud/Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Keeps an attached presentation a popover even in a compact (iPhone) size
/// class, instead of letting it adapt to a full-screen sheet. Retain an
/// instance for the lifetime of the presenting controller and assign it as the
/// popover presentation controller's delegate.
final class ForcePopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
```

- [ ] **Step 2: Create `QuickSwitchSortView`**

Create `Spud/Scenes/PostList/QuickSwitch/QuickSwitchSortView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SwiftUI

/// The sort picker pushed from the Quick Switch popover. Lists the same sort
/// groups as the toolbar sort menu (actives, Top, comments) via ``PostSortMenu``
/// and applies the selection immediately through the view model, then pops back.
struct QuickSwitchSortView: View {
    let viewModel: QuickSwitchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section { rows(for: PostSortMenu.actives) }
            Section("Top") { rows(for: PostSortMenu.tops) }
            Section { rows(for: PostSortMenu.comments) }
        }
        .navigationTitle("Sort")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rows(for sortTypes: [Components.Schemas.SortType]) -> some View {
        ForEach(sortTypes, id: \.self) { sortType in
            Button {
                viewModel.selectSort(sortType)
                dismiss()
            } label: {
                HStack {
                    let item = sortType.itemForMenu
                    if let symbol = item.imageSystemName {
                        Label(item.title, systemImage: symbol)
                    } else {
                        Text(item.title)
                    }
                    Spacer()
                    if sortType == viewModel.currentSort {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .tint(.primary)
        }
    }
}
```

- [ ] **Step 3: Create `QuickSwitchView`**

Create `Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import SwiftUI

/// The Quick Switch popover: in-feed controls for how the post list renders —
/// density, thumbnail position, and vote-button visibility — plus a Sort row
/// that pushes the full sort picker. Hosted from the post-list toolbar; writes
/// go straight through ``PreferencesService`` via the view model, so the feed
/// re-flows live.
struct QuickSwitchView: View {
    let viewModel: QuickSwitchViewModel

    private var postDensity: Binding<PostDensity> {
        .init { viewModel.postDensity } set: { viewModel.updatePostDensity($0) }
    }

    private var thumbnailPosition: Binding<ThumbnailPosition> {
        .init { viewModel.thumbnailPosition } set: { viewModel.updateThumbnailPosition($0) }
    }

    private var showVoteButtons: Binding<Bool> {
        .init { viewModel.showVoteButtons } set: { viewModel.updateShowVoteButtons($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Density") {
                    Picker("Density", selection: postDensity) {
                        ForEach(viewModel.allPostDensities) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Thumbnail") {
                    Picker("Thumbnail", selection: thumbnailPosition) {
                        ForEach(viewModel.allThumbnailPositions) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle(isOn: showVoteButtons) {
                        Label("Vote Buttons", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section {
                    NavigationLink {
                        QuickSwitchSortView(viewModel: viewModel)
                    } label: {
                        HStack {
                            Label("Sort", systemImage: "line.horizontal.3.decrease.circle")
                            Spacer()
                            Text(viewModel.currentSort.itemForMenu.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    QuickSwitchView(
        viewModel: QuickSwitchViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
    )
}
```

- [ ] **Step 4: Generate project + build**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds with no new errors. (If `Picker(...).pickerStyle(.segmented)` with a section header shows a redundant inline label, that is cosmetic and acceptable; do not change behavior.)

- [ ] **Step 5: Format + commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift Spud/Scenes/PostList/QuickSwitch/QuickSwitchSortView.swift Spud/Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift
git add Spud/Scenes/PostList/QuickSwitch/QuickSwitchView.swift Spud/Scenes/PostList/QuickSwitch/QuickSwitchSortView.swift Spud/Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift
git commit -m "feat(post-list): add Quick Switch popover views"
```

---

## Task 4: Wire Quick Switch into `PostListViewController`

Add the toolbar button, place it left of Compose on every feed, and present the popover. Verified by build + manual run.

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`

**Interfaces:**
- Consumes: `QuickSwitchView` / `QuickSwitchViewModel` (Tasks 2-3), `ForcePopoverDelegate` (Task 3), existing `preferencesService`, `viewModel.feed.feedType.sortType`, `sortTypeChanged(to:)`, `Haptics`.

- [ ] **Step 1: Add the SwiftUI import**

In `Spud/Scenes/PostList/PostListViewController.swift`, add `import SwiftUI` to the import block (after `import SpudUtilKit`, before `import UIKit`):

```swift
import SpudUtilKit
import SwiftUI
import UIKit
```

- [ ] **Step 2: Add the button property + retained delegate**

After the line `var sortTypeMenuActionsBySortType: [Components.Schemas.SortType: UIAction] = [:]` (~line 155), add:

```swift
    var quickSwitchBarButtonItem: UIBarButtonItem!

    /// Keeps the Quick Switch popover a popover (not a sheet) on iPhone. The
    /// popover holds this only weakly, so the controller retains it.
    private let forcePopoverDelegate = ForcePopoverDelegate()
```

- [ ] **Step 3: Build the button in `setup()` and present it**

In `setup()`, insert a call between `setupSortTypeMenu()` and `updateTrailingBarButtonItems()`:

```swift
        setupDataSource()
        setupSortTypeMenu()
        setupQuickSwitchButton()
        updateTrailingBarButtonItems()
```

Add the builder and the tap handler. Place them next to `setupSortTypeMenu` (after `sortTypeChanged(to:)`, ~line 648):

```swift
    private func setupQuickSwitchButton() {
        quickSwitchBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(quickSwitchTapped)
        )
    }

    @objc
    private func quickSwitchTapped() {
        Haptics.tap()
        let quickSwitchViewModel = QuickSwitchViewModel(
            preferencesService: preferencesService,
            currentSort: viewModel.feed.feedType.sortType,
            onSelectSort: { [weak self] sortType in
                self?.sortTypeChanged(to: sortType)
            }
        )
        let host = UIHostingController(rootView: QuickSwitchView(viewModel: quickSwitchViewModel))
        host.modalPresentationStyle = .popover
        host.sizingOptions = [.preferredContentSize]
        if let popover = host.popoverPresentationController {
            popover.sourceItem = quickSwitchBarButtonItem
            popover.delegate = forcePopoverDelegate
        }
        present(host, animated: true)
    }
```

- [ ] **Step 4: Place the button in the trailing items**

Replace the body of `updateTrailingBarButtonItems()` (~line 279-292) with:

```swift
    private func updateTrailingBarButtonItems() {
        guard case .frontpage = viewModel.feed.feedType else {
            navigationItem.rightBarButtonItems = [quickSwitchBarButtonItem, sortTypeBarButtonItem]
            return
        }
        let composeButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(composeTapped)
        )
        // First item is the right-most: compose stays outboard, Quick Switch
        // sits immediately to its left, then the sort menu.
        navigationItem.rightBarButtonItems = [composeButton, quickSwitchBarButtonItem, sortTypeBarButtonItem]
    }
```

- [ ] **Step 5: Generate project + build + run the full Spud test plan**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build succeeds; the existing test plan stays green (no regressions); `PostSortMenuTests` and `QuickSwitchViewModelTests` pass.

- [ ] **Step 6: Manual verification on a booted simulator**

Run the app. Confirm:
- A sliders button (`slider.horizontal.3`) appears in the nav bar, immediately left of Compose, on the frontpage feed.
- It also appears (left of the sort button) on a community feed and on the Saved feed (where Compose is absent).
- Tapping it shows a popover (an arrow popover on iPhone, not a full sheet).
- Changing Density / Thumbnail / Vote buttons re-flows the visible cells live behind the popover.
- The Sort row shows the current sort; tapping it pushes the sort list; selecting a sort applies immediately, updates the row, and the standalone sort button's checkmark matches.

- [ ] **Step 7: Format + commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "feat(post-list): add Quick Switch toolbar button and popover"
```

---

## Self-Review

**1. Spec coverage**
- Button (sliders icon, left of Compose, every feed) → Task 4 Steps 2-4. ✓
- Popover forced on iPhone → `ForcePopoverDelegate` (Task 3) + `delegate` wiring (Task 4 Step 3). ✓
- Density / Thumbnail / Vote controls writing through `PreferencesService` with haptics → Task 2 + `QuickSwitchView` (Task 3). ✓
- Live re-flow with no new wiring → relies on existing `startDisplayAndReadingObservations` (verified in spec); no code needed. ✓
- Sort row reusing existing sort path → `onSelectSort` → `sortTypeChanged(to:)` (Task 4 Step 3). ✓
- Shared sort grouping refactor → Task 1. ✓
- Out of scope (Immersive, accent in popover, text-size, set-as-default) → not implemented. ✓

**2. Placeholder scan** — no TBD/TODO/"handle edge cases"; every code step shows full code; every command has an expected result. ✓

**3. Type consistency** — `QuickSwitchViewModel` init signature, property names (`postDensity`, `thumbnailPosition`, `showVoteButtons`, `currentSort`), and methods (`updatePostDensity`, `updateThumbnailPosition`, `updateShowVoteButtons`, `selectSort`) are identical across Tasks 2, 3, 4. `PostSortMenu.actives/tops/comments/all` identical across Tasks 1, 3, 4. `ForcePopoverDelegate` and `quickSwitchBarButtonItem` names consistent in Tasks 3-4. ✓

## Risks / fallbacks

- **`PostSortMenu` location:** placed in the Spud target under `Scenes/PostList/`; reachable by both `PostListViewController` and the SwiftUI views (same target). If a future need arises to share it with another target, move to `SpudUIKit` — not needed now.
- **Segmented picker labels:** if the `.segmented` style reads poorly with a Section header, switching to the default (menu) `Picker` style is a safe one-line change with no behavior impact.
- **Test isolation:** `QuickSwitchViewModelTests` uses `PreferencesService()` (writes to standard `UserDefaults`), matching existing tests; each test sets the prefs it asserts on before constructing the view model, so order independence holds.
