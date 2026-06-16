# Collapsed-parent "N new" badge + reachable jumps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A collapsed comment that hides new replies shows an accent "N new" pill, and the banner "Jump" / FAB "Next new" auto-expand collapsed ancestors so they always land on the real new comment instead of no-opping.

**Architecture:** Extend the pure `CommentCollapseState` (SpudDataKit) to also count *new* hidden descendants per collapsed parent and to compute the collapsed ancestors hiding a target. Thread the new count through `PostDetailViewModel` into the cell view model and cell (the pill), and add `expandAncestors(toReveal:)`. In `PostDetailViewController`, the banner Jump and FAB use the new ancestor data to expand-then-scroll, anchoring the FAB's "below the fold" test on a hidden-new comment's nearest visible collapsed ancestor.

**Tech Stack:** Swift 6, UIKit (diffable data source), GRDB (unaffected), XCTest, pointfreeco/swift-snapshot-testing.

Spec: `docs/superpowers/specs/2026-06-16-collapsed-new-badge-design.md`.

Branch: `feat/collapsed-new-badge` (already created off `main`).

**Conventions for every task:**
- Build/test a single class: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:<Target>/<Class> -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
- After adding a **new** `.swift` file, run `make project` (XcodeGen; the `.xcodeproj` is generated/gitignored).
- Use the already-booted iPhone 17 sim only; do not boot a second simulator.
- `git status` hides untracked files (`showUntrackedFiles=no`) — use `git status -uall`. Stage explicit paths; never `git add -A`. Never stage `.remember/remember.md`. Snapshot PNGs are git-annex and show as "modified" though unchanged — only stage NEW refs you intentionally record.
- Before staging, run `mint run swiftformat <changed swift paths>`.
- Commit style: conventional subject, no emojis, end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

### Task 1: `CommentCollapseState` — count new hidden descendants

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/CommentCollapseState.swift`
- Test: `SpudDataKitTests/CommentCollapseStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `CommentCollapseStateTests` (after `testCollapsingLeafHasNoEffectOnRowsAndZeroCount`):

```swift
func testCollapsedNewDescendantCountsCountsOnlyNewHiddenDescendants() {
    let tree = sampleTree() // 1 > (2 > 3), 4 ; 5
    // Collapse 1; 3 and 4 are new, 2 is old. All three are hidden under 1.
    let result = CommentCollapseState.visibleTree(
        orderedComments: tree,
        collapsedIds: [1],
        newElementIds: [3, 4]
    )
    XCTAssertEqual(result.collapsedDescendantCounts[1], 3)
    XCTAssertEqual(result.collapsedNewDescendantCounts[1], 2)
}

func testCollapsedNewDescendantCountsNestedCountsForOutermostVisibleParent() {
    let tree = sampleTree()
    // Collapse 1 and 2; only 3 is new. 1 is the visible parent; 2 is hidden.
    let result = CommentCollapseState.visibleTree(
        orderedComments: tree,
        collapsedIds: [1, 2],
        newElementIds: [3]
    )
    XCTAssertEqual(result.collapsedNewDescendantCounts[1], 1)
    XCTAssertNil(result.collapsedNewDescendantCounts[2]) // hidden -> no visible badge
}

func testCollapsedParentWithNoNewDescendantsHasNoNewCount() {
    let tree = sampleTree()
    // Collapse 1; the only new comment (5) is a sibling, not under 1.
    let result = CommentCollapseState.visibleTree(
        orderedComments: tree,
        collapsedIds: [1],
        newElementIds: [5]
    )
    XCTAssertEqual(result.collapsedDescendantCounts[1], 3)
    XCTAssertNil(result.collapsedNewDescendantCounts[1])
}

func testNoNewElementIdsLeavesNewCountsEmpty() {
    let tree = sampleTree()
    let result = CommentCollapseState.visibleTree(orderedComments: tree, collapsedIds: [1])
    XCTAssertTrue(result.collapsedNewDescendantCounts.isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/CommentCollapseStateTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `collapsedNewDescendantCounts` and the `newElementIds:` argument do not exist yet.

- [ ] **Step 3: Add the `collapsedNewDescendantCounts` field to `VisibleTree`**

In `CommentCollapseState.swift`, replace the `VisibleTree` struct (the `public struct VisibleTree ... }` block) with:

```swift
    public struct VisibleTree: Equatable, Sendable {
        /// The rows that should be rendered, in display order. Descendants of a
        /// collapsed comment are removed; the collapsed comment itself stays.
        public let rows: [PostDetailCommentRow]

        /// For each *collapsed and visible* comment element id, the number of
        /// descendant rows it is currently hiding. Used to render the "+N"
        /// badge. Comments that are themselves hidden (because an ancestor is
        /// collapsed) are not included.
        public let collapsedDescendantCounts: [Int64: Int]

        /// For each *collapsed and visible* comment element id, how many of its
        /// hidden descendants are new since the user's last visit (a subset of
        /// `collapsedDescendantCounts`). Used to render the accent "N new" pill.
        /// A parent absent from this map hides no new descendants.
        public let collapsedNewDescendantCounts: [Int64: Int]

        public init(
            rows: [PostDetailCommentRow],
            collapsedDescendantCounts: [Int64: Int],
            collapsedNewDescendantCounts: [Int64: Int] = [:]
        ) {
            self.rows = rows
            self.collapsedDescendantCounts = collapsedDescendantCounts
            self.collapsedNewDescendantCounts = collapsedNewDescendantCounts
        }
    }
