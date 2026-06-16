# New-comment Visual Treatment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the "new since last visit" comment treatment in post detail — a teal wash that fades once per new comment, a persistent gutter dot, an in-flow "N new" banner, and a "Next new" jump pill — driving the already-computed (but unused) Phase 1 `newCommentState`.

**Architecture:** A pure `FreshWashState` decides each new comment's wash (none / static / fade-from-tint) from `isNew` + `hasAnimated` + reduce-motion. `PostDetailCommentCell` reuses its existing full-bleed `tintBackingView` for the wash (Core Animation keyframe fade) and gains a gutter dot; the host VC tracks `animatedNewCommentIds` and triggers the once-per-comment fade from a new `willDisplay` hook. A banner row (new `Item.newSinceBanner`) totals the new comments, and the existing "jump to next top-level comment" FAB is extended to prefer the next *new* comment when any exist.

**Tech Stack:** Swift 6, UIKit (UITableViewDiffableDataSource, Core Animation `CAKeyframeAnimation`), XCTest, pointfreeco/swift-snapshot-testing. Spud app target + SpudDataKit is untouched (the data already exists).

**Builds on (Phase 1, shipped):** `PostDetailViewModel.previousVisitAt`, `newCommentState` (`newElementIds: Set<Int64>`, `firstNewElementId`, `count`), `isNewComment(elementId:)`, `newCommentCount`, `firstNewCommentElementId`, and `orderedComments: [PostDetailCommentRow]` (display order; each row's `id` is its element id).

**Key files (from the codebase):**
- `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` — `tintBackingView` (full-bleed wash, reset in `prepareForReuse`), `configure(with:imageService:)` resolving `accent = tintColor ?? .systemTeal`, `headerStackView` (leading edge of the header line).
- `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift` — value snapshot; init at line 83 with params `(row:appearance:postCreatorPersonId:isCollapsed:collapsedDescendantCount:isBlockedRevealed:)`.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — `Section {header, comments}` / `Item {header, comment(elementId:)}` (line 1311), cell provider (line 1379), `applySnapshot` (line 413), the jump FAB `indexPathOfNextTopLevelComment`/`jumpToNextTopCommentTapped`/`updateJumpButtonVisibility` (lines 477-529), `scrollViewDidScroll` → `updateJumpButtonVisibility` (line 1450). There is NO `willDisplay` here yet.

**Commands (from `/Users/denis/dev/info.ddenis/Spud/Spud`):**
```sh
# unit test a class (iPhone 17 is booted)
xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/<Class> \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test
# snapshot tests (iPhone 14 Pro required for legacy refs; newer ones pin a config so any sim works — first run records, rerun verifies)
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostDetailCommentSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test
# app build + full unit plan
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"
# after creating any new .swift file:
make project
```

House rules (every task): `make project` after creating new files; booted `iPhone 17` only; Swift 6; no emojis; `mint run swiftformat <paths>` before staging; stage explicit paths (never `git add -A`; `git status -uall`); never touch `.remember/remember.md` or `SpudSnapshotTests/__Snapshots__/` except the new snapshot refs the test run records for this feature; end commit messages with a blank line then `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Ignore SourceKit "No such module" diagnostics — trust the build.

---

## Task 1: `orderedNewCommentElementIds` on the view model

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift`
- Test: `SpudTests/PostDetailViewModelNewCommentTests.swift` (existing — append)

- [ ] **Step 1: Write the failing test**

Append to `SpudTests/PostDetailViewModelNewCommentTests.swift` (it already has `makeRow(id:publishedOffset:creatorPersonId:)` and `makeViewModel()` helpers from Phase 1 — reuse them):

```swift
    func testOrderedNewCommentElementIdsAreInDisplayOrderAndOnlyNew() {
        let vm = makeViewModel()
        vm.previousVisitAt = Date(timeIntervalSince1970: 1_000_000 + 100)
        vm.currentAccountPersonId = nil
        vm.updateOrderedComments([
            makeRow(id: 10, publishedOffset: 50),   // before visit -> not new
            makeRow(id: 11, publishedOffset: 200),  // new
            makeRow(id: 12, publishedOffset: 300),  // new
        ])
        XCTAssertEqual(vm.orderedNewCommentElementIds, [11, 12])
    }

    func testOrderedNewCommentElementIdsEmptyOnFirstVisit() {
        let vm = makeViewModel()
        vm.previousVisitAt = nil
        vm.updateOrderedComments([makeRow(id: 1, publishedOffset: 500)])
        XCTAssertEqual(vm.orderedNewCommentElementIds, [])
    }
```

(If `makeRow`'s argument labels differ from `(id:publishedOffset:)`, match the existing helper in that file.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/PostDetailViewModelNewCommentTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — no member `orderedNewCommentElementIds`.

- [ ] **Step 3: Add the computed property**

In `PostDetailViewModel.swift`, in the "New-comment delta (view-layer)" section (next to `newCommentCount` / `firstNewCommentElementId`), add:

```swift
    /// Element ids of the new comments in display order (the order they appear
    /// in the current tree). Powers the "Next new" jump. Empty on a first visit.
    var orderedNewCommentElementIds: [Int64] {
        let newIds = newCommentState.newElementIds
        guard !newIds.isEmpty else { return [] }
        return orderedComments.map(\.id).filter { newIds.contains($0) }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelNewCommentTests.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift SpudTests/PostDetailViewModelNewCommentTests.swift
git commit -m "feat: expose orderedNewCommentElementIds for jump navigation"
```

---

## Task 2: `FreshWashState` pure helper

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/Comment/FreshWashState.swift`
- Test: `SpudTests/FreshWashStateTests.swift`

- [ ] **Step 1: Write the failing test**

`SpudTests/FreshWashStateTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class FreshWashStateTests: XCTestCase {
    func testNotNewIsNone() {
        XCTAssertEqual(FreshWashState.resolve(isNew: false, hasAnimated: false, reduceMotion: false), .none)
        XCTAssertEqual(FreshWashState.resolve(isNew: false, hasAnimated: true, reduceMotion: true), .none)
    }

    func testReduceMotionNewIsStaticTint() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: true), .staticTint)
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: true), .staticTint)
    }

    func testNewNotYetAnimatedFadesFromTint() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: false, reduceMotion: false), .fadeFromTint)
    }

    func testNewAlreadyAnimatedIsNone() {
        XCTAssertEqual(FreshWashState.resolve(isNew: true, hasAnimated: true, reduceMotion: false), .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (after `make project`): `xcodebuild -project Spud.xcodeproj -scheme Spud -only-testing:SpudTests/FreshWashStateTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — cannot find `FreshWashState`.

- [ ] **Step 3: Write the implementation**

`Spud/Scenes/PostDetail/Content/Comment/FreshWashState.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which background-wash treatment a comment row should show for the
/// "new since last visit" state. Pure decision, unit-tested in isolation.
enum FreshWashState: Equatable {
    /// No wash (not new, or new but its one-time fade already played).
    case none
    /// Hold a static tint for the visit (reduce-motion: no animation).
    case staticTint
    /// Start tinted and fade to the resting background once.
    case fadeFromTint

    static func resolve(isNew: Bool, hasAnimated: Bool, reduceMotion: Bool) -> FreshWashState {
        guard isNew else { return .none }
        if reduceMotion { return .staticTint }
        return hasAnimated ? .none : .fadeFromTint
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/FreshWashState.swift SpudTests/FreshWashStateTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/FreshWashState.swift SpudTests/FreshWashStateTests.swift
git commit -m "feat: add FreshWashState decision helper"
```

---

## Task 3: `isNew` on the comment view model + persistent gutter dot

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (cell provider: pass `isNew`)
- Test: `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift` (append a fresh-dot case)

This adds the always-on identifier (the dot). The fade is Task 4.

- [ ] **Step 1: Add `isNew` to the view model**

In `PostDetailCommentViewModel.swift`:

(a) Add the stored property near `isCollapsed` (around line 67):
```swift
    /// `true` when this comment is new since the user's last visit. Drives the
    /// gutter dot and the fresh-wash treatment.
    let isNew: Bool
```

(b) Add an `isNew` parameter to `init` (default `false`, so existing call sites and tests compile). Add it after `isBlockedRevealed`:
```swift
        isBlockedRevealed: Bool = false,
        isNew: Bool = false
    ) {
```
and assign it at the top of the body (next to `isDistinguished = distinguished`):
```swift
        self.isNew = isNew
```

- [ ] **Step 2: Add the gutter dot to the cell**

In `PostDetailCommentCell.swift`:

(a) Add the dot view (after `tintBackingView`):
```swift
    /// A small persistent dot at the leading edge of the header line marking a
    /// comment as new since the user's last visit. Decorative (VoiceOver gets a
    /// spoken hint instead).
    lazy var newDotView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 7),
            view.heightAnchor.constraint(equalToConstant: 7),
        ])
        view.layer.cornerRadius = 3.5
        return view
    }()
