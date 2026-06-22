# Post Detail Comment Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a post-detail config button (`slider.horizontal.3`) opening a popover with per-post comment sort and a new comment-density preference, make the comment fetch unit-testable via an injectable seam, and upgrade it to cancel-and-replace so a sort change supersedes an in-flight fetch.

**Architecture:** Mirrors the post-list Quick Switch — a SwiftUI popover (`UIHostingController` + `ForcePopoverDelegate`) backed by an `@Observable` view model that writes display prefs through `PreferencesService` and routes sort via a callback. Comment density is a new `PreferencesService` pref surfaced on `PostDetailAppearanceType`, consumed by the comment cell through its existing body-view rebuild path; the VC re-flows it live by reconfiguring visible cells. The fetch becomes a tracked cancel-and-replace `Task` with an injected operation closure for testability.

**Tech Stack:** Swift 6 / UIKit + SwiftUI, GRDB observations, `@Observable` view models, `swift-snapshot-testing`, XcodeGen, XCTest.

Spec: `docs/superpowers/specs/2026-06-22-post-detail-comment-config-design.md`

## Global Constraints

- **Working directory: `/Users/denis/dev/info.ddenis/Spud/Spud-comment-config`** (isolated worktree on branch `feat/post-detail-comment-config`). Do ALL work here. Never `cd` into `/Users/denis/dev/info.ddenis/Spud/Spud` (shared checkout, on `main`) or any path containing `/worktrees/`, `/.claude/`, `/.claire/`.
- Before any commit, verify `git branch --show-current` prints `feat/post-detail-comment-config`.
- No emojis in code, comments, docs, or commit messages. Conventional commit subjects; small focused commits.
- New source/test files require `make project` (XcodeGen) before they compile.
- `.swiftformat` is authoritative; run `mint run swiftformat <paths>` before staging. Inside `Task { [weak self] ... guard let self else { return } ... }`, drop the `self.` prefix on subsequent property accesses.
- Swift 6 language mode; view controller, view models, and `PostDetailAppearance` are `@MainActor`.
- SourceKit "No such module" editor diagnostics are KNOWN FALSE POSITIVES here — trust the actual build/test, not editor squiggles.
- Headless `xcodebuild` needs `-skipPackagePluginValidation -skipMacroValidation`.
- **Simulator:** target the single already-booted simulator by id to avoid the multi-sim flake (device names are duplicated here). Find it with `xcrun simctl list devices | grep Booted` and use `-destination 'platform=iOS Simulator,id=<BOOTED_UDID>'` for `xcodebuild`. The `build_and_test.py` wrapper auto-targets the booted sim. Do NOT boot/create/shutdown simulators.
- New snapshot tests pin `size:` + `displayScale: 2` (device-independent). git-annex tracks `SpudSnapshotTests/__Snapshots__/**`: record/verify one class at a time, never `git annex restage` between record and verify, `git add` the new ref directory after a green verify, and do NOT run any other `git annex` command. Existing snapshot PNGs show as cosmetically "modified" — ignore them; never stage them.
- `git status` hides untracked files — use `git status -uall`. Stage explicit paths; never `git add -A`.

---

### Task 1: `commentDensity` preference + appearance forwarding

**Files:**
- Modify: `Spud/Services/Preferences/PreferencesService.swift`
- Modify: `Spud/Services/Appearance/PostDetail/PostDetailAppearance.swift`

**Interfaces:**
- Consumes: `PostDensity` (SpudUIKit; `.comfortable`/`.compact`), `@UserDefaultsBacked`.
- Produces: `PreferencesServiceType.commentDensity: PostDensity { get set }` + `commentDensityStream: AsyncStream<PostDensity>`; `PostDetailAppearanceType.commentDensity: PostDensity { get set }` + `commentDensityStream: AsyncStream<PostDensity>`.

This is a mechanical addition mirroring `postDensity`; verified by build (the codebase does not unit-test `@UserDefaultsBacked` prefs directly — they are exercised by Tasks 2/4).