```

- [ ] **Step 4: Add the `newElementIds` parameter and tally the new counts**

In `visibleTree(...)`, change the signature from:

```swift
    public static func visibleTree(
        orderedComments: [PostDetailCommentRow],
        collapsedIds: Set<Int64>
    ) -> VisibleTree {
```

to:

```swift
    public static func visibleTree(
        orderedComments: [PostDetailCommentRow],
        collapsedIds: Set<Int64>,
        newElementIds: Set<Int64> = []
    ) -> VisibleTree {
```

Immediately after `var collapsedCounts: [Int64: Int] = [:]`, add:

```swift
        var collapsedNewCounts: [Int64: Int] = [:]
```

Replace the descendant-tally loop:

```swift
            for parent in openCollapsedParents {
                collapsedCounts[parent.id, default: 0] += 1
            }
```

with:

```swift
            let rowIsNew = newElementIds.contains(row.id)
            for parent in openCollapsedParents {
                collapsedCounts[parent.id, default: 0] += 1
                if rowIsNew {
                    collapsedNewCounts[parent.id, default: 0] += 1
                }
            }
```

Replace the `return` statement:

```swift
        return VisibleTree(
            rows: visibleRows,
            collapsedDescendantCounts: collapsedCounts
        )
```

with:

```swift
        return VisibleTree(
            rows: visibleRows,
            collapsedDescendantCounts: collapsedCounts,
            collapsedNewDescendantCounts: collapsedNewCounts
        )
```

(Leave the `collapsedCounts[row.id] = 0` seeding line as-is; `collapsedNewCounts` is intentionally left sparse so a parent with zero new descendants has no key.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/CommentCollapseStateTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (all existing tests + the 4 new ones).

- [ ] **Step 6: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/CommentCollapseState.swift SpudDataKitTests/CommentCollapseStateTests.swift
git add SpudDataKit/Services/AppDatabase/CommentCollapseState.swift SpudDataKitTests/CommentCollapseStateTests.swift
git commit -m "$(cat <<'EOF'
feat: count new hidden descendants per collapsed comment

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `CommentCollapseState` — collapsed ancestors of a comment

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/CommentCollapseState.swift`
- Test: `SpudDataKitTests/CommentCollapseStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `CommentCollapseStateTests`:

```swift
func testCollapsedAncestorsVisibleTargetReturnsEmpty() {
    let tree = sampleTree()
    XCTAssertEqual(
        CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: []),
        []
    )
}

func testCollapsedAncestorsSingleCollapsedParent() {
    let tree = sampleTree() // 3's ancestors are 2 (depth 2) and 1 (depth 1)
    XCTAssertEqual(
        CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: [1]),
        [1]
    )
}

func testCollapsedAncestorsNestedChainIsLeafToRoot() {
    let tree = sampleTree()
    // Both 1 and 2 collapsed; revealing 3 needs both, returned leaf-to-root.
    XCTAssertEqual(
        CommentCollapseState.collapsedAncestors(of: 3, in: tree, collapsedIds: [1, 2]),
        [2, 1]
    )
}