```

(b) Insert it as the first arranged subview of `headerStackView` (before `authorLabel`). In the `headerStackView` lazy initializer, change the `subviews` array to lead with the dot, and give it trailing spacing:
```swift
        let subviews = [
            newDotView,
            authorLabel,
            badgesStackView,
            subtitleLabel,
            spacerView,
            collapsedBadgeLabel,
        ]
        for view in subviews {
            stackView.addArrangedSubview(view)
        }

        stackView.setCustomSpacing(6, after: newDotView)
        stackView.setCustomSpacing(6, after: authorLabel)
        stackView.setCustomSpacing(6, after: badgesStackView)
```

(c) In `configure(with:imageService:)`, after the badges block and near the tint logic, drive the dot from `viewModel.isNew` (use the resolved `accent`):
```swift
        newDotView.isHidden = !viewModel.isNew
        newDotView.backgroundColor = viewModel.isNew ? accent : .clear
```

(d) In `prepareForReuse()`, reset it:
```swift
        newDotView.isHidden = true
        newDotView.backgroundColor = .clear
```

- [ ] **Step 3: Pass `isNew` from the host VC**

In `PostDetailViewController.swift`, in the cell provider's `.comment(elementId)` case (line ~1393), add `isNew` to the `PostDetailCommentViewModel(...)` construction:
```swift
                let viewModel = PostDetailCommentViewModel(
                    row: row,
                    appearance: appearance,
                    postCreatorPersonId: self?.headerRow?.creatorPersonId,
                    isCollapsed: isCollapsed,
                    collapsedDescendantCount: collapsedCount,
                    isBlockedRevealed: isBlockedRevealed,
                    isNew: self?.viewModel.isNewComment(elementId: elementId) ?? false
                )