- [ ] **Step 1: Add the preference (protocol + impl)**

In `Spud/Services/Preferences/PreferencesService.swift`, add to the protocol right after the `postDensityStream` getter (the `var postDensityStream: AsyncStream<PostDensity> { get }` line):

```swift
    /// Comment-thread density (comfortable / compact) for the post-detail
    /// screen. Independent of the feed's `postDensity`.
    var commentDensity: PostDensity { get set }
    var commentDensityStream: AsyncStream<PostDensity> { get }
```

In the same file, add to the concrete `PreferencesService` right after the `postDensityStream` computed property (the `var postDensityStream: AsyncStream<PostDensity> { $postDensity }` block):

```swift
    @UserDefaultsBacked(key: "commentDensity")
    var commentDensity: PostDensity = .comfortable

    var commentDensityStream: AsyncStream<PostDensity> {
        $commentDensity
    }
```

- [ ] **Step 2: Forward it through `PostDetailAppearance`**

In `Spud/Services/Appearance/PostDetail/PostDetailAppearance.swift`:

1. If the file does not already `import SpudUIKit`, add it (after `import SpudUtilKit`) — `PostDensity` lives there.
2. Add to the `PostDetailAppearanceType` protocol (after `var commentRibbonTheme: PostCommentRibbonTheme { get set }`):

```swift
    var commentDensity: PostDensity { get set }
    var commentDensityStream: AsyncStream<PostDensity> { get }
```

3. Add to the concrete `PostDetailAppearance` (after the `commentRibbonTheme` property):

```swift
    /// Forwards to the user's comment-density preference.
    var commentDensity: PostDensity {
        get { preferencesService.commentDensity }
        set { preferencesService.commentDensity = newValue }
    }

    var commentDensityStream: AsyncStream<PostDensity> {
        preferencesService.commentDensityStream
    }
```

- [ ] **Step 3: Regenerate and build**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```

Expected: build succeeds (0 errors).

- [ ] **Step 4: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
mint run swiftformat Spud/Services/Preferences/PreferencesService.swift Spud/Services/Appearance/PostDetail/PostDetailAppearance.swift
git add Spud/Services/Preferences/PreferencesService.swift Spud/Services/Appearance/PostDetail/PostDetailAppearance.swift
git commit -m "feat(post-detail): add commentDensity preference"
```

---

### Task 2: Comment cell + view-model density

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`
- Test: `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift`

**Interfaces:**
- Consumes: `PostDetailAppearanceType.commentDensity` (Task 1), `PostDensity`.
- Produces: `PostDetailCommentViewModel.commentDensity: PostDensity` (a `let`, captured at init from `appearance.postDetail.commentDensity`). The cell reads `viewModel.commentDensity` and rebuilds its body view when it changes — same path as `textSizeAdjustment`.

This is a behavior change to rendering, so the cell must honor density BEFORE the snapshot reference is recorded — otherwise a wrong (comfortable) reference gets locked in. Order: VM (Step 1) → cell (Step 2) → test + record (Steps 3-5).

- [ ] **Step 1: Carry density on the view model**

In `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`:

1. If the file does not already `import SpudUIKit`, add it (after `import SpudMarkdownKit`).
2. Next to the existing `let textSizeAdjustment: CGFloat` stored property, add:

```swift
    let commentDensity: PostDensity
```

3. In `init`, right after the existing two lines
   `let textSizeAdjustment = appearance.postDetail.textSizeAdjustment` /
   `self.textSizeAdjustment = textSizeAdjustment`, add:

```swift
        commentDensity = appearance.postDetail.commentDensity
```

- [ ] **Step 2: Pass density into the cell body view**

In `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`:

1. Change the lazy `bodyView` initializer:

```swift
    private(set) lazy var bodyView: MarkdownBodyView = makeBodyView(textScale: 0, density: .comfortable)