func testCollapsedAncestorsUnknownIdReturnsEmpty() {
    let tree = sampleTree()
    XCTAssertEqual(
        CommentCollapseState.collapsedAncestors(of: 999, in: tree, collapsedIds: [1]),
        []
    )
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/CommentCollapseStateTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `collapsedAncestors` does not exist.

- [ ] **Step 3: Implement `collapsedAncestors`**

In `CommentCollapseState.swift`, add this method after `descendantIds(of:in:)` (before the final closing `}` of the enum):

```swift
    /// The currently-collapsed ancestor element ids that hide `elementId` — the
    /// set a caller must expand to make `elementId` visible. Walks the pre-order
    /// list backward from `elementId`, collecting each strictly-shallower row (the
    /// ancestor chain) that is in `collapsedIds`. Returns leaf-to-root order; the
    /// caller should treat it as a set. Empty when the element is absent or has no
    /// collapsed ancestor.
    public static func collapsedAncestors(
        of elementId: Int64,
        in orderedComments: [PostDetailCommentRow],
        collapsedIds: Set<Int64>
    ) -> [Int64] {
        guard let startIndex = orderedComments.firstIndex(where: { $0.id == elementId }) else {
            return []
        }
        var result: [Int64] = []
        var ancestorDepth = orderedComments[startIndex].depth
        var index = startIndex - 1
        while index >= 0 {
            let row = orderedComments[index]
            if row.depth < ancestorDepth {
                if collapsedIds.contains(row.id) {
                    result.append(row.id)
                }
                ancestorDepth = row.depth
                if ancestorDepth <= 1 { break }
            }
            index -= 1
        }
        return result
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudDataKitTests/CommentCollapseStateTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/CommentCollapseState.swift SpudDataKitTests/CommentCollapseStateTests.swift
git add SpudDataKit/Services/AppDatabase/CommentCollapseState.swift SpudDataKitTests/CommentCollapseStateTests.swift
git commit -m "$(cat <<'EOF'
feat: compute collapsed ancestors hiding a comment

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `PostDetailViewModel` — thread new counts + `expandAncestors`

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Create: `SpudTests/PostDetailViewModelExpandAncestorsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/PostDetailViewModelExpandAncestorsTests.swift`:

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

@MainActor
final class PostDetailViewModelExpandAncestorsTests: XCTestCase {
    private func row(id: Int64, depth: Int64, publishedOffset: TimeInterval = 0) -> PostDetailCommentRow {
        PostDetailCommentRow(
            id: id, position: id, depth: depth,
            serverCommentId: id, body: "b\(id)",
            originalCommentUrl: "https://example.test/comment/\(id)",
            score: 0, voteStatus: nil, isSaved: false, isRemoved: false,
            isDistinguished: false, isDeleted: false, isCreatorModerator: false,
            isCreatorAdmin: false, isCreatorBannedFromCommunity: false,
            isCreatorBlocked: false, isCreatorSiteBanned: false, isCreatorBot: false,
            isCreatorAccountDeleted: false, removedReason: nil,
            published: Date(timeIntervalSince1970: 1_000_000 + publishedOffset),
            creatorName: "u\(id)", creatorPersonId: id,
            creatorInstanceActorId: "https://example.test",
            moreChildCount: nil, moreParentId: nil
        )
    }

    private func makeViewModel() -> PostDetailViewModel {
        PostDetailViewModel(
            serverPostId: 1,
            accountKeychainId: "kc-1",
            dependencies: TestDependencies()
        )
    }

    func testExpandAncestorsRevealsCollapsedParent() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        XCTAssertTrue(vm.isCollapsed(elementId: 1))

        XCTAssertTrue(vm.expandAncestors(toReveal: 3))
        XCTAssertFalse(vm.isCollapsed(elementId: 1))
    }

    func testExpandAncestorsRemovesNestedCollapsedAncestors() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2), row(id: 3, depth: 3)])
        vm.toggleCollapse(elementId: 1)
        vm.toggleCollapse(elementId: 2)

        XCTAssertTrue(vm.expandAncestors(toReveal: 3))
        XCTAssertFalse(vm.isCollapsed(elementId: 1))
        XCTAssertFalse(vm.isCollapsed(elementId: 2))
    }

    func testExpandAncestorsIsIdempotentWhenAlreadyVisible() {
        let vm = makeViewModel()
        vm.updateOrderedComments([row(id: 1, depth: 1), row(id: 2, depth: 2)])
        XCTAssertFalse(vm.expandAncestors(toReveal: 2))
    }

    func testVisibleCommentTreeSurfacesCollapsedNewCounts() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        // 1 > (2 old, 3 new). Collapse 1.
        vm.updateOrderedComments([
            row(id: 1, depth: 1, publishedOffset: 50),
            row(id: 2, depth: 2, publishedOffset: 50),
            row(id: 3, depth: 2, publishedOffset: 300),
        ])
        vm.toggleCollapse(elementId: 1)

        let tree = vm.visibleCommentTree()
        XCTAssertEqual(tree.collapsedDescendantCounts[1], 2)
        XCTAssertEqual(tree.collapsedNewDescendantCounts[1], 1)
    }
}
```

- [ ] **Step 2: Regenerate the project and run the tests to verify they fail**

Run: `make project`
Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailViewModelExpandAncestorsTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `expandAncestors(toReveal:)` does not exist; `visibleCommentTree()` does not yet pass `newElementIds`.

- [ ] **Step 3: Thread `newElementIds` and add `expandAncestors`**

In `PostDetailViewModel.swift`, replace `visibleCommentTree()`:

```swift
    func visibleCommentTree() -> CommentCollapseState.VisibleTree {
        CommentCollapseState.visibleTree(
            orderedComments: orderedComments,
            collapsedIds: collapsedElementIds
        )
    }
```

with:

```swift
    func visibleCommentTree() -> CommentCollapseState.VisibleTree {
        CommentCollapseState.visibleTree(
            orderedComments: orderedComments,
            collapsedIds: collapsedElementIds,
            newElementIds: newCommentState.newElementIds
        )
    }

    /// Expands every currently-collapsed ancestor of `elementId` so the comment
    /// becomes visible. Returns `true` if the collapsed set changed (the caller
    /// rebuilds the snapshot before scrolling). Idempotent: a already-visible
    /// target changes nothing and returns `false`.
    @discardableResult
    func expandAncestors(toReveal elementId: Int64) -> Bool {
        let ancestors = CommentCollapseState.collapsedAncestors(
            of: elementId,
            in: orderedComments,
            collapsedIds: collapsedElementIds
        )
        guard !ancestors.isEmpty else { return false }
        collapsedElementIds.subtract(ancestors)
        return true
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailViewModelExpandAncestorsTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelExpandAncestorsTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelExpandAncestorsTests.swift
git commit -m "$(cat <<'EOF'
feat: expose collapsed-new counts and expandAncestors on PostDetailViewModel

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `PostDetailCommentViewModel` — new-count input + VoiceOver

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`
- Test: `SpudTests/PostDetailCommentViewModelAccessibilityTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PostDetailCommentViewModelAccessibilityTests`:

```swift
func testCollapsedWithNewDescendantsAddsNewClauseAndExposesCount() {
    let appearance = AppearanceService(preferencesService: PreferencesService())
    let vm = PostDetailCommentViewModel(
        row: makeRow(),
        appearance: appearance,
        isCollapsed: true,
        collapsedDescendantCount: 22,
        collapsedNewDescendantCount: 5
    )
    let label = vm.subtitleAccessibilityLabel ?? ""
    XCTAssertTrue(label.contains("22 hidden"), "expected hidden count in: \(label)")
    XCTAssertTrue(label.contains("5 new"), "expected new count in: \(label)")
    XCTAssertEqual(vm.collapsedNewDescendantCount, 5)
}

func testCollapsedWithZeroNewDescendantsHasNoNewCount() {
    let appearance = AppearanceService(preferencesService: PreferencesService())
    let vm = PostDetailCommentViewModel(
        row: makeRow(),
        appearance: appearance,
        isCollapsed: true,
        collapsedDescendantCount: 8,
        collapsedNewDescendantCount: 0
    )
    XCTAssertNil(vm.collapsedNewDescendantCount)
    XCTAssertFalse((vm.subtitleAccessibilityLabel ?? "").contains(" new"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailCommentViewModelAccessibilityTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — no `collapsedNewDescendantCount` parameter/property.

- [ ] **Step 3: Add the property, init parameter, and VoiceOver clause**

In `PostDetailCommentViewModel.swift`, add the stored property after the `collapsedBadgeText` declaration:

```swift
    /// Count of *new* descendants hidden under this collapsed comment, for the
    /// accent "N new" pill. nil when none (the cell renders no pill). The cell
    /// builds the pill so the accent resolves from its `tintColor`.
    let collapsedNewDescendantCount: Int?
```

In `init`, add the parameter after `collapsedDescendantCount: Int? = nil,`:

```swift
        collapsedNewDescendantCount: Int? = nil,
```

Assign the property — add immediately after the `collapsedBadgeText` assignment block (the `if let count = collapsedDescendantCount ... } else { collapsedBadgeText = nil }`):

```swift
        if let newCount = collapsedNewDescendantCount, newCount > 0 {
            self.collapsedNewDescendantCount = newCount
        } else {
            self.collapsedNewDescendantCount = nil
        }