```

- [ ] **Step 4: Add a snapshot case for the dot**

In `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift`, add a test that renders a comment with `isNew: true` (follow the file's existing pattern for constructing a `PostDetailCommentViewModel` + `PostDetailCommentCell` and snapshotting; reuse its existing row/view-model factory, passing `isNew: true`). Name it `test_new_dark` / `test_new_light` to match the file's light/dark convention.

- [ ] **Step 5: Build, record snapshot, verify**

Run `make project`, then the snapshot command from the header (first run records the new ref + fails, rerun verifies PASS), then the app unit build:
`python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17"`.
Expected: app builds; existing tests green; the new snapshot ref recorded and passing on rerun.

- [ ] **Step 6: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift SpudSnapshotTests/PostDetailCommentSnapshotTests.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift SpudSnapshotTests/PostDetailCommentSnapshotTests.swift
# stage the newly recorded snapshot refs too (git status -uall to find them under __Snapshots__/PostDetailCommentSnapshotTests/)
git add SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/test_new_*.png
git commit -m "feat: mark new comments with a persistent gutter dot"
```

---

## Task 4: Fresh wash + one-time fade

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (add `willDisplay`, `animatedNewCommentIds`)

No isolated unit test (Core Animation timing). The decision logic is `FreshWashState` (Task 2, tested); the static end-state is covered by a snapshot. Verified by build + manual scroll.

- [ ] **Step 1: Add the wash methods to the cell**

In `PostDetailCommentCell.swift`:

(a) Store the fresh/resting colors during `configure`. Add stored properties:
```swift
    /// The row's non-fresh resting wash color (clear, or the distinguished /
    /// collapsed tint), captured in `configure` so the fade lands on the right
    /// background instead of always clearing to transparent.
    private var restingTintColor: UIColor = .clear
    /// The fresh-comment tint, captured in `configure` from the resolved accent.
    private var freshTintColor: UIColor = .clear
    private var isFresh = false