```

2. Add a density-tracking field next to `bodyViewTextScale`:

```swift
    /// Density baked into the current `bodyView`, compared on each configure
    /// alongside `bodyViewTextScale`.
    private var bodyViewDensity: PostDensity = .comfortable
```

3. Change `makeBodyView` to take a density:

```swift
    private func makeBodyView(textScale: CGFloat, density: PostDensity) -> MarkdownBodyView {
        let context = MarkdownContext(kind: .comment, textScale: textScale, density: density)
        let view = MarkdownBodyView(context: context)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityIdentifier = "body"
        view.delegate = self
        view.onContentSizeChange = { [weak self] in
            self?.onBodyImageLoaded?()
        }
        return view
    }
```

4. In `configure`, replace the text-scale rebuild block with one that also reacts to density:

```swift
            // Rebuild the body view when the text-scale or density preference
            // changes so fonts are correct; otherwise reuse the existing instance.
            let textScale = viewModel.textSizeAdjustment
            let density = viewModel.commentDensity
            if textScale != bodyViewTextScale || density != bodyViewDensity {
                let oldBodyView = bodyView
                let newBodyView = makeBodyView(textScale: textScale, density: density)
                if let idx = verticalStackView.arrangedSubviews.firstIndex(of: oldBodyView) {
                    verticalStackView.insertArrangedSubview(newBodyView, at: idx)
                    oldBodyView.removeFromSuperview()
                }
                bodyView = newBodyView
                bodyViewTextScale = textScale
                bodyViewDensity = density
            }
```

- [ ] **Step 3: Add the compact-density snapshot test**

In `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift`, change the `makeViewModel` helper to accept a density and apply it transiently (the VM captures it at init, so the global pref is restored immediately and no other snapshot is affected). Change the signature to add a parameter:

```swift
    private func makeViewModel(
        row: PostDetailCommentRow,
        postCreatorPersonId: Int64? = nil,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil,
        collapsedNewDescendantCount: Int? = nil,
        isNew: Bool = false,
        commentDensity: PostDensity = .comfortable
    ) -> PostDetailCommentViewModel {
        let preferences = PreferencesService()
        preferences.commentDensity = commentDensity
        let appearance = AppearanceService(preferencesService: preferences)
        let viewModel = PostDetailCommentViewModel(
            row: row,
            appearance: appearance,
            postCreatorPersonId: postCreatorPersonId,
            isCollapsed: isCollapsed,
            collapsedDescendantCount: collapsedDescendantCount,
            collapsedNewDescendantCount: collapsedNewDescendantCount,
            isNew: isNew
        )
        // The VM captured the density at init; restore the global default so no
        // other snapshot renders compact.
        preferences.commentDensity = .comfortable
        return viewModel
    }
```

Add `import SpudUIKit` to the test file if not present (for `PostDensity`). Then add the new test methods (near the other `test_` methods):

```swift
    func test_compactDensity() {
        assertComment(viewModel: makeViewModel(
            row: row(body: "A compact comment renders with tighter, smaller body text."),
            commentDensity: .compact
        ))
    }
```

- [ ] **Step 4: Record the snapshot references (first run)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests/test_compactDensity \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST FAILURE — "No reference was found on disk. Automatically recorded snapshot" for `test_compactDensity` (light + dark). Two PNGs written under `SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/`.

- [ ] **Step 5: Verify — new ref + no drift on existing comment snapshots**

Do NOT `git annex restage` between Step 5 and here. Run the whole class to confirm the new test passes AND the existing comment snapshots did not drift (default density `.comfortable` matches the previously-hardcoded value):

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (all existing cases + `test_compactDensity`, no references recorded this run).

- [ ] **Step 6: Format and commit (refs first)**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift SpudSnapshotTests/PostDetailCommentSnapshotTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift \
        Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift \
        SpudSnapshotTests/PostDetailCommentSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests
git commit -m "feat(post-detail): apply comment density to comment cells"
```

---