```

In the accessibility section's collapsed branch, replace:

```swift
            if isCollapsed {
                if let count = collapsedDescendantCount, count > 0 {
                    pieces.append(String(
                        format: NSLocalizedString(
                            "collapsed, %lld hidden",
                            comment: "VoiceOver: collapsed comment with hidden descendant count"
                        ),
                        count
                    ))
                } else {
                    pieces.append(NSLocalizedString("collapsed", comment: "VoiceOver: collapsed comment"))
                }
            }
```

with:

```swift
            if isCollapsed {
                if let count = collapsedDescendantCount, count > 0 {
                    pieces.append(String(
                        format: NSLocalizedString(
                            "collapsed, %lld hidden",
                            comment: "VoiceOver: collapsed comment with hidden descendant count"
                        ),
                        count
                    ))
                } else {
                    pieces.append(NSLocalizedString("collapsed", comment: "VoiceOver: collapsed comment"))
                }
                if let newCount = collapsedNewDescendantCount, newCount > 0 {
                    pieces.append(String(
                        format: NSLocalizedString(
                            "%lld new",
                            comment: "VoiceOver: count of new replies hidden under a collapsed comment"
                        ),
                        newCount
                    ))
                }
            }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailCommentViewModelAccessibilityTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift SpudTests/PostDetailCommentViewModelAccessibilityTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift SpudTests/PostDetailCommentViewModelAccessibilityTests.swift
