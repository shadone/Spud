# Post Detail Comment Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the post-detail content screen, show a comment-shaped loading skeleton in the comments region while comments are fetched, and a "No comments yet" empty state when a post genuinely has none.

**Architecture:** A pure `CommentsBackground.decide(...)` function chooses skeleton / empty / hidden from three booleans. `PostDetailViewModel` gains an observable `isLoadingComments` flag toggled around its `fetchComments()` network call (pull-to-refresh bypasses this method, so it is excluded). `PostDetailViewController` renders the skeleton and empty views as `tableView.backgroundView` — occluded by the always-present opaque header cell, so they appear only in the comments region below it — driven by an `ObservationStream` task on the flag plus the existing comment-snapshot path. The skeleton's pulse + bar factory are shared with the feed's `FeedLoadingSkeletonView` via a small `SkeletonView` base class.

**Tech Stack:** Swift 6 / UIKit, GRDB observations, `@Observable` view models, `ObservationStream.values(of:)`, `swift-snapshot-testing`, XcodeGen, XCTest.

Spec: `docs/superpowers/specs/2026-06-22-post-detail-comment-loading-design.md`

## Global Constraints

- **Working directory: `/Users/denis/dev/info.ddenis/Spud/Spud-comment-loading`** (an isolated git worktree on branch `feat/post-detail-comment-loading`). Do ALL work here. Never `cd` into `/Users/denis/dev/info.ddenis/Spud/Spud` (the shared checkout, on `main`) or any path containing `/worktrees/` or `/.claude/` or `/.claire/`.
- Before any commit, verify `git branch --show-current` prints `feat/post-detail-comment-loading`.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`); small, focused commits.
- New source/test files require `make project` (XcodeGen) before they compile into the target — the `.xcodeproj` is generated and gitignored. Run it after creating any file.
- `.swiftformat` is authoritative. Inside a `Task { [weak self] ... guard let self else { return } ... }`, drop the `self.` prefix on subsequent property accesses (SwiftFormat `redundantSelf`). Run `mint run swiftformat <paths>` before staging.
- Spud target is Swift 6 language mode; the view controller and view model are `@MainActor`.
- Headless `xcodebuild` needs `-skipPackagePluginValidation -skipMacroValidation`.
- Unit tests run on the `Spud` test plan; snapshot tests on the `SpudSnapshots` test plan. New snapshot classes here pin `size:` + `displayScale: 2`, so they are device-independent (any booted sim).
- git-annex tracks all `SpudSnapshotTests/__Snapshots__/**`. Record/verify one class at a time; never `git annex restage` between the record and verify runs; after a green verify, `git add` the PNGs (the annex clean filter stores them); commit new refs before any branch switch. Existing snapshot PNGs may show as cosmetically "modified" (annex content-availability) — do NOT stage those; stage only the explicit new-class ref directory.
- `git status` here hides untracked files — use `git status -uall`. Stage explicit paths; never `git add -A`.

---

### Task 1: `CommentsBackground` pure decision

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Comment/CommentsBackgroundState.swift`
- Test: `SpudTests/CommentsBackgroundStateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum CommentsBackground: Equatable { case skeleton; case empty; case hidden }` and `static func decide(isLoadingComments: Bool, hasCompletedFetch: Bool, hasComments: Bool) -> CommentsBackground`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/CommentsBackgroundStateTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class CommentsBackgroundStateTests: XCTestCase {
    func testCommentsPresentIsAlwaysHidden() {
        for loading in [true, false] {
            for completed in [true, false] {
                XCTAssertEqual(
                    CommentsBackground.decide(
                        isLoadingComments: loading,
                        hasCompletedFetch: completed,
                        hasComments: true
                    ),
                    .hidden,
                    "loading=\(loading) completed=\(completed)"
                )
            }
        }
    }

    func testLoadingWithNoCommentsShowsSkeleton() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: false, hasComments: false),
            .skeleton
        )
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: true, hasCompletedFetch: true, hasComments: false),
            .skeleton
        )
    }

    func testSettledWithNoCommentsShowsEmpty() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: true, hasComments: false),
            .empty
        )
    }

    func testInitialBeforeFetchShowsSkeleton() {
        XCTAssertEqual(
            CommentsBackground.decide(isLoadingComments: false, hasCompletedFetch: false, hasComments: false),
            .skeleton
        )
    }
}
```

- [ ] **Step 2: Regenerate the project and run the test to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/CommentsBackgroundStateTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — `cannot find 'CommentsBackground' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/PostDetail/Content/Comment/CommentsBackgroundState.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which placeholder, if any, the post-detail comments region shows behind the
/// always-present (opaque) post-header cell.
enum CommentsBackground: Equatable {
    /// A fetch is in flight, or the screen has just opened and no fetch has
    /// completed yet — and there are no comments on screen.
    case skeleton
    /// A comment fetch has completed and the post genuinely has no comments.
    case empty
    /// Comments are present; no background placeholder.
    case hidden

    /// Decides the comments-region background.
    ///
    /// The empty state is gated on `hasCompletedFetch` (not on "a snapshot has
    /// arrived"): a fresh open emits an empty *cached* snapshot before the
    /// network fetch starts, so gating on the snapshot would briefly flash the
    /// empty state before the skeleton. Defaulting to `.skeleton` until a fetch
    /// has actually completed avoids that flash.
    static func decide(
        isLoadingComments: Bool,
        hasCompletedFetch: Bool,
        hasComments: Bool
    ) -> CommentsBackground {
        if hasComments {
            return .hidden
        }
        if isLoadingComments {
            return .skeleton
        }
        if hasCompletedFetch {
            return .empty
        }
        return .skeleton
    }
}
```

- [ ] **Step 4: Regenerate and run the test to verify it passes**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/CommentsBackgroundStateTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (4 tests pass).

- [ ] **Step 5: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/CommentsBackgroundState.swift SpudTests/CommentsBackgroundStateTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/CommentsBackgroundState.swift SpudTests/CommentsBackgroundStateTests.swift
git commit -m "feat(post-detail): add CommentsBackground decision for comment loading state"
```

---

### Task 2: `isLoadingComments` flag on the view model

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift` (add property near line 40; update `fetchComments()` at lines 176-183)
- Test: `SpudTests/PostDetailViewModelLoadingTests.swift`

**Interfaces:**
- Consumes: existing `PostDetailViewModel(serverPostId:accountScope:dependencies:)` initializer.
- Produces: `PostDetailViewModel.isLoadingComments: Bool` (observable, `private(set)`), `true` while `fetchComments()` runs, `false` otherwise.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/PostDetailViewModelLoadingTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostDetailViewModelLoadingTests: XCTestCase {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType

        init() {
            let appDatabase = try! AppDatabase.inMemory()
            accountService = AccountService(appDatabase: appDatabase)
            alertService = AlertService()
            preferencesService = PreferencesService()
        }
    }

    private func makeViewModel() -> PostDetailViewModel {
        let dependencies = TestDependencies()
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies
        )
    }

    func testIsLoadingCommentsDefaultsFalse() {
        XCTAssertFalse(makeViewModel().isLoadingComments)
    }
}
```

- [ ] **Step 2: Regenerate and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailViewModelLoadingTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — `value of type 'PostDetailViewModel' has no member 'isLoadingComments'`.

- [ ] **Step 3: Add the property and toggle**

In `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`, add the property right after `var commentSortType: Components.Schemas.CommentSortType` (line 40):

```swift
    /// True while a (non-pull-refresh) comment fetch is in flight. Pull-to-refresh
    /// calls `LemmyService.fetchComments` directly and does not flip this.
    private(set) var isLoadingComments: Bool = false
```

Replace the existing `fetchComments()` (lines 176-183):

```swift
    func fetchComments() async {
        do {
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: commentSortType)
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
    }
```

with:

```swift
    func fetchComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: commentSortType)
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailViewModelLoadingTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelLoadingTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelLoadingTests.swift
git commit -m "feat(post-detail): track isLoadingComments while fetching comments"
```

---

### Task 3: Extract shared `SkeletonView` base

**Files:**
- Create: `Spud/Scenes/Common/SkeletonView.swift`
- Modify: `Spud/Scenes/PostList/FeedLoadingSkeletonView.swift`
- Test: existing `SpudSnapshotTests/LoadingStatesSnapshotTests.swift` (no new tests — the existing `FeedLoadingSkeletonView` snapshots must still pass unchanged, proving the refactor is behavior-preserving).

**Interfaces:**
- Consumes: nothing.
- Produces: `class SkeletonView: UIView` with instance `func startAnimating()`, `func stopAnimating()`, and `static func bar(height: CGFloat) -> UIView`. `FeedLoadingSkeletonView` becomes a subclass; its surface used by `PostListViewController` (`init(frame:)`, `startAnimating()`, `stopAnimating()`) is unchanged.

This is a behavior-preserving refactor, so there is no RED step; the gate is that the existing `FeedLoadingSkeletonView` snapshot references still match (no re-record).

- [ ] **Step 1: Create the shared base**

Create `Spud/Scenes/Common/SkeletonView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Base class for pulsing skeleton placeholder views. Provides the shared,
/// reduce-motion-aware opacity pulse and a neutral rounded "bar" factory used to
/// build skeleton rows. Subclasses lay out their own bars.
class SkeletonView: UIView {
    /// Starts the pulse, unless Reduce Motion is on (then the bars stay static).
    func startAnimating() {
        layer.removeAnimation(forKey: "pulse")
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    func stopAnimating() {
        layer.removeAnimation(forKey: "pulse")
    }

    /// A neutral rounded bar used as a skeleton element. Callers may override the
    /// returned view's `layer.cornerRadius` for non-default shapes (e.g. a round
    /// avatar dot).
    static func bar(height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiarySystemFill
        view.layer.cornerRadius = min(height / 2, 6)
        view.layer.cornerCurve = .continuous
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
```

- [ ] **Step 2: Refactor `FeedLoadingSkeletonView` onto the base**

In `Spud/Scenes/PostList/FeedLoadingSkeletonView.swift`, make exactly these changes (leave all layout code intact):

1. Change the declaration `final class FeedLoadingSkeletonView: UIView {` to `final class FeedLoadingSkeletonView: SkeletonView {`.
2. Delete its `startAnimating()` and `stopAnimating()` methods (and their doc comment) — now inherited from `SkeletonView`.
3. Delete its private `bar(height:)` method — now `SkeletonView.bar(height:)`.
4. In `makeRow()`, replace each `bar(height: N)` call with `Self.bar(height: N)` (the `thumbnail`, `line1`, `line2`, and `line3` bars — four call sites).

- [ ] **Step 3: Regenerate and build**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```

Expected: build succeeds.

- [ ] **Step 4: Run the existing skeleton snapshots to confirm no drift**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/LoadingStatesSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (all `loadingFooter` and `skeleton` cases still pass — the refactor changes no rendering, so no references are re-recorded). If any `skeleton` case reports a recorded/changed reference, the refactor changed rendering — revert and reconcile before continuing.

- [ ] **Step 5: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/Common/SkeletonView.swift Spud/Scenes/PostList/FeedLoadingSkeletonView.swift
git add Spud/Scenes/Common/SkeletonView.swift Spud/Scenes/PostList/FeedLoadingSkeletonView.swift
git commit -m "refactor(skeleton): extract shared SkeletonView base for pulse and bar"
```

---

### Task 4: `CommentLoadingSkeletonView`

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Comment/CommentLoadingSkeletonView.swift`
- Test: `SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift`

**Interfaces:**
- Consumes: `SkeletonView` (Task 3) — instance `startAnimating()`/`stopAnimating()` and `static func bar(height:)`.
- Produces: `final class CommentLoadingSkeletonView: SkeletonView` with `init(frame:)` (pulse and bar inherited from `SkeletonView`).

- [ ] **Step 1: Write the snapshot test**

Create `SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the post-detail comment loading states: the comment-shaped
/// skeleton placeholder and the "No comments yet" empty view, each in light and
/// dark. Both render at a fixed size and pinned display scale, so the references
/// are device-independent. The skeleton's pulse is an infinite layer animation,
/// so `stopAnimating()` is called (and `startAnimating()` never is) to pin a
/// static, full-opacity frame.
@MainActor
final class PostDetailCommentLoadingSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    func test_commentSkeleton_light() { assertSkeleton(style: .light) }
    func test_commentSkeleton_dark() { assertSkeleton(style: .dark) }

    private func assertSkeleton(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 500)
        let view = CommentLoadingSkeletonView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
        view.stopAnimating()
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }
}
```

- [ ] **Step 2: Regenerate and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — `cannot find 'CommentLoadingSkeletonView' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/PostDetail/Content/Comment/CommentLoadingSkeletonView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A loading placeholder for a post's comments: a column of comment-shaped
/// skeleton rows (a small avatar dot + a short name bar, then two text bars),
/// each indented per depth to read as a threaded tree. Shown as the table
/// background below the post header while comments load, so the comments region
/// never reads as blank. The pulse and bar factory come from `SkeletonView`.
final class CommentLoadingSkeletonView: SkeletonView {
    /// Indentation depth per skeleton row, to suggest a comment tree.
    private static let rowDepths: [Int] = [0, 0, 1, 2, 0, 1]
    private static let indentPerDepth: CGFloat = 22

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for depth in Self.rowDepths {
            stack.addArrangedSubview(makeRow(depth: depth))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeRow(depth: Int) -> UIView {
        let avatar = Self.bar(height: 24)
        avatar.layer.cornerRadius = 12
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 24)])

        let name = Self.bar(height: 12)
        let header = UIStackView(arrangedSubviews: [avatar, name])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let line1 = Self.bar(height: 12)
        let line2 = Self.bar(height: 12)

        let column = UIStackView(arrangedSubviews: [header, line1, line2])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 8

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(column)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator.withAlphaComponent(0.5)
        container.addSubview(separator)

        let leading = CGFloat(depth) * Self.indentPerDepth + 14

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: container.topAnchor, constant: 11),
            column.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -11),
            column.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            column.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            name.widthAnchor.constraint(equalToConstant: 90),
            line1.widthAnchor.constraint(equalTo: column.widthAnchor),
            line2.widthAnchor.constraint(equalTo: column.widthAnchor, multiplier: 0.6),

            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
```

- [ ] **Step 4: Record the snapshot references (first run)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST FAILURE — "No reference was found on disk. Automatically recorded snapshot" for both `light` and `dark`. Two PNGs are written under `SpudSnapshotTests/__Snapshots__/PostDetailCommentLoadingSnapshotTests/`.

- [ ] **Step 5: Verify the recorded references (second run)**

Do NOT run `git annex restage` between Step 4 and here.

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED. Inspect the two PNGs to confirm they read as indented comment rows:

```bash
find SpudSnapshotTests/__Snapshots__/PostDetailCommentLoadingSnapshotTests -name '*.png'
```

- [ ] **Step 6: Format and commit (refs first)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/CommentLoadingSkeletonView.swift SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/CommentLoadingSkeletonView.swift \
        SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentLoadingSnapshotTests
git commit -m "feat(post-detail): add CommentLoadingSkeletonView with snapshots"
```

---

### Task 5: `PostDetailEmptyCommentsView`

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Comment/PostDetailEmptyCommentsView.swift`
- Test: `SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift` (append cases)

**Interfaces:**
- Consumes: nothing.
- Produces: `final class PostDetailEmptyCommentsView: UIView` with `init(frame:)`.

- [ ] **Step 1: Add the failing snapshot cases**

In `SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift`, add these methods after `test_commentSkeleton_dark()`:

```swift
    func test_emptyComments_light() { assertEmpty(style: .light) }
    func test_emptyComments_dark() { assertEmpty(style: .dark) }

    private func assertEmpty(
        style: UIUserInterfaceStyle,
        testName: String = #function,
        line: UInt = #line
    ) {
        let size = CGSize(width: width, height: 320)
        let view = PostDetailEmptyCommentsView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .systemBackground
        view.layoutIfNeeded()

        assertSnapshot(
            matching: view,
            as: .image(size: size, traits: traits(style)),
            named: style == .dark ? "dark" : "light",
            testName: testName,
            line: line
        )
    }
```

- [ ] **Step 2: Regenerate and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — `cannot find 'PostDetailEmptyCommentsView' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/PostDetail/Content/Comment/PostDetailEmptyCommentsView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The "No comments yet" placeholder shown in a post's comments region once a
/// comment fetch settles with no comments. A plain view used as the table
/// background, so it sits below the post header rather than overlaying it the way
/// `UIContentUnavailableConfiguration` would.
final class PostDetailEmptyCommentsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        let titleText = NSLocalizedString(
            "No comments yet",
            comment: "Empty-state title for a post with no comments"
        )
        let subtitleText = NSLocalizedString(
            "Be the first to comment.",
            comment: "Empty-state subtitle for a post with no comments"
        )

        let icon = UIImageView(image: UIImage(systemName: "text.bubble"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)

        let title = UILabel()
        title.text = titleText
        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = .secondaryLabel
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = subtitleText
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .tertiaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(12, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(titleText). \(subtitleText)"
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 4: Record the new references (first run)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST FAILURE — "No reference was found on disk. Automatically recorded snapshot" for the two new `emptyComments` cases (the skeleton cases still pass). Two new PNGs written.

- [ ] **Step 5: Verify (second run)**

Do NOT `git annex restage` between Step 4 and here.

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (all 4 cases).

- [ ] **Step 6: Format and commit (refs first)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailEmptyCommentsView.swift SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailEmptyCommentsView.swift \
        SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentLoadingSnapshotTests
git commit -m "feat(post-detail): add PostDetailEmptyCommentsView with snapshots"
```

---

### Task 6: Wire the background into `PostDetailViewController`

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`

**Interfaces:**
- Consumes: `CommentsBackground.decide(...)` (Task 1), `PostDetailViewModel.isLoadingComments` (Task 2), `CommentLoadingSkeletonView` (Task 4), `PostDetailEmptyCommentsView` (Task 5), `ObservationStream.values(of:)`.
- Produces: no new public surface; drives `tableView.backgroundView`.

This task has no automated test — its logic is the already-tested pure decision function; the wiring is verified by a clean build plus on-device checks (Step 8). Make every edit, then build, then verify.

- [ ] **Step 1: Add instance state**

In `PostDetailViewController`, in the `// MARK: - Private` block (after line 149, near the other `*Task` properties), add:

```swift
    /// True once the comment GRDB observation has emitted at least once; gates
    /// the single `didPrepareObservation` call.
    private var hasReceivedFirstCommentSnapshot = false
    /// True once a comment fetch has completed (its loading flag went
    /// true -> false); gates the "No comments yet" empty state.
    private var hasCompletedCommentFetch = false
    private var loadingObservationTask: Task<Void, Never>?

    private lazy var commentLoadingSkeletonView = CommentLoadingSkeletonView()
    private lazy var emptyCommentsView = PostDetailEmptyCommentsView()
```

- [ ] **Step 2: Cancel the new task in `deinit` and `setPost`**

In `deinit` (lines 188-192), add the cancel:

```swift
    deinit {
        observationTask?.cancel()
        commentObservationTask?.cancel()
        swipeActionsObservationTask?.cancel()
        loadingObservationTask?.cancel()
    }
```

In `setPost(serverPostId:accountKeychainId:)` (lines 73-84), add the cancel beside the others:

```swift
    func setPost(serverPostId: Components.Schemas.PostID, accountKeychainId: String) {
        observationTask?.cancel()
        commentObservationTask?.cancel()
        loadingObservationTask?.cancel()

        viewModel = PostDetailViewModel(
            serverPostId: serverPostId,
            accountScope: dependencies.own.accountService.scope(forAccountKeychainId: accountKeychainId),
            dependencies: dependencies.own
        )

        startObservations()
    }
```

- [ ] **Step 3: Reset flags and start the loading observation in `startObservations()`**

At the very top of `startObservations()` (currently begins with `refreshModerationCapability()`), insert:

```swift
    private func startObservations() {
        hasReceivedFirstCommentSnapshot = false
        hasCompletedCommentFetch = false
        startLoadingObservation()
        updateCommentsBackground()

        refreshModerationCapability()
```

(Leave the rest of `startObservations()` unchanged.)

- [ ] **Step 4: Use the instance flag in `startCommentObservation`**

In `startCommentObservation(postRowId:)`, remove the local `var hasReceivedFirstSnapshot = false` and use the instance property. The loop body becomes:

```swift
        commentObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await rows in appDatabase.observePostDetailComments(
                postRowId: postRowId,
                sortType: sortTypeRaw
            ) {
                if Task.isCancelled { break }
                commentRowsByElementId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
                viewModel.updateOrderedComments(rows)

                await Self.prewarmCommentBodies(
                    rows,
                    textSizeAdjustment: appearanceService.postDetail.textSizeAdjustment
                )
                if Task.isCancelled { break }

                applySnapshot()
                if !hasReceivedFirstCommentSnapshot {
                    hasReceivedFirstCommentSnapshot = true
                    viewModel.didPrepareObservation(numberOfFetchedComments: rows.count)
                }
            }
        }
```

- [ ] **Step 5: Re-evaluate the background at the end of `applySnapshot`**

At the end of `applySnapshot(animated:)` (after the existing `updateJumpButtonVisibility()` call), add `updateCommentsBackground()`:

```swift
        dataSource.apply(snapshot, animatingDifferences: animate)
        updateJumpButtonVisibility()
        updateCommentsBackground()
    }
```

- [ ] **Step 6: Add `startLoadingObservation()` and `updateCommentsBackground()`**

Add both methods to the controller (e.g. immediately after `startCommentObservation(postRowId:)`):

```swift
    /// Observes the view model's comment-loading flag and refreshes the comments
    /// background on each change, recording the first fetch completion (the
    /// true -> false edge) so the empty state can show only once a fetch settles.
    private func startLoadingObservation() {
        loadingObservationTask?.cancel()
        loadingObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasLoading = false
            for await isLoading in ObservationStream.values(of: { [weak self] in
                self?.viewModel.isLoadingComments ?? false
            }) {
                if Task.isCancelled { break }
                if wasLoading, !isLoading {
                    hasCompletedCommentFetch = true
                }
                wasLoading = isLoading
                updateCommentsBackground()
            }
        }
    }

    /// Picks the comments-region background (skeleton / empty / none) and drives
    /// the skeleton pulse. The header cell is opaque, so the background view shows
    /// only in the blank region below it. Idempotent — safe to call freely.
    private func updateCommentsBackground() {
        switch CommentsBackground.decide(
            isLoadingComments: viewModel.isLoadingComments,
            hasCompletedFetch: hasCompletedCommentFetch,
            hasComments: !viewModel.orderedComments.isEmpty
        ) {
        case .skeleton:
            if tableView.backgroundView !== commentLoadingSkeletonView {
                tableView.backgroundView = commentLoadingSkeletonView
            }
            commentLoadingSkeletonView.startAnimating()
        case .empty:
            commentLoadingSkeletonView.stopAnimating()
            if tableView.backgroundView !== emptyCommentsView {
                tableView.backgroundView = emptyCommentsView
            }
        case .hidden:
            commentLoadingSkeletonView.stopAnimating()
            if tableView.backgroundView != nil {
                tableView.backgroundView = nil
            }
        }
    }
```

- [ ] **Step 7: Format and build**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```

Expected: build succeeds with no new warnings (the pre-existing benign `Duplicate -rpath` warning may remain).

- [ ] **Step 8: Manual on-sim verification**

Boot a single simulator (multiple booted sims flake UI runs). Run the app and check:

1. Open a post with no cached comments -> a pulsing comment skeleton shows below the header -> it is replaced by comments when they arrive.
2. Open a post that genuinely has zero comments -> skeleton -> "No comments yet" empty state (does not overlap the header).
3. Pull to refresh on a loaded post -> only the refresh control spins; no skeleton appears over the comments.
4. Re-open a post visited moments ago (cached comments) -> comments appear immediately; no skeleton flash, no "No comments yet" flash.
5. Settings -> enable Reduce Motion -> reopen a loading post -> the skeleton is static (no pulse).

- [ ] **Step 9: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat(post-detail): show comment skeleton and empty state while loading"
```

---

## Full regression pass (after Task 6)

Run the comment-related unit + snapshot tests together to confirm nothing regressed:

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-loading
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/CommentsBackgroundStateTests \
  -only-testing:SpudTests/PostDetailViewModelLoadingTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test

xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/LoadingStatesSnapshotTests \
  -only-testing:SpudSnapshotTests/PostDetailCommentLoadingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: all green.
