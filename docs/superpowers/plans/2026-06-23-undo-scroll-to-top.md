# Undo accidental scroll-to-top — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a status-bar tap scrolls the post list to the top from deep in the feed, offer a one-tap undo (toast button or a second status-bar tap) that instantly snaps back to where the user was, pulses the row they were reading, and confirms with a toast.

**Architecture:** A UIKit-free `ScrollToTopUndo` value type holds the decision/state machine (arm-on-deep-jump, toggle, invalidate) and is unit-tested in isolation. `ToastPresenter` gains an interactive (action-button) toast variant plus an explicit `dismiss()`. `PostListViewController` wires the two `UIScrollView` scroll-to-top delegate methods (plus `scrollViewWillBeginDragging`) to the reducer, performs the instant restore, and flashes the anchored cell via a small reusable `pulseHighlight()` helper.

**Tech Stack:** Swift 6, UIKit, GRDB-backed diffable data source (`UITableViewDiffableDataSource<Section, Item>`), XCTest, pointfreeco swift-snapshot-testing.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-06-23-undo-scroll-to-top-design.md`.
- **Scope:** `PostListViewController` + `ToastPresenter` + two new small files. No view-model or data-layer changes.
- **Toast copy (verbatim):** undo hint title `"Jumped to top"`, action title `"Undo"`, confirmation `"Back to where you were"`. All via `NSLocalizedString` with a comment.
- **Undo-hint toast duration:** `.seconds(4)`. Plain/confirmation toast stays `.seconds(2)` (existing default).
- **Arm threshold:** only arm undo when the pre-jump `contentOffset.y >= tableView.bounds.height` (≈ one screen).
- **Restore:** instant — `setContentOffset(_:animated: false)`. Never animated.
- **Pulse:** accent-tinted translucent overlay, ~0.6s ease-out (0.3s under Reduce Motion), self-removing.
- **New files require XcodeGen:** after creating any `.swift` file run `make project` before building/testing, or the generated `Spud.xcodeproj` won't include it.
- **No emojis** in code/comments/commits. SwiftFormat (`.swiftformat`) is authoritative — format before staging (`mint run swiftformat <paths>`).
- **Commits:** conventional subjects (`feat:` / `test:`), end every commit message with the standard trailers:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP
  ```
- **Working dir:** `/Users/denis/dev/info.ddenis/Spud/Spud`. Branch: `feat/undo-scroll-to-top`.
- **Simulators:** unit tests on `iPhone 17 Pro`; snapshot tests on `iPhone 14 Pro` (portrait), per project convention. `xcodebuild` needs `-skipPackagePluginValidation -skipMacroValidation`.

---

### Task 1: `ScrollToTopUndo` reducer (pure state machine) + unit tests

The whole decision/state machine, UIKit-free so it is unit-testable without a view controller. Models: arm-on-deep-jump, toggle re-tap, take-undo, invalidate. Follows the existing `ForwardStackReducer` / `SeenDwellTracker` pattern (pure type in `Spud/Scenes/PostList/`, XCTest in `SpudTests/`).

**Files:**
- Create: `Spud/Scenes/PostList/ScrollToTopUndo.swift`
- Test: `SpudTests/ScrollToTopUndoTests.swift`