git commit -m "$(cat <<'EOF'
feat: expose collapsed-new count on comment view model with VoiceOver clause

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `PostDetailCommentCell` — the accent "N new" pill

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`

(No standalone unit test — the pill's rendering is covered by the snapshot in Task 6. This task and Task 6 are committed together at the end of Task 6.)

- [ ] **Step 1: Add the pill label**

In `PostDetailCommentCell.swift`, add this lazy property immediately after the `collapsedBadgeLabel` declaration (after its closing `}()`):

```swift
    /// Accent "N new" pill shown on a collapsed comment that hides replies new
    /// since the user's last visit, beside the "+N" hidden-count label.
    lazy var collapsedNewBadgeLabel: BadgeLabel = {
        let label = BadgeLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.accessibilityIdentifier = "collapsedNewBadge"
        label.isAccessibilityElement = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()
```

- [ ] **Step 2: Add the pill to the header stack**

In the `headerStackView` lazy initializer, change the `subviews` array from:

```swift
        let subviews = [
            newDotView,
            authorLabel,
            badgesStackView,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
        ]
```

to:

```swift
        let subviews = [
            newDotView,
            authorLabel,
            badgesStackView,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
            collapsedNewBadgeLabel,
        ]
```

and add a custom spacing line after the existing `setCustomSpacing(...)` calls in that initializer:

```swift
        stackView.setCustomSpacing(6, after: collapsedBadgeLabel)
```

- [ ] **Step 3: Configure the pill**

In `configure(with:imageService:)`, immediately after the two `collapsedBadgeLabel` lines:

```swift
        collapsedBadgeLabel.attributedText = viewModel.collapsedBadgeText
        collapsedBadgeLabel.isHidden = viewModel.collapsedBadgeText == nil
```

add:

```swift
        if let newCount = viewModel.collapsedNewDescendantCount {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            collapsedNewBadgeLabel.attributedText = NSAttributedString(
                string: "\(newCount) new",
                attributes: attributes
            )
            collapsedNewBadgeLabel.backgroundColor = accent
            collapsedNewBadgeLabel.isHidden = false
        } else {
            collapsedNewBadgeLabel.attributedText = nil
            collapsedNewBadgeLabel.backgroundColor = .clear
            collapsedNewBadgeLabel.isHidden = true
        }
```

- [ ] **Step 4: Reset the pill on reuse**

In `prepareForReuse()`, after the `newDotView.backgroundColor = .clear` line, add:

```swift
        collapsedNewBadgeLabel.attributedText = nil
        collapsedNewBadgeLabel.backgroundColor = .clear
        collapsedNewBadgeLabel.isHidden = true
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED. (Commit happens in Task 6 with the recorded snapshot.)

---

### Task 6: Snapshot — collapsed comment with a "N new" pill

**Files:**
- Modify: `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift`
- Create (recorded): `SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_collapsedWithNew.light.png` and `…/test_collapsedWithNew.dark.png`

- [ ] **Step 1: Add the `collapsedNewDescendantCount` parameter to the snapshot helper**

In `PostDetailCommentSnapshotTests.swift`, change `makeViewModel` from:

```swift
    private func makeViewModel(
        row: PostDetailCommentRow,
        postCreatorPersonId: Int64? = nil,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil,
        isNew: Bool = false
    ) -> PostDetailCommentViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailCommentViewModel(
            row: row,
            appearance: appearance,
            postCreatorPersonId: postCreatorPersonId,
            isCollapsed: isCollapsed,
            collapsedDescendantCount: collapsedDescendantCount,
            isNew: isNew
        )
    }
```

to:

```swift
    private func makeViewModel(
        row: PostDetailCommentRow,
        postCreatorPersonId: Int64? = nil,
        isCollapsed: Bool = false,
        collapsedDescendantCount: Int? = nil,
        collapsedNewDescendantCount: Int? = nil,
        isNew: Bool = false
    ) -> PostDetailCommentViewModel {
        let appearance = AppearanceService(preferencesService: PreferencesService())
        return PostDetailCommentViewModel(
            row: row,
            appearance: appearance,
            postCreatorPersonId: postCreatorPersonId,
            isCollapsed: isCollapsed,
            collapsedDescendantCount: collapsedDescendantCount,
            collapsedNewDescendantCount: collapsedNewDescendantCount,
            isNew: isNew
        )
    }
```

- [ ] **Step 2: Add the snapshot test**

Add after `test_collapsed_withDescendantCount`:

```swift
    func test_collapsedWithNew() {
        // A collapsed parent hiding 22 descendants, 5 of them new: "+22" plus an
        // accent "5 new" pill (the glidergun demo node).
        assertComment(viewModel: makeViewModel(
            row: row(),
            isCollapsed: true,
            collapsedDescendantCount: 22,
            collapsedNewDescendantCount: 5
        ))
    }
```

- [ ] **Step 3: Run once to record the new reference images (expected to fail)**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests/test_collapsedWithNew -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL with "No reference was found on disk. Automatically recorded snapshot" — this writes the two new PNGs.

- [ ] **Step 4: Visually confirm the recorded pill**

Open the two recorded PNGs and confirm: the collapsed cell shows the "+22" secondary text followed by a teal rounded pill reading "5 new", in both light and dark.

```bash
open SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_collapsedWithNew.light.png \
     SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_collapsedWithNew.dark.png
```
Expected: pill renders as described. If wrong, fix Task 5's `configure` styling and re-record.

- [ ] **Step 5: Run again to verify the references match**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (the whole comment-snapshot class, confirming no other cell snapshot regressed).

- [ ] **Step 6: Commit (cell + snapshot together)**

Find the newly recorded refs (untracked) with `git status -uall`, then stage them explicitly along with the cell and test changes. Do NOT stage the pre-existing "modified" annex PNGs.

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift SpudSnapshotTests/PostDetailCommentSnapshotTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift \
        SpudSnapshotTests/PostDetailCommentSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_collapsedWithNew.light.png \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_collapsedWithNew.dark.png
git commit -m "$(cat <<'EOF'
feat: render an accent "N new" pill on collapsed comments

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `PostDetailViewController` — pass the count + auto-expand jumps

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`

(The scroll behavior is UIKit integration — verified on-device in Task 8, not by a unit test. The expand decision is already unit-tested via `expandAncestors` in Task 3.)

- [ ] **Step 1: Store the per-row new counts and feed them to the cell**

Add a property next to `collapsedDescendantCounts` (line ~144):

```swift
    private var collapsedNewDescendantCounts: [Int64: Int] = [:]
```

In `applySnapshot`, after `collapsedDescendantCounts = visible.collapsedDescendantCounts`, add:

```swift
        collapsedNewDescendantCounts = visible.collapsedNewDescendantCounts
```

In the `.comment(elementId)` cell provider, after `let collapsedCount = self?.collapsedDescendantCounts[elementId]`, add:

```swift
                let collapsedNewCount = self?.collapsedNewDescendantCounts[elementId]
```

and add the argument to the `PostDetailCommentViewModel(...)` call, after `collapsedDescendantCount: collapsedCount,`:

```swift
                    collapsedNewDescendantCount: collapsedNewCount,
```

- [ ] **Step 2: Add the expand-then-scroll helper**

Add this method in the "Jump to next top-level comment / next new comment" section (e.g. just below `indexPathOfNextTopLevelComment()`):

```swift
    /// Scrolls to the comment, first expanding any collapsed ancestors that hide
    /// it (rebuilding the snapshot non-animated) so the row exists before the
    /// scroll. Does not haptic — callers do.
    private func scrollToComment(elementId: Int64) {
        if dataSource.indexPath(for: .comment(elementId: elementId)) == nil {
            if viewModel.expandAncestors(toReveal: elementId) {
                applySnapshot(animated: false)
            }
        }
        guard let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)) else { return }
        tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Where `elementId` currently sits on screen: its own row if visible, else
    /// its nearest *visible* collapsed ancestor (the outermost collapsed one).
    /// Used to position a possibly-hidden new comment for the "below the fold"
    /// test. Returns nil only when neither resolves (should not happen for a
    /// comment in the tree).
    private func anchorIndexPath(forNewComment elementId: Int64) -> IndexPath? {
        if let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)) {
            return indexPath
        }
        let ancestors = CommentCollapseState.collapsedAncestors(
            of: elementId,
            in: viewModel.orderedComments,
            collapsedIds: viewModel.collapsedElementIds
        )
        for ancestorId in ancestors {
            if let indexPath = dataSource.indexPath(for: .comment(elementId: ancestorId)) {
                return indexPath
            }
        }
        return nil
    }