### Task 3: Cancel-and-replace fetch + testable seam

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Test: `SpudTests/PostDetailViewModelFetchTests.swift`

**Interfaces:**
- Consumes: existing `PostDetailViewModel` init (`serverPostId`, `accountScope`, `dependencies`).
- Produces: new init param `fetchCommentsOperation: (@MainActor (Components.Schemas.CommentSortType) async throws -> Void)? = nil` (defaults to the `accountScope.lemmyService.fetchComments` path); `commentSortType` becomes `private(set)`; new `func setCommentSortType(_:)`; `fetchComments()` is cancel-and-replace. The dead `didChangeCommentSortType` is removed.

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/PostDetailViewModelFetchTests.swift`:

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

/// Counts error-handling calls so the cancel-and-replace tests can assert a
/// superseded fetch does not surface an error.
private final class SpyAlertService: AlertServiceType, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [AlertHandlerRequest] = []
    var handledRequests: [AlertHandlerRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func handle(_ error: Error, for request: AlertHandlerRequest) {
        lock.lock(); _requests.append(request); lock.unlock()
    }

    func image(error: ImageLoadingError, for imageUrl: URL) {}
}

@MainActor
final class PostDetailViewModelFetchTests: XCTestCase {
    private struct TestDependencies:
        HasAccountService, HasAlertService, HasPreferencesService
    {
        let accountService: AccountServiceType
        let alertService: AlertServiceType
        let preferencesService: PreferencesServiceType

        init(alertService: AlertServiceType) {
            let appDatabase = try! AppDatabase.inMemory()
            accountService = AccountService(appDatabase: appDatabase)
            self.alertService = alertService
            preferencesService = PreferencesService()
        }
    }

    private func makeViewModel(
        alertService: AlertServiceType = AlertService(),
        fetchCommentsOperation: @escaping @MainActor (Components.Schemas.CommentSortType) async throws -> Void
    ) -> PostDetailViewModel {
        let dependencies = TestDependencies(alertService: alertService)
        return PostDetailViewModel(
            serverPostId: 1,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies,
            fetchCommentsOperation: fetchCommentsOperation
        )
    }

    func testLoadingFlagTrueWhileFetchingThenFalse() async {
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "operation started")
        let vm = makeViewModel { _ in
            started.fulfill()
            await withCheckedContinuation { release = $0 }
        }

        let task = Task { await vm.fetchComments() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(vm.isLoadingComments)

        release?.resume()
        await task.value
        XCTAssertFalse(vm.isLoadingComments)
    }

    func testCancelAndReplaceKeepsFlagAndSilencesSupersededFetch() async {
        var release1: CheckedContinuation<Void, Never>?
        var release2: CheckedContinuation<Void, Never>?
        let started1 = expectation(description: "op1 started")
        let started2 = expectation(description: "op2 started")
        var callCount = 0
        let alert = SpyAlertService()

        let vm = makeViewModel(alertService: alert) { _ in
            callCount += 1
            if callCount == 1 {
                started1.fulfill()
                try await withCheckedThrowingContinuation { release1 = $0 }
            } else {
                started2.fulfill()
                await withCheckedContinuation { release2 = $0 }
            }
        }

        let t1 = Task { await vm.fetchComments() }
        await fulfillment(of: [started1], timeout: 1)

        let t2 = Task { await vm.fetchComments() }   // supersedes t1
        await fulfillment(of: [started2], timeout: 1)
        XCTAssertTrue(vm.isLoadingComments)

        // Release t1 with a cancellation error; as the superseded fetch it must
        // not clear the flag or surface an error.
        release1?.resume(throwing: CancellationError())
        await t1.value
        XCTAssertTrue(vm.isLoadingComments)

        release2?.resume()
        await t2.value
        XCTAssertFalse(vm.isLoadingComments)
        XCTAssertTrue(alert.handledRequests.isEmpty)
    }

    func testGenuineErrorIsSurfacedAndClearsFlag() async {
        struct Boom: Error {}
        let alert = SpyAlertService()
        let vm = makeViewModel(alertService: alert) { _ in throw Boom() }

        await vm.fetchComments()

        XCTAssertFalse(vm.isLoadingComments)
        XCTAssertEqual(alert.handledRequests, [.fetchComments])
    }

    func testSetCommentSortTypeUpdatesValue() {
        let vm = makeViewModel { _ in }
        vm.setCommentSortType(.New)
        XCTAssertEqual(vm.commentSortType, .New)
    }
}
```