**Interfaces:**
- Consumes: nothing (leaf type; `CGPoint`/`Int64` only).
- Produces (relied on by Task 3):
  - `struct ScrollToTopUndo`
  - `ScrollToTopUndo.Pending` — `struct { var offset: CGPoint; var anchorServerPostId: Int64 }`, `Equatable`
  - `ScrollToTopUndo.TapResponse` — `enum { case allowScrollToTop; case undo }`, `Equatable`
  - `private(set) var pending: ScrollToTopUndo.Pending?`
  - `mutating func statusBarTapped(currentOffset: CGPoint, topVisibleServerPostId: Int64?) -> TapResponse`
  - `mutating func scrolledToTop(viewportHeight: CGFloat) -> Pending?`
  - `mutating func takeUndo() -> Pending?`
  - `mutating func invalidate()`

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/ScrollToTopUndoTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class ScrollToTopUndoTests: XCTestCase {
    private let viewport: CGFloat = 800

    // Arming

    func test_deepScrollToTop_armsUndo_andReturnsPending() {
        var sut = ScrollToTopUndo()
        let response = sut.statusBarTapped(
            currentOffset: CGPoint(x: 0, y: 2400),
            topVisibleServerPostId: 42
        )
        XCTAssertEqual(response, .allowScrollToTop)
        XCTAssertNil(sut.pending, "Not armed until the scroll actually completes")

        let armed = sut.scrolledToTop(viewportHeight: viewport)
        XCTAssertEqual(armed, ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 2400), anchorServerPostId: 42))
        XCTAssertEqual(sut.pending, armed)
    }

    func test_shallowScrollToTop_doesNotArm() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 200), topVisibleServerPostId: 7)
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport))
        XCTAssertNil(sut.pending)
    }

    func test_threshold_isInclusiveOfOneViewport() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: viewport), topVisibleServerPostId: 1)
        XCTAssertNotNil(sut.scrolledToTop(viewportHeight: viewport), "offset.y == viewport arms")

        var below = ScrollToTopUndo()
        _ = below.statusBarTapped(currentOffset: CGPoint(x: 0, y: viewport - 1), topVisibleServerPostId: 1)
        XCTAssertNil(below.scrolledToTop(viewportHeight: viewport), "just under one viewport stays silent")
    }

    func test_noVisiblePost_doesNotArm() {
        var sut = ScrollToTopUndo()
        let response = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 3000), topVisibleServerPostId: nil)
        XCTAssertEqual(response, .allowScrollToTop)
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport))
    }

    // Toggle

    func test_secondTap_whileArmed_returnsUndo_withoutRecapturing() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        let response = sut.statusBarTapped(currentOffset: .zero, topVisibleServerPostId: 99)
        XCTAssertEqual(response, .undo)
        XCTAssertEqual(sut.pending?.anchorServerPostId, 42, "toggle keeps the original anchor, not the re-tap")
    }

    // Take undo

    func test_takeUndo_returnsPendingThenClears() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        XCTAssertEqual(sut.takeUndo(), ScrollToTopUndo.Pending(offset: CGPoint(x: 0, y: 2400), anchorServerPostId: 42))
        XCTAssertNil(sut.pending)
        XCTAssertNil(sut.takeUndo(), "second take is empty")
    }

    func test_afterUndo_nextTapAllowsScrollToTopAgain() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)
        _ = sut.takeUndo()

        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 1500), topVisibleServerPostId: 5),
            .allowScrollToTop
        )
    }

    // Invalidate

    func test_invalidate_clearsArmedUndo() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        _ = sut.scrolledToTop(viewportHeight: viewport)

        sut.invalidate()
        XCTAssertNil(sut.pending)
        XCTAssertEqual(
            sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42),
            .allowScrollToTop,
            "after invalidate a tap is a fresh scroll-to-top, not a toggle"
        )
    }

    func test_invalidate_clearsPendingCandidateBeforePromotion() {
        var sut = ScrollToTopUndo()
        _ = sut.statusBarTapped(currentOffset: CGPoint(x: 0, y: 2400), topVisibleServerPostId: 42)
        sut.invalidate()
        XCTAssertNil(sut.scrolledToTop(viewportHeight: viewport), "an invalidated candidate cannot promote")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail (no type yet)**

Run:
```sh
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/ScrollToTopUndoTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build/compile failure — `cannot find 'ScrollToTopUndo' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/PostList/ScrollToTopUndo.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics

/// Pure state machine for the post list's "undo accidental scroll-to-top".
///
/// A status-bar tap scrolls the feed to the top. When that happens from deep in
/// the feed it is usually accidental, so we offer a one-tap undo that snaps back
/// to the prior position. The capability lives here, independent of any toast,
/// so a second status-bar tap (a toggle) still undoes even after the hint toast
/// has expired - until the user manually scrolls or the feed changes.
///
/// UIKit-free (operates on `CGPoint` / `Int64` only) so the decision logic is
/// unit-testable without a view controller.
struct ScrollToTopUndo {
    /// A captured place to return to: the exact content offset plus the server
    /// post id of the row to pulse on restore.
    struct Pending: Equatable {
        var offset: CGPoint
        var anchorServerPostId: Int64
    }

    /// What the view controller should do in response to a status-bar tap.
    enum TapResponse: Equatable {
        /// No undo armed: record a candidate and let iOS scroll to the top
        /// (return `true` from `scrollViewShouldScrollToTop`).
        case allowScrollToTop
        /// An undo is armed and we are at the top: consume the tap (return
        /// `false`) and perform the undo instead.
        case undo
    }

    /// The armed undo, surviving until the user moves on. `nil` when nothing is
    /// armed. Readable by the view controller to gate toast dismissal.
    private(set) var pending: Pending?

    /// The pre-jump position recorded between `statusBarTapped` and
    /// `scrolledToTop`, promoted to `pending` only if the jump was deep enough.
    private var candidate: Pending?

    /// Intercepts a status-bar tap (from `scrollViewShouldScrollToTop`).
    /// Returns `.undo` when an undo is already armed (toggle back); otherwise
    /// records the current position as a candidate and returns `.allowScrollToTop`.
    mutating func statusBarTapped(
        currentOffset: CGPoint,
        topVisibleServerPostId: Int64?
    ) -> TapResponse {
        if pending != nil {
            return .undo
        }
        candidate = topVisibleServerPostId.map {
            Pending(offset: currentOffset, anchorServerPostId: $0)
        }
        return .allowScrollToTop
    }

    /// Called from `scrollViewDidScrollToTop` after iOS finished scrolling.
    /// Promotes the candidate to an armed undo when the pre-jump offset was at
    /// least `viewportHeight` deep (about one screen). Returns the armed
    /// `Pending` (show the undo toast) or `nil` (stay silent).
    mutating func scrolledToTop(viewportHeight: CGFloat) -> Pending? {
        defer { candidate = nil }
        guard let candidate, candidate.offset.y >= viewportHeight else {
            return nil
        }
        pending = candidate
        return candidate
    }

    /// Consumes the armed undo (toast button or toggle re-tap). Returns the
    /// `Pending` to restore, or `nil` if nothing is armed.
    mutating func takeUndo() -> Pending? {
        defer { pending = nil }
        return pending
    }

    /// Drops any armed/candidate undo - the user manually scrolled or the feed
    /// changed, so the saved position is stale.
    mutating func invalidate() {
        pending = nil
        candidate = nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the same `xcodebuild ... -only-testing:SpudTests/ScrollToTopUndoTests ... test` command from Step 2.
Expected: all `ScrollToTopUndoTests` PASS.

- [ ] **Step 5: Format and commit**

```sh
mint run swiftformat Spud/Scenes/PostList/ScrollToTopUndo.swift SpudTests/ScrollToTopUndoTests.swift
git add Spud/Scenes/PostList/ScrollToTopUndo.swift SpudTests/ScrollToTopUndoTests.swift
git commit -m "feat: add ScrollToTopUndo state machine for post list

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

---

### Task 2: `ToastPresenter` interactive (action-button) variant + `dismiss()` + snapshots

Extend the toast so it can host a trailing "Undo" button and be dismissed on demand, while keeping the existing plain text toast unchanged for the confirmation and refresh-failure toasts. `ToastView` becomes `internal` (from `private`) so it can be snapshot-tested. Because the toast is a content-sized pill pinned near the bottom (not a full-screen overlay), making it interactive only intercepts touches on the pill itself; touches elsewhere pass through naturally — no custom hit-testing overlay is required.

**Files:**
- Modify: `Spud/Scenes/Common/Toast/ToastPresenter.swift` (full rewrite below)
- Test: `SpudSnapshotTests/ToastSnapshotTests.swift` (create)

**Interfaces:**
- Consumes: `ThemeManager.currentAccentColor` (SpudUIKit).
- Produces (relied on by Task 3):
  - `func show(_ message: String, in window: UIWindow)` — unchanged (plain, ~2s, coalesces).
  - `func show(_ message: String, actionTitle: String, in window: UIWindow, duration: Duration = .seconds(4), action: @escaping @MainActor () -> Void)` — interactive.
  - `func dismiss()` — animate out + remove the current toast now.
  - `final class ToastView` (internal) with `let messageLabel: UILabel`, `let isInteractive: Bool`, `init(message:actionTitle:action:)`.

- [ ] **Step 1: Write the failing snapshot tests**

Create `SpudSnapshotTests/ToastSnapshotTests.swift`:

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

/// Snapshots of the toast pill in both forms: plain text (confirmation /
/// failure toasts) and with a trailing accent "Undo" button. Rendered on a
/// fixed-size, pinned-scale host so references are device-independent.
@MainActor
final class ToastSnapshotTests: XCTestCase {
    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func host(_ toast: ToastView, height: CGFloat) -> UIView {
        let size = CGSize(width: width, height: height)
        let container = UIView(frame: CGRect(origin: .zero, size: size))
        container.backgroundColor = .systemBackground
        toast.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])
        container.layoutIfNeeded()
        return container
    }

    func test_plainToast_light() { assertPlain(style: .light) }
    func test_plainToast_dark() { assertPlain(style: .dark) }
    func test_undoToast_light() { assertUndo(style: .light) }
    func test_undoToast_dark() { assertUndo(style: .dark) }

    private func assertPlain(style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = host(ToastView(message: "Back to where you were"), height: 96)
        assertSnapshot(
            matching: view, as: .image(size: view.bounds.size, traits: traits(style)),
            named: style == .dark ? "dark" : "light", testName: testName, line: line
        )
    }

    private func assertUndo(style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = host(ToastView(message: "Jumped to top", actionTitle: "Undo", action: {}), height: 96)
        assertSnapshot(
            matching: view, as: .image(size: view.bounds.size, traits: traits(style)),
            named: style == .dark ? "dark" : "light", testName: testName, line: line
        )
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```sh
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/ToastSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: compile failure — `ToastView` is `private` (not visible) and the `actionTitle:` initializer does not exist yet.

- [ ] **Step 3: Rewrite `ToastPresenter.swift`**

Replace the entire contents of `Spud/Scenes/Common/Toast/ToastPresenter.swift` with:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// Presents a transient, non-blocking "pill" toast near the bottom of a window.
///
/// Two forms:
/// - Plain text (`show(_:in:)`): non-interactive, ~2s, coalesces by updating the
///   text of an existing plain toast and resetting its timer.
/// - Interactive (`show(_:actionTitle:in:duration:action:)`): adds a trailing
///   accent action button (e.g. "Undo"); the pill is content-sized, so only it
///   intercepts touches - the rest of the screen stays usable. Replaces any
///   existing toast rather than coalescing.
///
/// `dismiss()` animates the current toast out immediately.
@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private init() { }

    // MARK: - State

    private weak var currentToast: ToastView?
    private var dismissTask: Task<Void, Never>?

    // MARK: - Public

    func show(_ message: String, in window: UIWindow) {
        if let existing = currentToast, !existing.isInteractive {
            existing.messageLabel.text = message
            scheduleDismiss(for: existing, after: .seconds(2))
            return
        }
        present(ToastView(message: message), in: window, duration: .seconds(2))
    }

    func show(
        _ message: String,
        actionTitle: String,
        in window: UIWindow,
        duration: Duration = .seconds(4),
        action: @escaping @MainActor () -> Void
    ) {
        let toast = ToastView(message: message, actionTitle: actionTitle) { [weak self] in
            action()
            self?.dismiss()
        }
        present(toast, in: window, duration: duration)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let toast = currentToast else { return }
        currentToast = nil
        animateOut(toast)
    }

    // MARK: - Private

    private func present(_ toast: ToastView, in window: UIWindow, duration: Duration) {
        // Replace any existing toast outright (covers plain <-> interactive swaps).
        if let existing = currentToast {
            dismissTask?.cancel()
            dismissTask = nil
            existing.removeFromSuperview()
            currentToast = nil
        }

        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: 12)
        window.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            toast.bottomAnchor.constraint(
                equalTo: window.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            toast.leadingAnchor.constraint(
                greaterThanOrEqualTo: window.leadingAnchor,
                constant: 16
            ),
            toast.trailingAnchor.constraint(
                lessThanOrEqualTo: window.trailingAnchor,
                constant: -16
            ),
        ])

        currentToast = toast

        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            toast.alpha = 1
            toast.transform = .identity
        }

        scheduleDismiss(for: toast, after: duration)
    }

    private func scheduleDismiss(for toast: ToastView, after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self, weak toast] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, let toast else { return }
            currentToast = nil
            dismissTask = nil
            animateOut(toast)
        }
    }

    private func animateOut(_ toast: ToastView) {
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseIn) {
            toast.alpha = 0
            toast.transform = CGAffineTransform(translationX: 0, y: 8)
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

// MARK: - ToastView

final class ToastView: UIView {
    let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        return label
    }()

    /// True when the toast hosts an action button (and is interactive).
    let isInteractive: Bool

    init(
        message: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        isInteractive = actionTitle != nil && action != nil
        super.init(frame: .zero)
        messageLabel.text = message

        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.cgColor

        if let actionTitle, let action {
            isUserInteractionEnabled = true
            messageLabel.textAlignment = .natural

            var config = UIButton.Configuration.plain()
            config.title = actionTitle
            config.baseForegroundColor = ThemeManager.currentAccentColor
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)

            let stack = UIStackView(arrangedSubviews: [messageLabel, button])
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = 12
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            ])
        } else {
            isUserInteractionEnabled = false
            messageLabel.textAlignment = .center
            addSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
                messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 4: Record then verify the snapshots**

First run records the new reference PNGs and reports failure; the second run verifies. (Snapshot refs are git-annex tracked — record/verify one class at a time, do not `git annex restage` between runs.)

```sh
cd /Users/denis/dev/info.ddenis/Spud/Spud
# Run 1: records refs, expected FAIL ("No reference image ... Recorded")
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/ToastSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
# Run 2: verifies against the recorded refs, expected PASS
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/ToastSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: Run 1 FAIL (recorded 4 PNGs), Run 2 PASS. Confirm 4 PNGs exist:
```sh
find SpudSnapshotTests/__Snapshots__/ToastSnapshotTests -name '*.png'
```
Expected: 4 files (plain/undo × light/dark).

- [ ] **Step 5: Format and commit**

```sh
mint run swiftformat Spud/Scenes/Common/Toast/ToastPresenter.swift SpudSnapshotTests/ToastSnapshotTests.swift
git add Spud/Scenes/Common/Toast/ToastPresenter.swift SpudSnapshotTests/ToastSnapshotTests.swift SpudSnapshotTests/__Snapshots__/ToastSnapshotTests
git commit -m "feat: add interactive (action-button) toast variant and dismiss()

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

---

### Task 3: Wire the post list — scroll-to-top delegates, restore, pulse, invalidation

Connect the reducer and toast to `PostListViewController`, add the reusable cell-pulse helper, and invalidate on manual scroll / feed change. This is UIKit glue with no new unit-testable logic (the logic lives in the Task 1 reducer); it is verified by a green build and the manual simulator checklist below — consistent with the pull-to-refresh feature's verification approach.

**Files:**
- Create: `Spud/Scenes/Common/CellPulseHighlight.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`
  - add `private var scrollUndo = ScrollToTopUndo()` near the other private state (after `:113` `dataSource` / the `seenDwellTracker` block ~`:117`)
  - new scroll-to-top delegate methods + helpers in the `UITableViewDelegate` extension (`:1415`)
  - invalidation calls in `feedChanged(keepingContent:)` (`:723`)

**Interfaces:**
- Consumes: `ScrollToTopUndo` (Task 1); `ToastPresenter.show(_:actionTitle:in:duration:action:)`, `.show(_:in:)`, `.dismiss()` (Task 2); `UIView.pulseHighlight(color:)` (this task); existing `dataSource: UITableViewDiffableDataSource<Section, Item>` and `Item.post(serverPostId:)`.
- Produces: nothing downstream.

- [ ] **Step 1: Create the pulse helper**

Create `Spud/Scenes/Common/CellPulseHighlight.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

extension UIView {
    /// Briefly flashes a translucent accent tint over the view, then removes it,
    /// to re-anchor the user's eye - e.g. after an undo snaps the feed back to
    /// where they were. Honours Reduce Motion by fading faster. The flash is an
    /// opacity fade (not motion), so it stays on under that setting.
    func pulseHighlight(color: UIColor = ThemeManager.currentAccentColor) {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = color.withAlphaComponent(0.22)
        overlay.isUserInteractionEnabled = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let duration = UIAccessibility.isReduceMotionEnabled ? 0.3 : 0.6
        UIView.animate(withDuration: duration, delay: 0.05, options: .curveEaseOut) {
            overlay.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }
}
```

- [ ] **Step 2: Add the undo state property**

In `PostListViewController.swift`, in the private-state block (right after the `seenDwellTracker` declaration, ~`:117`), add:

```swift
    /// Undo state for an accidental status-bar scroll-to-top. See
    /// `ScrollToTopUndo`; wired in the `UITableViewDelegate` extension below.
    private var scrollUndo = ScrollToTopUndo()
```

- [ ] **Step 3: Add the scroll-to-top delegate methods and helpers**

In the `extension PostListViewController: UITableViewDelegate` block (starts `:1415`), add these methods (place them right after the existing `scrollViewDidScroll(_:)`):

```swift
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        switch scrollUndo.statusBarTapped(
            currentOffset: scrollView.contentOffset,
            topVisibleServerPostId: topmostVisibleServerPostId()
        ) {
        case .undo:
            performScrollUndo()
            return false
        case .allowScrollToTop:
            return true
        }
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        guard scrollUndo.scrolledToTop(viewportHeight: scrollView.bounds.height) != nil else {
            return
        }
        showUndoScrollToast()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // A manual scroll means the user moved on - drop the armed undo (and its
        // hint toast). Only touch the toast when we actually had one armed.
        let wasArmed = scrollUndo.pending != nil
        scrollUndo.invalidate()
        if wasArmed {
            ToastPresenter.shared.dismiss()
        }
    }

    /// The server post id of the topmost currently-visible post row - the row to
    /// pulse on restore. `nil` when no post row is visible (e.g. only the loading
    /// footer), which suppresses the undo for that tap.
    private func topmostVisibleServerPostId() -> Int64? {
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            if case let .post(serverPostId)? = dataSource.itemIdentifier(for: indexPath) {
                return serverPostId
            }
        }
        return nil
    }

    private func showUndoScrollToast() {
        guard let window = view.window else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString(
                "Jumped to top",
                comment: "Accessibility announcement when a status-bar tap scrolled the feed to the top"
            )
        )
        ToastPresenter.shared.show(
            NSLocalizedString(
                "Jumped to top",
                comment: "Undo toast title shown after an accidental scroll-to-top"
            ),
            actionTitle: NSLocalizedString(
                "Undo",
                comment: "Undo button on the scroll-to-top toast"
            ),
            in: window,
            action: { [weak self] in self?.performScrollUndo() }
        )
    }

    /// Snaps instantly back to the saved position, pulses the anchored row, and
    /// confirms. Shared by the toast "Undo" button and the status-bar toggle.
    private func performScrollUndo() {
        guard let pending = scrollUndo.takeUndo() else { return }
        tableView.setContentOffset(pending.offset, animated: false)
        tableView.layoutIfNeeded()
        if let indexPath = dataSource.indexPath(for: .post(serverPostId: pending.anchorServerPostId)),
           let cell = tableView.cellForRow(at: indexPath) {
            cell.contentView.pulseHighlight()
        }
        if let window = view.window {
            ToastPresenter.shared.show(
                NSLocalizedString(
                    "Back to where you were",
                    comment: "Confirmation toast after undoing an accidental scroll-to-top"
                ),
                in: window
            )
        }
    }
```

- [ ] **Step 4: Invalidate on feed change**

In `feedChanged(keepingContent:)` (`:723`), at the very top of the method (before `viewModel.prepareForReload()`), add:

```swift
        // The saved scroll-undo position belongs to the prior feed; a feed swap
        // makes it stale. Drop it (and its hint toast) before reloading.
        let hadArmedUndo = scrollUndo.pending != nil
        scrollUndo.invalidate()
        if hadArmedUndo {
            ToastPresenter.shared.dismiss()
        }
```

(Pull-to-refresh routes through `feedChanged(keepingContent: true)`, so this covers refresh too.)

- [ ] **Step 5: Regenerate project and build**

```sh
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds. The only pre-existing warning is the benign `Duplicate -rpath '@executable_path'`; no new warnings or errors. If `build_and_test.py` reports errors, get details with its `--get-errors`.

- [ ] **Step 6: Run the full unit + snapshot test plans (regression)**

```sh
cd /Users/denis/dev/info.ddenis/Spud/Spud
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS (including `ScrollToTopUndoTests`).

- [ ] **Step 7: Format and commit**

```sh
mint run swiftformat Spud/Scenes/Common/CellPulseHighlight.swift Spud/Scenes/PostList/PostListViewController.swift
git add Spud/Scenes/Common/CellPulseHighlight.swift Spud/Scenes/PostList/PostListViewController.swift
git commit -m "feat: undo accidental status-bar scroll-to-top in post list

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP"
```

- [ ] **Step 8: Manual simulator verification (one booted simulator only)**

On a feed with plenty of posts:
1. Scroll deep (well past one screen). Tap the status bar → feed scrolls to top, `"Jumped to top · Undo"` toast appears (~4s).
2. Tap **Undo** → instant snap back to the prior spot, the anchored row briefly pulses, `"Back to where you were"` confirmation shows.
3. Repeat step 1; this time tap the **status bar again** (don't touch the toast) → same instant snap-back + pulse + confirmation (the toggle).
4. Repeat step 1, let the toast expire (>4s), then tap the **status bar** → still snaps back (state outlived the toast).
5. Repeat step 1, then **manually scroll** during the window → toast disappears; a subsequent status-bar tap performs a fresh scroll-to-top (no stale undo).
6. From near the top (shallow), tap the status bar → no toast (below threshold); status bar behaves exactly as before.
7. Pull-to-refresh while an undo is armed → undo toast clears, no stale snap-back afterwards.

---

## Self-Review

**Spec coverage:**
- Toggle model (toast + status-bar re-tap) → Task 1 `statusBarTapped`/`takeUndo`, Task 3 `scrollViewShouldScrollToTop`. ✓
- Instant snap restore → Task 3 `performScrollUndo` (`animated: false`). ✓
- Only when scrolled deep (≈1 screen) → Task 1 `scrolledToTop(viewportHeight:)` threshold + tests. ✓
- Pulse anchored row, Reduce-Motion aware → Task 3 `CellPulseHighlight`. ✓
- Confirmation toast on both paths → Task 3 `performScrollUndo` (shared by button + toggle). ✓
- State outlives toast / survives toast supersession → Task 1 `pending` independent of toast; Task 2 `dismiss()` + replace-don't-coalesce. ✓
- Invalidate on manual drag / feed change / refresh → Task 3 `scrollViewWillBeginDragging` + `feedChanged`. ✓
- Programmatic scrolls don't trigger → relies on `scrollViewDidScrollToTop` only firing for status-bar/system scroll-to-top (documented behavior); restore uses `setContentOffset`, which doesn't fire it. ✓
- Interactive toast + hit-testing → Task 2; simplified (content-sized pill, no full-screen overlay) and noted. ✓
- Accessibility announcement + accessible Undo button → Task 3 `showUndoScrollToast` + the button. ✓
- Toast copy verbatim → Global Constraints + used literally in Tasks 2/3. ✓

**Deviation from spec (intentional):** the spec suggested unit-testing the pulse trigger via an injected spy. The plan instead concentrates unit tests on the `ScrollToTopUndo` reducer (where the real logic lives) and verifies the pulse/VC wiring via build + the manual checklist, avoiding a brittle view-controller spy. The pulse is a pure UIKit animation side effect with no branching logic to assert.

**Placeholder scan:** none — every step has concrete code/commands.

**Type consistency:** `ScrollToTopUndo`, `Pending { offset, anchorServerPostId }`, `TapResponse { allowScrollToTop, undo }`, `pending`, `statusBarTapped`, `scrolledToTop`, `takeUndo`, `invalidate`, `ToastView(message:actionTitle:action:)`, `isInteractive`, `pulseHighlight(color:)` are used identically across Tasks 1–3 and the tests. `Item.post(serverPostId:)` matches the existing enum (`:106`).