```

- [ ] **Step 3: Replace `indexPathOfNextNewComment` with an anchor-based, expand-aware target**

Replace the whole `indexPathOfNextNewComment()` method:

```swift
    private func indexPathOfNextNewComment() -> IndexPath? {
        let threshold = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
        for elementId in viewModel.orderedNewCommentElementIds {
            guard let indexPath = dataSource.indexPath(for: .comment(elementId: elementId)) else { continue }
            if tableView.rectForRow(at: indexPath).minY > threshold {
                return indexPath
            }
        }
        return nil
    }
```

with:

```swift
    /// The element id of the next new comment whose anchor row sits below the
    /// current scroll position, in display order. The anchor lets a collapsed-away
    /// new comment still count (positioned at its visible collapsed ancestor); the
    /// jump handler expands it. Returns nil when none below.
    private func nextNewCommentBelowFold() -> Int64? {
        let threshold = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
        for elementId in viewModel.orderedNewCommentElementIds {
            guard let anchor = anchorIndexPath(forNewComment: elementId) else { continue }
            if tableView.rectForRow(at: anchor).minY > threshold {
                return elementId
            }
        }
        return nil
    }
```

- [ ] **Step 4: Replace `jumpTarget` with a `JumpTarget` enum**

Replace the `jumpTarget()` method:

```swift
    private func jumpTarget() -> (indexPath: IndexPath, isNew: Bool)? {
        if viewModel.newCommentCount > 0, let next = indexPathOfNextNewComment() {
            return (next, true)
        }
        if let next = indexPathOfNextTopLevelComment() {
            return (next, false)
        }
        return nil
    }