(`AlertHandlerRequest` must be `Equatable` for `XCTAssertEqual([.fetchComments])`. If it is not, change that assertion to `XCTAssertEqual(alert.handledRequests.count, 1)`.)

- [ ] **Step 2: Regenerate and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailViewModelFetchTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — the `fetchCommentsOperation:` init param and `setCommentSortType` do not exist yet.

- [ ] **Step 3: Implement the seam, cancel-and-replace, and setter**

In `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`:

1. Make the sort type read-only from outside and add the operation + task storage. Change `var commentSortType: Components.Schemas.CommentSortType` to:

```swift
    private(set) var commentSortType: Components.Schemas.CommentSortType
```

2. Add stored properties near the other `@ObservationIgnored` lets:

```swift
    @ObservationIgnored
    private let fetchCommentsOperation: @MainActor (Components.Schemas.CommentSortType) async throws -> Void

    @ObservationIgnored
    private var fetchTask: Task<Void, Never>?
```

3. Change the initializer signature and body to resolve the operation:

```swift
    init(
        serverPostId: Components.Schemas.PostID,
        accountScope: AccountScope,
        dependencies: Dependencies,
        fetchCommentsOperation: (@MainActor (Components.Schemas.CommentSortType) async throws -> Void)? = nil
    ) {
        self.dependencies = dependencies
        self.serverPostId = serverPostId
        self.accountScope = accountScope
        commentSortType = dependencies.preferencesService.defaultCommentSortType
        self.fetchCommentsOperation = fetchCommentsOperation ?? { sortType in
            try await accountScope.lemmyService
                .fetchComments(serverPostId: serverPostId, sortType: sortType)
        }
    }
```

4. Replace the dead `didChangeCommentSortType(_:)` with a plain setter:

```swift
    func setCommentSortType(_ sortType: Components.Schemas.CommentSortType) {
        commentSortType = sortType
    }
```

5. Replace `fetchComments()` with the cancel-and-replace version:

```swift
    func fetchComments() async {
        // Cancel-and-replace: a new fetch (e.g. a sort change) supersedes the
        // in-flight one. The flag is set synchronously and only the winning
        // (non-cancelled) task clears it or surfaces an error, so it never flaps
        // and a superseded fetch is silent.
        fetchTask?.cancel()
        isLoadingComments = true
        let sortType = commentSortType
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await fetchCommentsOperation(sortType)
            } catch is CancellationError {
                // Superseded — leave the flag to the winning fetch.
            } catch {
                if !Task.isCancelled {
                    alertService.handle(error, for: .fetchComments)
                }
            }
            if !Task.isCancelled {
                isLoadingComments = false
            }
        }
        fetchTask = task
        await task.value
    }
```

- [ ] **Step 4: Run to verify the tests pass**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailViewModelFetchTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (4 tests). If `testGenuineErrorIsSurfacedAndClearsFlag` fails to compile on the `XCTAssertEqual([.fetchComments])` line, switch it to the `.count` assertion noted in Step 1.

- [ ] **Step 5: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelFetchTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelFetchTests.swift
git commit -m "feat(post-detail): cancel-and-replace comment fetch with testable seam"
```

---

### Task 4: Config popover (view model + views)

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigViewModel.swift`
- Create: `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigView.swift`
- Create: `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigSortView.swift`
- Test: `SpudTests/PostDetailConfigViewModelTests.swift`