```

(b) In `configure(with:imageService:)`, replace the existing tint block so it records the resting color (and the existing distinguished/collapsed behavior is preserved):
```swift
        if viewModel.isDistinguished {
            restingTintColor = accent.withAlphaComponent(0.10)
        } else if viewModel.isCollapsed {
            restingTintColor = UIColor.label.withAlphaComponent(0.03)
        } else {
            restingTintColor = .clear
        }
        isFresh = viewModel.isNew
        freshTintColor = accent.withAlphaComponent(
            traitCollection.userInterfaceStyle == .dark ? 0.16 : 0.11
        )
        // Resting state by default; the host re-applies the fresh wash in
        // willDisplay (so the one-time fade can run as the row appears).
        tintBackingView.layer.removeAnimation(forKey: "freshFade")
        tintBackingView.backgroundColor = restingTintColor
```

(c) Add the wash entry point + the fade:
```swift
    /// Applies the fresh-comment wash for this appearance. Returns `true` if it
    /// started the one-time fade (so the host can record that this comment has
    /// animated and not replay it).
    @discardableResult
    func startFreshWashIfNeeded(hasAnimated: Bool) -> Bool {
        let state = FreshWashState.resolve(
            isNew: isFresh,
            hasAnimated: hasAnimated,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )
        switch state {
        case .none:
            tintBackingView.layer.removeAnimation(forKey: "freshFade")
            tintBackingView.backgroundColor = restingTintColor
            return false
        case .staticTint:
            tintBackingView.layer.removeAnimation(forKey: "freshFade")
            tintBackingView.backgroundColor = freshTintColor
            return false
        case .fadeFromTint:
            playFreshFade()
            return true
        }
    }

    /// Holds the fresh tint, then fades to the resting background — the design's
    /// spudFreshFade (hold to 38%, fade to 100% over 4.2s, ease-out).
    private func playFreshFade() {
        let resting = restingTintColor.cgColor
        let fresh = freshTintColor.cgColor
        tintBackingView.backgroundColor = restingTintColor // model layer = end state

        let animation = CAKeyframeAnimation(keyPath: "backgroundColor")
        animation.values = [fresh, fresh, resting]
        animation.keyTimes = [0, 0.38, 1.0]
        animation.duration = 4.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        tintBackingView.layer.add(animation, forKey: "freshFade")
    }
```

(d) In `prepareForReuse()`, also clear the animation/flags:
```swift
        tintBackingView.layer.removeAnimation(forKey: "freshFade")
        isFresh = false
        restingTintColor = .clear
        freshTintColor = .clear
```

- [ ] **Step 2: Add the `willDisplay` hook + tracking in the VC**

In `PostDetailViewController.swift`:

(a) Add the per-visit tracking set (near the other comment state, e.g. by `commentRowsByElementId`):
```swift
    /// Element ids of new comments whose one-time fresh-wash fade has already
    /// played this visit, so scrolling them back into view doesn't replay it.
    private var animatedNewCommentIds: Set<Int64> = []
```

(b) In the `UITableViewDelegate` extension (next to `scrollViewDidScroll`), add:
```swift
    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        guard
            case let .comment(elementId) = dataSource.itemIdentifier(for: indexPath),
            let cell = cell as? PostDetailCommentCell
        else { return }
        let didAnimate = cell.startFreshWashIfNeeded(
            hasAnimated: animatedNewCommentIds.contains(elementId)
        )
        if didAnimate {
            animatedNewCommentIds.insert(elementId)
        }
    }