```

with:

```swift
    /// The FAB's current jump target. A new-comment target is identified by id (it
    /// may be collapsed away and is expanded on tap); a fallback next-top-level
    /// target is a concrete index path.
    private enum JumpTarget {
        case newComment(elementId: Int64)
        case topLevel(indexPath: IndexPath)

        var isNew: Bool {
            if case .newComment = self { return true }
            return false
        }
    }

    private func jumpTarget() -> JumpTarget? {
        if viewModel.newCommentCount > 0, let elementId = nextNewCommentBelowFold() {
            return .newComment(elementId: elementId)
        }
        if let indexPath = indexPathOfNextTopLevelComment() {
            return .topLevel(indexPath: indexPath)
        }
        return nil
    }
```

- [ ] **Step 5: Update the FAB tap handler and the banner Jump to use expand-then-scroll**

Replace `jumpToNextTopCommentTapped()`:

```swift
    @objc
    private func jumpToNextTopCommentTapped() {
        guard let target = jumpTarget() else { return }
        Haptics.tap()
        tableView.scrollToRow(at: target.indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }
```

with:

```swift
    @objc
    private func jumpToNextTopCommentTapped() {
        guard let target = jumpTarget() else { return }
        Haptics.tap()
        switch target {
        case let .newComment(elementId):
            scrollToComment(elementId: elementId)
        case let .topLevel(indexPath):
            tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
```

Replace `jumpToFirstNewComment()`:

```swift
    private func jumpToFirstNewComment() {
        guard
            let elementId = viewModel.firstNewCommentElementId,
            let indexPath = dataSource.indexPath(for: .comment(elementId: elementId))
        else { return }
        Haptics.tap()
        tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }
```

with:

```swift
    private func jumpToFirstNewComment() {
        guard let elementId = viewModel.firstNewCommentElementId else { return }
        Haptics.tap()
        scrollToComment(elementId: elementId)
    }
```

- [ ] **Step 6: Confirm `updateJumpButtonVisibility` still type-checks**

`updateJumpButtonVisibility()` reads `let target = jumpTarget()`, `let shouldShow = target != nil`, and `applyJumpButtonStyle(isNew: target?.isNew ?? false)`. The new `JumpTarget?` supports `!= nil` and `?.isNew`, so no change is required. Read it to confirm (around line 553); make no edit.

- [ ] **Step 7: Build to verify it compiles**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "$(cat <<'EOF'
feat: auto-expand collapsed ancestors when jumping to new comments

The banner Jump and FAB Next-new now expand any collapsed ancestors hiding
the target new comment and scroll to it, instead of no-opping or skipping.
The FAB anchors a collapsed-away new comment at its visible collapsed
ancestor for the below-the-fold test.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Full regression + on-device verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full unit + data-layer suites on the merged tree**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: `TEST SUCCEEDED` — all SpudTests + SpudDataKitTests pass, including the new collapse/expand and accessibility tests.

- [ ] **Step 2: Run the snapshot suite**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS, including `test_collapsedWithNew`.

- [ ] **Step 3: On-device verification pass (manual, iPhone 17 sim)**

This exercises the part no unit test covers — the scroll. Using a post that has comments new since the last visit (see the test Lemmy instances in memory `spud_lemmy_test_instances`, or open a post twice with a gap):
  1. Collapse a top-level comment that contains a new reply. Confirm the collapsed cell shows "+N" and a teal "N new" pill.
  2. Tap the banner "Jump". Confirm the collapsed ancestor expands and the view scrolls to the actual new comment (no dead tap).
  3. Scroll up, tap the FAB "Next new" repeatedly. Confirm it steps into collapsed-away new comments by expanding them, and never silently skips one that the banner counted.
  4. Toggle VoiceOver on the collapsed cell; confirm it speaks "collapsed, N hidden, M new".

Note: `idb` tap automation is broken here (memory `spud_ui_test_sim_flake`); drive via the accessibility-based approach in `ddenis:ios-simulator-skill` and capture `simctl` screenshots.

- [ ] **Step 4: Verify the branch is clean and review the diff**

```bash
git status -uall
git log --oneline main..HEAD
```
Expected: only the intended commits (Tasks 1-7) ahead of `main`; no stray staged files; `.remember/remember.md` not committed.

---

## Self-Review

**1. Spec coverage:**
- "N new pill on collapsed parents" → Tasks 1 (count), 4 (VM), 5 (cell), 6 (snapshot). ✓
- "Auto-expand then jump" (banner Jump + FAB) → Tasks 2 (ancestors), 3 (`expandAncestors`), 7 (VC wiring). ✓
- "FAB anchor row" → Task 7 Step 2-3 (`anchorIndexPath` + `nextNewCommentBelowFold`). ✓
- "Rebuild non-animated then scroll" → Task 7 Step 2 (`scrollToComment` calls `applySnapshot(animated: false)`). ✓
- VoiceOver "N hidden, M new" → Task 4. ✓
- Testing (pure unit, VM, cell VM, snapshot, on-device) → Tasks 1-4, 6, 8. ✓
- Out of scope (settings toggle, push, whole-feature on-device) → not in any task. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**3. Type consistency:**
- `collapsedNewDescendantCounts` (VisibleTree field, VC property) — same name throughout. ✓
- `collapsedNewDescendantCount` (cell-VM init param + property + VC local `collapsedNewCount` passed into it) — consistent. ✓
- `expandAncestors(toReveal:)`, `collapsedAncestors(of:in:collapsedIds:)`, `visibleTree(orderedComments:collapsedIds:newElementIds:)`, `scrollToComment(elementId:)`, `anchorIndexPath(forNewComment:)`, `nextNewCommentBelowFold()`, `JumpTarget` — defined once, referenced consistently. ✓
- `viewModel.orderedComments` / `viewModel.collapsedElementIds` are `private(set) var` on `PostDetailViewModel` (same Spud module as the VC) — readable from `anchorIndexPath`. ✓