**Interfaces:**
- Consumes: `PreferencesServiceType.commentDensity` (Task 1), `Components.Schemas.CommentSortType`, `CommentSortType.itemForMenu`, `PostDensity`.
- Produces: `PostDetailConfigViewModel(preferencesService:currentSort:onSelectSort:)` with `commentDensity`, `currentSort`, `updateCommentDensity(_:)`, `selectSort(_:)`; `PostDetailConfigView(viewModel:)`; `PostDetailConfigSortView(viewModel:)`.

- [ ] **Step 1: Write the failing view-model tests**

Create `SpudTests/PostDetailConfigViewModelTests.swift`:

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
final class PostDetailConfigViewModelTests: XCTestCase {
    func testSeedsFromPreferencesAndCurrentSort() {
        let prefs = PreferencesService()
        prefs.commentDensity = .compact
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .New,
            onSelectSort: { _ in }
        )
        XCTAssertEqual(viewModel.commentDensity, .compact)
        XCTAssertEqual(viewModel.currentSort, .New)
    }

    func testUpdateCommentDensityWritesThrough() {
        let prefs = PreferencesService()
        prefs.commentDensity = .comfortable
        let viewModel = PostDetailConfigViewModel(
            preferencesService: prefs,
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
        viewModel.updateCommentDensity(.compact)
        XCTAssertEqual(viewModel.commentDensity, .compact)
        XCTAssertEqual(prefs.commentDensity, .compact)
    }

    func testSelectSortRoutesAndUpdates() {
        var selected: Components.Schemas.CommentSortType?
        let viewModel = PostDetailConfigViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )
        viewModel.selectSort(.Top)
        XCTAssertEqual(viewModel.currentSort, .Top)
        XCTAssertEqual(selected, .Top)
    }
}
```

- [ ] **Step 2: Regenerate and run to verify it fails**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailConfigViewModelTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: BUILD FAILURE — `cannot find 'PostDetailConfigViewModel' in scope`.

- [ ] **Step 3: Write the view model**

Create `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigViewModel.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit

/// Backs the post-detail config popover. Comment density is a preference,
/// written straight back through ``PreferencesService`` so the open post
/// re-flows live (the controller observes the same stream). Comment sort is
/// per-post, so it is routed to the controller via ``onSelectSort`` rather than
/// persisted. Seeds once at init (the popover is short-lived and the only writer
/// while open), mirroring ``QuickSwitchViewModel``.
@MainActor
@Observable
final class PostDetailConfigViewModel {
    private let preferencesService: PreferencesServiceType
    private let onSelectSort: (Components.Schemas.CommentSortType) -> Void

    let allCommentDensities: [PostDensity] = PostDensity.allCases

    var commentDensity: PostDensity
    var currentSort: Components.Schemas.CommentSortType

    init(
        preferencesService: PreferencesServiceType,
        currentSort: Components.Schemas.CommentSortType,
        onSelectSort: @escaping (Components.Schemas.CommentSortType) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onSelectSort = onSelectSort
        self.currentSort = currentSort
        commentDensity = preferencesService.commentDensity
    }

    func updateCommentDensity(_ value: PostDensity) {
        commentDensity = value
        preferencesService.commentDensity = value
        Haptics.tap()
    }

    func selectSort(_ value: Components.Schemas.CommentSortType) {
        currentSort = value
        onSelectSort(value)
        Haptics.tap()
    }
}
```

- [ ] **Step 4: Write the views**

Create `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import SwiftUI

/// The post-detail config popover: comment density plus a Sort row that pushes
/// the comment-sort picker. Hosted from the post-detail toolbar; density writes
/// through ``PreferencesService`` (live re-flow), sort routes per-post.
struct PostDetailConfigView: View {
    let viewModel: PostDetailConfigViewModel