```

- [ ] **Step 3: Build + manual check**

Run `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17"`. Expected: builds; unit + snapshot plan green. Manual (with a thread that has new comments — see the `lemmy-test-instances` notes, or temporarily seed by leaving + revisiting a post): new comments appear teal-washed, fade to normal within ~4s, leave the dot; scrolling away/back does not replay; reduce-motion shows a static wash.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: fade a fresh teal wash on new comments once per visit"
```

---

## Task 5: "N new since your last visit" banner

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/PostDetailNewSinceBannerCell.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (Item enum, cell registration + provider, `applySnapshot`, jump-to-first-new)

No isolated unit test (UIKit cell + diffable wiring); build + manual.

- [ ] **Step 1: Create the banner cell**

`Spud/Scenes/PostDetail/Content/PostDetailNewSinceBannerCell.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// In-flow band above the comment list: "N new since your last visit · {time}"
/// with a trailing "Jump" control that scrolls to the first new comment.
final class PostDetailNewSinceBannerCell: UITableViewCell {
    static let reuseIdentifier = "PostDetailNewSinceBannerCell"

    var jumpTapped: (() -> Void)?

    private let dotView = UIView()
    private let messageLabel = UILabel()
    private let jumpButton = UIButton(type: .system)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.layer.cornerRadius = 3.5
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),
        ])

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0

        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Jump", comment: "Jump to the first new comment")
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 3
        config.contentInsets = .zero
        jumpButton.configuration = config
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.setContentHuggingPriority(.required, for: .horizontal)
        jumpButton.addTarget(self, action: #selector(didTapJump), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [dotView, messageLabel, jumpButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 9
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        jumpTapped = nil
    }

    /// `accent` is the resolved app accent; `count` is the number of new comments;
    /// `relativeText` is e.g. "2 hours ago" (may be nil).
    func configure(count: Int, relativeText: String?, accent: UIColor) {
        dotView.backgroundColor = accent
        contentView.backgroundColor = accent.withAlphaComponent(
            traitCollection.userInterfaceStyle == .dark ? 0.16 : 0.11
        )
        jumpButton.tintColor = accent

        let countText = String(
            format: NSLocalizedString("%lld new", comment: "Count of new comments since last visit"),
            count
        )
        let suffix: String = {
            guard let relativeText else {
                return NSLocalizedString(" since your last visit", comment: "New-comments banner suffix without a time")
            }
            return String(
                format: NSLocalizedString(" since your last visit · %@", comment: "New-comments banner suffix with a relative time"),
                relativeText
            )
        }()
        let attr = NSMutableAttributedString(
            string: countText,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline).bold(), .foregroundColor: accent]
        )
        attr.append(NSAttributedString(
            string: suffix,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.label]
        ))
        messageLabel.attributedText = attr

        isAccessibilityElement = true
        accessibilityLabel = countText + suffix
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("Scrolls to the first new comment", comment: "VoiceOver hint for the new-comments banner")
    }

    @objc private func didTapJump() { jumpTapped?() }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
```

- [ ] **Step 2: Wire the banner into the diffable data source**

In `PostDetailViewController.swift`:

(a) Extend the `Item` enum (line 1316):
```swift
    enum Item: Hashable {
        case header
        case newSinceBanner
        case comment(elementId: Int64)
    }
```

(b) Register the cell in the `tableView` lazy initializer (next to the other `register` calls, ~line 96):
```swift
        tableView.register(PostDetailNewSinceBannerCell.self, forCellReuseIdentifier: PostDetailNewSinceBannerCell.reuseIdentifier)
```

(c) In the cell provider `switch item` (line 1330), add a case (place it before `.comment`):
```swift
            case .newSinceBanner:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PostDetailNewSinceBannerCell.reuseIdentifier,
                    for: indexPath
                ) as! PostDetailNewSinceBannerCell
                let accent = self?.tableView.tintColor ?? .systemTeal
                cell.configure(
                    count: self?.viewModel.newCommentCount ?? 0,
                    relativeText: self?.viewModel.previousVisitAt?.relativeString,
                    accent: accent
                )
                cell.jumpTapped = { [weak self] in self?.jumpToFirstNewComment() }
                return cell
```

(d) In `applySnapshot` (line 414), append the banner item to the `.header` section when there are new comments, after `.header`:
```swift
        snapshot.appendSections([.header, .comments])
        snapshot.appendItems([.header], toSection: .header)
        if viewModel.newCommentCount > 0 {
            snapshot.appendItems([.newSinceBanner], toSection: .header)
            snapshot.reconfigureItems([.newSinceBanner])
        }
        snapshot.reconfigureItems([.header])