    private var commentDensity: Binding<PostDensity> {
        .init { viewModel.commentDensity } set: { viewModel.updateCommentDensity($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Density") {
                    Picker("Density", selection: commentDensity) {
                        ForEach(viewModel.allCommentDensities) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink {
                        PostDetailConfigSortView(viewModel: viewModel)
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
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    PostDetailConfigView(
        viewModel: PostDetailConfigViewModel(
            preferencesService: PreferencesService(),
            currentSort: .Hot,
            onSelectSort: { _ in }
        )
    )
}
```

Create `Spud/Scenes/PostDetail/Content/Config/PostDetailConfigSortView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SwiftUI

/// The comment-sort picker pushed from the post-detail config popover. Lists the
/// `CommentSortType` cases, applies the selection immediately through the view
/// model, then pops back.
struct PostDetailConfigSortView: View {
    let viewModel: PostDetailConfigViewModel
    @Environment(\.dismiss) private var dismiss

    private let sortTypes: [Components.Schemas.CommentSortType] = [.Hot, .Top, .New, .Old, .Controversial]

    var body: some View {
        List {
            ForEach(sortTypes, id: \.self) { sortType in
                Button {
                    viewModel.selectSort(sortType)
                    dismiss()
                } label: {
                    HStack {
                        Text(sortType.itemForMenu.title)
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
        .navigationTitle("Sort")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 5: Regenerate and run to verify the tests pass**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailConfigViewModelTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: TEST SUCCEEDED (3 tests).

- [ ] **Step 6: Format and commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
mint run swiftformat Spud/Scenes/PostDetail/Content/Config SpudTests/PostDetailConfigViewModelTests.swift
git add Spud/Scenes/PostDetail/Content/Config SpudTests/PostDetailConfigViewModelTests.swift
git commit -m "feat(post-detail): add comment config popover (sort + density)"
```

---

### Task 5: Wire the config button + sort/density into the view controller

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`

**Interfaces:**
- Consumes: `PostDetailConfigView` / `PostDetailConfigViewModel` (Task 4), `ForcePopoverDelegate` (existing, `Scenes/PostList/QuickSwitch/ForcePopoverDelegate.swift`, same target), `PostDetailViewModel.setCommentSortType` / `fetchComments` (Task 3), `preferencesService.commentDensityStream` (Task 1), `startCommentObservation(postRowId:)` (existing).
- Produces: no new public surface.

No automated test (UIKit wiring); the logic it consumes is already tested. Gate: clean build (Step 6) plus manual on-sim checks (Step 7, a user gate — tap automation is unavailable here).

- [ ] **Step 1: Add the config button + popover delegate + density task properties**

In `PostDetailViewController`, in the `// MARK: - Private` block (near `overflowBarButtonItem` / the other `*Task` properties), add:

```swift
    private var configBarButtonItem: UIBarButtonItem!
    private let forcePopoverDelegate = ForcePopoverDelegate()
    private var commentDensityObservationTask: Task<Void, Never>?
```

- [ ] **Step 2: Create the button and show both nav items**

In `setup()`, replace the line `navigationItem.rightBarButtonItem = overflowBarButtonItem` with:

```swift
        configBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "slider.horizontal.3"),
            style: .plain,
            target: self,
            action: #selector(configTapped)
        )
        configBarButtonItem.accessibilityIdentifier = "postDetailConfig"
        configBarButtonItem.accessibilityLabel = NSLocalizedString(
            "Comment options",
            comment: "Accessibility label for the post detail comment config button"
        )
        navigationItem.rightBarButtonItems = [overflowBarButtonItem, configBarButtonItem]
```

- [ ] **Step 3: Present the popover**

Add (e.g. after `makePostOverflowMenu()` or near the other `@objc` actions):

```swift
    @objc
    private func configTapped() {
        Haptics.tap()
        let configViewModel = PostDetailConfigViewModel(
            preferencesService: preferencesService,
            currentSort: viewModel.commentSortType,
            onSelectSort: { [weak self] sortType in
                self?.changeCommentSort(to: sortType)
            }
        )
        let host = UIHostingController(rootView: PostDetailConfigView(viewModel: configViewModel))
        host.modalPresentationStyle = .popover
        host.sizingOptions = [.preferredContentSize]
        if let popover = host.popoverPresentationController {
            popover.sourceItem = configBarButtonItem
            popover.delegate = forcePopoverDelegate
        }
        present(host, animated: true)
    }
```

`UIHostingController` requires `import SwiftUI` in this file — add it if not present.

- [ ] **Step 4: Sort-change orchestration**

Add:

```swift
    /// Applies a new comment sort: updates the view model, restarts the comment
    /// observation with the new ordering, and triggers a cancel-and-replace
    /// fetch. Per-post only — the global default is untouched.
    private func changeCommentSort(to sortType: Components.Schemas.CommentSortType) {
        guard sortType != viewModel.commentSortType else { return }
        viewModel.setCommentSortType(sortType)
        if let postRowId = appDatabase.postRowIdSync(
            forKeychainId: viewModel.accountKeychainId,
            serverPostId: Int64(viewModel.serverPostId)
        ) {
            startCommentObservation(postRowId: postRowId)
        }
        Task { await viewModel.fetchComments() }
    }
```

- [ ] **Step 5: Live density re-flow**

Add the observation (mirrors `startSwipeActionsObservation` / `reconfigureVisibleSwipeActions`):

```swift
    /// Observes the comment-density preference and reconfigures visible comment
    /// cells when it changes, so the open thread re-flows live. Independent of
    /// the backing post, so it is started once in `viewDidLoad`.
    private func startCommentDensityObservation() {
        commentDensityObservationTask?.cancel()
        commentDensityObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var current = preferencesService.commentDensity
            for await density in preferencesService.commentDensityStream {
                if Task.isCancelled { break }
                guard density != current else { continue }
                current = density
                reconfigureVisibleComments()
            }
        }
    }

    /// Reconfigures visible comment cells so they rebuild body views at the
    /// updated density.
    private func reconfigureVisibleComments() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        let commentItems = snapshot.itemIdentifiers(inSection: .comments)
        guard !commentItems.isEmpty else { return }
        snapshot.reconfigureItems(commentItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
```

In `viewDidLoad()`, add `startCommentDensityObservation()` next to `startSwipeActionsObservation()`:

```swift
    override func viewDidLoad() {
        super.viewDidLoad()
        startSwipeActionsObservation()
        startCommentDensityObservation()
        startObservations()
    }
```

In `deinit`, add the cancel alongside the others:

```swift
        commentDensityObservationTask?.cancel()
```

- [ ] **Step 6: Format and build**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```

Expected: build succeeds with no new warnings (the pre-existing benign `Duplicate -rpath` may remain).

- [ ] **Step 7: Manual on-sim verification**

Boot a single simulator. Run the app, open a post, and check:

1. A `slider.horizontal.3` button appears beside the `•••` overflow; tapping it opens a popover (stays a popover on iPhone, not a full sheet).
2. Density segmented control toggles comfortable/compact → the open comment thread re-flows live (smaller/tighter text on compact).
3. Sort row pushes the comment-sort picker; choosing a different sort pops back and the comments reorder.
4. Rapid sort switches settle on the last choice with no error alert and no stuck spinner.
5. Reopening a different post uses the default comment sort (per-post, not persisted).

- [ ] **Step 8: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat(post-detail): add comment config button with live sort and density"
```

---

## Full regression pass (after Task 5)

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-comment-config
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostDetailViewModelFetchTests \
  -only-testing:SpudTests/PostDetailConfigViewModelTests \
  -only-testing:SpudTests/PostDetailViewModelLoadingTests \
  -only-testing:SpudTests/CommentsBackgroundTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test

xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests \
  -destination 'platform=iOS Simulator,id=<BOOTED_UDID>' \
  -skipPackagePluginValidation -skipMacroValidation test
```

Expected: all green.