```

(e) Add the jump-to-first-new method (next to the existing jump methods, ~line 507):
```swift
    /// Scrolls to the first new comment (the banner's "Jump" action).
    private func jumpToFirstNewComment() {
        guard
            let elementId = viewModel.firstNewCommentElementId,
            let indexPath = dataSource.indexPath(for: .comment(elementId: elementId))
        else { return }
        Haptics.tap()
        tableView.scrollToRow(at: indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }
```

(Confirm `Date.relativeString` exists — `PostDetailCommentViewModel` uses `published.relativeString` at line 366, so it's available. If the accessor differs, match that usage.)

- [ ] **Step 3: Build + manual**

`python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17"`. Expected: builds; tests green. Manual: revisiting a post with new comments shows the banner; tapping "Jump" scrolls to the first new comment; no banner when there are no new comments.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailNewSinceBannerCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailNewSinceBannerCell.swift Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: add new-since-last-visit comment banner with jump"
```

---

## Task 6: "Next new" jump pill (extend the existing FAB)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`

The VC already has a "jump to next top-level comment" FAB (`jumpToNextButton`, `indexPathOfNextTopLevelComment`, `jumpToNextTopCommentTapped`, `updateJumpButtonVisibility`, refreshed from `scrollViewDidScroll`). Extend it: while there are new comments, it targets the next NEW comment below the viewport and reads "Next new"; otherwise it keeps its existing behavior. No isolated unit test (geometric, like the existing FAB); build + manual.

- [ ] **Step 1: Add the next-new index-path finder**

Next to `indexPathOfNextTopLevelComment()` (line 481), add the new-comment analogue:
```swift
    /// The index path of the next new comment whose top is below the current
    /// content offset (plus the top inset). Iterates the new comments in display
    /// order (`orderedNewCommentElementIds`, Task 1), skipping any that are
    /// currently collapsed away (no index path). Returns nil if none below.
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

    /// In "prefer new" mode (there are new comments) the FAB targets the next new
    /// comment; otherwise the next top-level comment. Returns the target + whether
    /// it is a new-comment target (for styling).
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

- [ ] **Step 2: Route the tap and visibility through `jumpTarget()`**

Replace `jumpToNextTopCommentTapped()` body (line 503) to use the combined target:
```swift
    @objc
    private func jumpToNextTopCommentTapped() {
        guard let target = jumpTarget() else { return }
        Haptics.tap()
        tableView.scrollToRow(at: target.indexPath, at: .top, animated: !UIAccessibility.isReduceMotionEnabled)
    }
```

In `updateJumpButtonVisibility()` (line 511), compute from `jumpTarget()` and restyle for the new-comment case:
```swift
    private func updateJumpButtonVisibility() {
        let target = jumpTarget()
        let shouldShow = target != nil

        // Restyle for "Next new" vs the default next-top-level affordance.
        applyJumpButtonStyle(isNew: target?.isNew ?? false)

        guard shouldShow != (jumpToNextButton.alpha > 0) else { return }
        if shouldShow { jumpToNextButton.isHidden = false }
        let animate = !UIAccessibility.isReduceMotionEnabled
        let work = { self.jumpToNextButton.alpha = shouldShow ? 1 : 0 }
        let completion = { (_: Bool) in
            if !shouldShow { self.jumpToNextButton.isHidden = true }
        }
        if animate {
            UIView.animate(withDuration: 0.2, animations: work, completion: completion)
        } else {
            work()
            completion(true)
        }
    }

    /// Styles the jump FAB: accent "Next new" label when there are new comments to
    /// jump to, else the default next-top-level chevron.
    private func applyJumpButtonStyle(isNew: Bool) {
        let accent = tableView.tintColor ?? .systemTeal
        if isNew {
            jumpToNextButton.setTitle(NSLocalizedString("Next new", comment: "Jump to the next new comment"), for: .normal)
            jumpToNextButton.accessibilityLabel = NSLocalizedString("Next new comment", comment: "VoiceOver: jump to the next new comment")
            jumpToNextButton.backgroundColor = accent
        } else {
            applyDefaultJumpButtonStyle()
        }
    }
```

> The FAB's existing construction (title/icon/background) lives in its lazy initializer. Extract that styling into a `applyDefaultJumpButtonStyle()` method and call it from both the initializer and `applyJumpButtonStyle(isNew:)` above, so the default look has a single source. Read the `jumpToNextButton` lazy var to see its exact current configuration (icon, colors, corner radius) and move it verbatim into `applyDefaultJumpButtonStyle()`. If the FAB shows only an icon (no title), `setTitle` may require switching it to a title+image configuration — match the button's existing API (UIButton.Configuration vs target-action) when adding the "Next new" label.

- [ ] **Step 3: Build + manual**

`python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17"`. Expected: builds; tests green. Manual: with new comments below, the FAB reads "Next new" (accent) and steps through them; once past all new comments (or none exist) it reverts to the next-top-level behavior; hidden when there's nothing below.

- [ ] **Step 4: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: jump FAB steps through new comments when present"
```

---

## Task 7: VoiceOver for new comments

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift` (append to `subtitleAccessibilityLabel`)

- [ ] **Step 1: Add a failing test**

Append to `SpudTests` (a new `PostDetailCommentViewModelAccessibilityTests.swift` or the nearest existing comment-VM test file). Construct a `PostDetailCommentViewModel` from a `PostDetailCommentRow` (follow the snapshot tests' row factory) with `isNew: true` and assert the spoken metadata includes the new-comment phrase:

```swift
    func testIsNewAddsVoiceOverPhrase() {
        let vm = PostDetailCommentViewModel(row: sampleRow(), appearance: FakeAppearance(), isNew: true)
        XCTAssertTrue((vm.subtitleAccessibilityLabel ?? "").contains("New comment"))
    }
```

(Use whatever appearance fake / row factory the existing comment-VM or snapshot tests use; the assertion is the contract.)

- [ ] **Step 2: Run it; expect FAIL** (phrase absent).

- [ ] **Step 3: Implement**

In `PostDetailCommentViewModel.swift`, in the non-`isMore` accessibility branch (where `pieces` is assembled, around line 343-399), append the new-comment phrase before `subtitleAccessibilityLabel = pieces.joined(...)`:
```swift
            if isNew {
                pieces.append(NSLocalizedString(
                    "New comment, posted after your last visit",
                    comment: "VoiceOver: comment is new since the user's last visit"
                ))
            }
```

- [ ] **Step 4: Run it; expect PASS.**

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift SpudTests/<the test file>
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift SpudTests/<the test file>
git commit -m "feat: announce new comments to VoiceOver"
```

---

## Self-review notes

- **Resting color & fade:** the fade always lands on `restingTintColor` (clear, or distinguished/collapsed tint), so a new+distinguished comment settles to its teal bar tint, never erasing it.
- **Once-per-visit:** the VC's `animatedNewCommentIds` gates the fade; `willDisplay` fires for initially-visible cells (first display) and for cells scrolled into view, but not for in-place `reconfigureItems` — which is correct, since reconfigure happens on votes/collapse after the fade already played.
- **Banner placement:** in the `.header` section (in-flow, scrolls away), shown only when `newCommentCount > 0`.
- **FAB:** reuses the existing jump infrastructure (position, show/hide, `scrollViewDidScroll`), preferring new comments when present.

## Done criteria

- New comments show a teal wash that fades to the resting background once per visit (static under reduce-motion), plus a persistent gutter dot.
- A "N new since your last visit · {time}" banner appears above the comments when there are new ones; "Jump" scrolls to the first new comment.
- The jump FAB steps through new comments when present.
- New comments are announced to VoiceOver.
- `FreshWashState`, `orderedNewCommentElementIds`, and the existing `NewCommentState` are unit-tested; the dot has a snapshot; the app builds and the unit/snapshot plan is green.

## Out of scope

- Collapsed-parent "N new" count badge (deferred follow-up; the banner already totals new comments).
- Changing how "new" is computed (Phase 1 owns it). Push notifications (dropped).
