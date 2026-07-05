# Voted-state visual treatment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a vote read as unmistakably *voted* — a filled "vote pill" when the vote arrows are shown, a trailing-corner "dog-ear fold" when they're hidden, and a filled score-pill in the detail header and on comments — replacing today's easy-to-miss tint-only cue.

**Architecture:** Presentation-only. A small shared `VoteFillStyle` helper centralizes the fill color (reusing the existing accent/periwinkle tokens), capsule metrics, and the commit animation (spring, with a Reduce-Motion cross-fade fallback). Each of the four vote surfaces consumes it: the post-list cell's arrow buttons (`PostListPostContentView`), a new `VoteFoldView` for the arrows-hidden mode, the detail header's vote buttons (`PostDetailHeaderCell`), and a new score-pill in the comment header (`PostDetailCommentCell`). No data-layer, preference, or vote-mechanics changes.

**Tech Stack:** UIKit, Swift 6 (strict concurrency, `@MainActor`), `pointfreeco/swift-snapshot-testing`, Swift Testing (unit).

**Design spec:** `docs/superpowers/specs/2026-07-05-voted-state-design.md`. Source: Claude Design `Spud Voted State - Final.html`.

## Global Constraints

- **Up token reused, down token changed to the mock's indigo.** Up = `GeneralAppearance.upvoteButtonActiveColor` (`ThemeManager.currentAccentColor`) — unchanged. Down = `GeneralAppearance.downvoteButtonActiveColor` (`GeneralAppearance.downColor`), **changed from periwinkle `#7c8df0` to indigo `#5b57e0`** (RGB ≈ 0.357, 0.341, 0.878) in Task 1 — the single source, so it propagates to every downvote surface app-wide (user-approved). Filled-capsule glyph/number = `.white`. Inactive/neutral = `.tertiaryLabel`.
- **`VoteStatus`** (SpudDataKit) has cases `.up`, `.down`, `.neutral` — never `.none`.
- **Modes never stack.** The pill (arrows shown) and the fold (arrows hidden) are gated by the SAME existing `showVoteButtons` preference (default `true`). A cell shows exactly one.
- **Accessibility.** Active vote controls gain the `.selected` trait; keep using `VoteAccessibility` for labels/score phrasing; each arrow keeps ≥44 pt hit area; the fold is `isAccessibilityElement = false`.
- **Reduce Motion.** Gate the spring on `!UIAccessibility.isReduceMotionEnabled`; otherwise cross-fade. Do NOT add a new vote haptic — the app already fires one on enqueue.
- **Strict concurrency.** All new code is `@MainActor` UIKit. No `static let` non-Sendable stored formatters/colors.
- **No emojis.** Conventional-commit subjects (`feat:` / `test:` / `docs:`). SwiftFormat (`mint run swiftformat .`) before every commit; the pre-commit hook blocks on violations.
- **Snapshot recording.** `.image(size:traits:)` refs are device+runtime-sensitive → record/verify on the reference sim via `make snapshot` (iPhone 17 Pro / iOS 26.3.x). Re-record ONE class at a time; never `git annex restage` between record and verify; `git add` only the explicit refs you changed. The **orchestrator runs the final reference-device snapshot pass** (§ Task 7) to avoid shared-sim contention between subagents; per-task implementers build + run pure unit tests, and write (not necessarily record) the snapshot tests.

**Repo paths** are relative to the worktree root (app sources under `Spud/`, frameworks under `SpudUIKit/` etc., docs under `docs/`). Build/test via the `make` targets. This plan is executed in the worktree `/.../.claude/worktrees/voted-state` on branch `feat/voted-state`.

---

### Task 1: Shared `VoteFillStyle` helper

The single source of truth for the filled-capsule look and its commit animation, so the four surfaces are visually identical and DRY.

**Files:**
- Create: `Spud/Utils/Vote/VoteFillStyle.swift`
- Create (test): `SpudTests/VoteFillStyleTests.swift`
- Modify: `project.yml` is not needed (XcodeGen globs `Spud/**`), but run `make project` after adding the file so the generated project sees it.

**Interfaces:**
- Consumes: `VoteStatus` (SpudDataKit), `GeneralAppearance` (`Spud/Services/Appearance/GeneralAppearance.swift`) exposing `upvoteButtonActiveColor` / `downvoteButtonActiveColor`.
- Also in this task: **change the downvote token** `GeneralAppearance.downColor` from periwinkle to the mock's indigo (see Step 0). It's the single downvote-color source, so this is one edit that repaints every downvote surface.
- Produces (later tasks rely on these exact signatures):
  - `enum VoteFillStyle`
  - `static func fillColor(for status: VoteStatus, appearance: GeneralAppearance) -> UIColor?` — accent for `.up`, periwinkle for `.down`, `nil` for `.neutral`.
  - `static let filledGlyphColor: UIColor` (= `.white`)
  - `static let capsuleCornerRadius: CGFloat` (= 8)
  - `static func animateCommit(_ view: UIView)` — spring scale 0.9→1.0 (~180 ms) when Motion is allowed; a quick opacity cross-fade otherwise. Reads `UIAccessibility.isReduceMotionEnabled` internally.

- [ ] **Step 0: Change the downvote token to indigo `#5b57e0`**

In `Spud/Services/Appearance/GeneralAppearance.swift`, change `downColor` from periwinkle to the mock's indigo (keep the existing decimal style and the doc comment, updating the hex):

```swift
/// The design's "down" token (#5b57e0): the downvoted state and negative
/// scores. A fixed indigo, distinct from the accent (which drives the
/// upvoted state). Computed so it stays concurrency-safe (UIColor isn't
/// `Sendable`, so it can't be a shared `static let`).
static var downColor: UIColor {
    UIColor(red: 0.357, green: 0.341, blue: 0.878, alpha: 1)
}
```

This is the single downvote-color source (list arrows, header/comment score, swipe-action backgrounds), so every downvote surface picks up the indigo. Expect several extra snapshot refs beyond the voted-state ones to drift — handled in Task 7 Step 3.

- [ ] **Step 1: Write the helper**

Create `Spud/Utils/Vote/VoteFillStyle.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Shared styling for the "voted" state's filled capsule, used by every vote
/// surface (post-list arrow buttons, the detail-header vote button, and the
/// comment score-pill) so they read as one object.
///
/// The state is carried by a real weight change — a solid fill with a white
/// glyph vs a hairline/tertiary outline — not by hue alone, so it survives a
/// glance and color-blindness. Colors reuse the app's existing vote tokens
/// (accent for up, periwinkle for down) rather than hardcoded values, so the
/// upvote fill tracks the user's chosen accent.
@MainActor
enum VoteFillStyle {
    /// The fill color for a voted capsule, or `nil` when there is nothing to
    /// fill (neutral — the control stays a tertiary outline).
    static func fillColor(for status: VoteStatus, appearance: GeneralAppearance) -> UIColor? {
        switch status {
        case .up: return appearance.upvoteButtonActiveColor
        case .down: return appearance.downvoteButtonActiveColor
        case .neutral: return nil
        }
    }

    /// Glyph / number color drawn on top of a filled capsule.
    static let filledGlyphColor: UIColor = .white

    /// Corner radius of the filled capsule across all surfaces.
    static let capsuleCornerRadius: CGFloat = 8

    /// Animates a just-committed vote capsule: a light spring scale-in that
    /// reads as a pressed-button confirmation. Honors Reduce Motion by
    /// cross-fading the fill instead (no scaling).
    ///
    /// The vote haptic is fired elsewhere (on enqueue); this is visual only.
    static func animateCommit(_ view: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            view.layer.removeAnimation(forKey: "voteFillFade")
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.15
            view.layer.add(fade, forKey: "voteFillFade")
            return
        }
        view.layer.removeAnimation(forKey: "voteFillPop")
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.9
        pop.toValue = 1.0
        pop.damping = 14
        pop.stiffness = 320
        pop.mass = 0.7
        pop.duration = pop.settlingDuration
        view.layer.add(pop, forKey: "voteFillPop")
    }
}
```

- [ ] **Step 2: Write the unit test**

Create `SpudTests/VoteFillStyleTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
import UIKit
@testable import Spud

@MainActor
struct VoteFillStyleTests {
    private func appearance() -> GeneralAppearance {
        GeneralAppearance()
    }

    @Test func upResolvesToAccent() {
        let fill = VoteFillStyle.fillColor(for: .up, appearance: appearance())
        #expect(fill == ThemeManager.currentAccentColor)
    }

    @Test func downResolvesToDownToken() {
        let fill = VoteFillStyle.fillColor(for: .down, appearance: appearance())
        #expect(fill == GeneralAppearance.downColor)
    }

    @Test func neutralHasNoFill() {
        #expect(VoteFillStyle.fillColor(for: .neutral, appearance: appearance()) == nil)
    }

    @Test func filledGlyphIsWhite() {
        #expect(VoteFillStyle.filledGlyphColor == .white)
    }
}
```

Note: confirm `GeneralAppearance()`'s initializer signature before running — if it requires no args this compiles; if it needs a `PreferencesService`, construct `GeneralAppearance(...)` to match its real init (read `Spud/Services/Appearance/GeneralAppearance.swift`). `ThemeManager` and `GeneralAppearance.downColor` are the values the helper returns, so the test is tautological-by-design (it pins the mapping, catching an accidental swap of up/down).

- [ ] **Step 3: Regenerate the project and build**

Run: `make project && make build`
Expected: builds clean (the new file compiles; 1 pre-existing benign rpath warning is fine).

- [ ] **Step 4: Run the unit test**

Run: `make test-only ONLY=SpudTests`
Expected: `✔ Test run with N tests ... passed` including the 4 `VoteFillStyle` tests.

- [ ] **Step 5: Format & commit**

```bash
mint run swiftformat .
git add Spud/Utils/Vote/VoteFillStyle.swift SpudTests/VoteFillStyleTests.swift
git commit -m "feat: add VoteFillStyle helper for the voted-state capsule"
```

---

### Task 2: Post-list vote pill (arrows shown)

Turn the active arrow into a filled capsule (white glyph on the token); the other arrow stays a tertiary hairline. Animate on commit; set the `.selected` trait.

**Files:**
- Modify: `Spud/Scenes/PostList/PostListPostContentView.swift` (the `makeVoteButton` builder ~343-361, the `configure` tint lines ~436-437; add a small `applyVoteState` helper)
- Test: `SpudSnapshotTests/PostListPostCellSnapshotTests.swift` (existing `test_upvoted` / `test_downvoted` / `test_neutral` cover the matrix — they'll be re-recorded)

**Interfaces:**
- Consumes: `VoteFillStyle` (Task 1); `viewModel.voteStatus`, `viewModel.upvoteActiveColor`, `viewModel.downvoteActiveColor` (unchanged).
- Produces: a private `applyVoteState(_:animated:)` on `PostListPostContentView`.

- [ ] **Step 1: Give the arrow buttons a capsule footprint**

In `makeVoteButton` (`PostListPostContentView.swift`), after `button.tintColor = .tertiaryLabel`, add a fixed capsule size and rounded corners so the fill has stable geometry:

```swift
button.tintColor = .tertiaryLabel
button.layer.cornerRadius = VoteFillStyle.capsuleCornerRadius
button.clipsToBounds = true
NSLayoutConstraint.activate([
    button.widthAnchor.constraint(equalToConstant: 32),
    button.heightAnchor.constraint(equalToConstant: 28),
])
button.accessibilityLabel = accessibilityLabel
```

(The 32×28 capsule keeps the arrow's ≥44 pt hit area via the surrounding `voteColumn` spacing; the visible fill is the capsule.)

- [ ] **Step 2: Replace the tint-only lines with a filled-capsule state**

Replace the two lines at ~436-437 in `configure`:

```swift
upvoteButton.tintColor = viewModel.voteStatus == .up ? viewModel.upvoteActiveColor : .tertiaryLabel
downvoteButton.tintColor = viewModel.voteStatus == .down ? viewModel.downvoteActiveColor : .tertiaryLabel
```

with a call to a new helper (defined next), non-animated on `configure` (cell reuse must not animate):

```swift
applyVoteState(viewModel.voteStatus, animated: false)
```

Add the helper near `makeVoteButton`:

```swift
/// Renders the active arrow as a filled capsule (white glyph on the vote
/// token) and the other as a tertiary hairline. `animated` springs the newly
/// filled capsule in; it must be `false` on cell reuse (`configure`) so
/// scrolling doesn't animate every recycled cell.
private func applyVoteState(_ status: VoteStatus, animated: Bool) {
    style(upvoteButton, filled: status == .up, fill: appliedUpvoteColor)
    style(downvoteButton, filled: status == .down, fill: appliedDownvoteColor)
    if animated {
        if status == .up { VoteFillStyle.animateCommit(upvoteButton) }
        if status == .down { VoteFillStyle.animateCommit(downvoteButton) }
    }
}

private func style(_ button: UIButton, filled: Bool, fill: UIColor) {
    button.backgroundColor = filled ? fill : .clear
    button.tintColor = filled ? VoteFillStyle.filledGlyphColor : .tertiaryLabel
    button.accessibilityTraits = filled ? [.button, .selected] : [.button]
}
```

Store the resolved colors so `applyVoteState` has them (they come from the view model). Add stored properties and set them in `configure` before the call:

```swift
// near the other applied* cache properties
private var appliedUpvoteColor: UIColor = .tertiaryLabel
private var appliedDownvoteColor: UIColor = .tertiaryLabel
```

and in `configure`, just before `applyVoteState(...)`:

```swift
appliedUpvoteColor = viewModel.upvoteActiveColor
appliedDownvoteColor = viewModel.downvoteActiveColor
applyVoteState(viewModel.voteStatus, animated: false)
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: clean build.

- [ ] **Step 4: Re-record the post-list vote snapshots (reference sim)**

The existing `test_upvoted` / `test_downvoted` / `test_neutral` now render the pill. Delete their refs, record, verify — ONE class at a time:

```bash
find SpudSnapshotTests/__Snapshots__/PostListPostCellSnapshotTests -name 'test_upvoted*' -o -name 'test_downvoted*' -o -name 'test_neutral*'
# delete those refs, then:
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/PostListPostCellSnapshotTests \
  -destination "$(scripts/resolve-test-destination.sh --reference)" \
  -skipPackagePluginValidation -skipMacroValidation test   # records + fails
# rerun the same command → verifies (green)
```

Visually confirm each recorded PNG shows: upvoted = filled accent up-capsule + tertiary down-arrow; downvoted = filled periwinkle down-capsule; neutral = both tertiary. (Orchestrator may run this pass — see Global Constraints.)

- [ ] **Step 5: Format & commit**

```bash
mint run swiftformat .
git add Spud/Scenes/PostList/PostListPostContentView.swift
git add SpudSnapshotTests/__Snapshots__/PostListPostCellSnapshotTests/test_upvoted.* \
        SpudSnapshotTests/__Snapshots__/PostListPostCellSnapshotTests/test_downvoted.* \
        SpudSnapshotTests/__Snapshots__/PostListPostCellSnapshotTests/test_neutral.*
git commit -m "feat: fill the active vote arrow as a capsule in the post list"
```

---

### Task 3: Dog-ear fold (arrows hidden)

When the user hides the vote arrows (`showVoteButtons == false`), a voted post gets a folded trailing corner: up folds from the top, down from the bottom, each with a debossed arrow.

**Files:**
- Create: `Spud/Scenes/PostList/VoteFoldView.swift`
- Modify: `Spud/Scenes/PostList/PostListPostContentView.swift` (add the fold subview; show/hide it in `applyLayout` / `applyVoteState`)
- Test: `SpudSnapshotTests/PostListPostCellSnapshotTests.swift` (add a buttons-hidden trio)

**Interfaces:**
- Consumes: `VoteStatus`, `VoteFillStyle` (Task 1), and the resolved up/down colors already cached on the content view (`appliedUpvoteColor` / `appliedDownvoteColor`, Task 2).
- Produces: `final class VoteFoldView: UIView` with `func configure(status: VoteStatus, upColor: UIColor, downColor: UIColor)` and it sets its own `isHidden` for `.neutral`.

- [ ] **Step 1: Write `VoteFoldView`**

Create `Spud/Scenes/PostList/VoteFoldView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// A folded-corner ("dog-ear") mark that carries voted state on a post-list
/// cell when the trailing vote arrows are hidden (gesture-voting mode). Up
/// folds from the trailing-top corner, down from the trailing-bottom corner —
/// orientation encodes direction before color does. Decorative: not an
/// accessibility element and not a tap target (voting stays a swipe/gesture).
final class VoteFoldView: UIView {
    private let triangleLayer = CAShapeLayer()
    private let arrow = UIImageView()
    private var status: VoteStatus = .neutral

    /// Fixed 28 pt corner; the fold is fixed geometry (unaffected by Dynamic Type).
    static let side: CGFloat = 28

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.addSublayer(triangleLayer)
        arrow.contentMode = .center
        arrow.tintColor = VoteFillStyle.filledGlyphColor
        addSubview(arrow)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the fold for a voted status (hidden when neutral). `upColor` /
    /// `downColor` are the resolved vote tokens (accent / periwinkle).
    func configure(status: VoteStatus, upColor: UIColor, downColor: UIColor) {
        self.status = status
        switch status {
        case .neutral:
            isHidden = true
            return
        case .up:
            isHidden = false
            triangleLayer.fillColor = upColor.cgColor
            arrow.image = UIImage(
                systemName: "arrow.up",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            )
        case .down:
            isHidden = false
            triangleLayer.fillColor = downColor.cgColor
            arrow.image = UIImage(
                systemName: "arrow.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .heavy)
            )
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = bounds.size
        let path = UIBezierPath()
        if status == .down {
            // Trailing-bottom corner: top-right, bottom-right, bottom-left.
            path.move(to: CGPoint(x: s.width, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            path.addLine(to: CGPoint(x: 0, y: s.height))
            arrow.frame = CGRect(x: s.width - 15, y: s.height - 15, width: 13, height: 13)
        } else {
            // Trailing-top corner: top-left, top-right, bottom-right.
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: 0))
            path.addLine(to: CGPoint(x: s.width, y: s.height))
            arrow.frame = CGRect(x: s.width - 15, y: 2, width: 13, height: 13)
        }
        path.close()
        triangleLayer.path = path.cgPath
    }
}
```

- [ ] **Step 2: Host the fold in the content view**

In `PostListPostContentView.swift`, add the fold as an overlay subview pinned to the trailing edge (NOT in the horizontal stack). In `init`/setup, after the content is assembled:

```swift
lazy var voteFold: VoteFoldView = {
    let view = VoteFoldView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    view.isHidden = true
    return view
}()
```

Add it to the cell's root content view and pin trailing + top and bottom (its own `configure` swaps which corner is drawn; pin all three so either corner is reachable):

```swift
addSubview(voteFold)          // above the stack; the trailing corner is free in hidden mode
NSLayoutConstraint.activate([
    voteFold.trailingAnchor.constraint(equalTo: trailingAnchor),
    voteFold.topAnchor.constraint(equalTo: topAnchor),
])
```

Note: pin `top` only; the view draws up- or down-corner within its own 28×28 box, and for the down case anchor it to the bottom instead. Simplest robust approach: keep two constraints (top and bottom) and toggle their `isActive` in `applyVoteState` based on status. Read the actual view hierarchy in `PostListPostContentView` and choose the anchor that matches the cell's outer content rect (the fold must sit flush to the visible trailing edge, inside the swipe container). Provide both constraints as stored properties:

```swift
private lazy var voteFoldTop = voteFold.topAnchor.constraint(equalTo: topAnchor)
private lazy var voteFoldBottom = voteFold.bottomAnchor.constraint(equalTo: bottomAnchor)
```

- [ ] **Step 3: Drive the fold from vote state + the layout gate**

Extend `applyVoteState` (from Task 2) so the fold shows ONLY when the vote arrows are hidden:

```swift
private func applyVoteState(_ status: VoteStatus, animated: Bool) {
    // Pill (arrows shown) and fold (arrows hidden) are mutually exclusive.
    let showFold = !appliedShowVoteButtons!  && status != .neutral
    style(upvoteButton, filled: status == .up, fill: appliedUpvoteColor)
    style(downvoteButton, filled: status == .down, fill: appliedDownvoteColor)

    voteFoldTop.isActive = status == .up
    voteFoldBottom.isActive = status == .down
    voteFold.configure(status: showFold ? status : .neutral,
                       upColor: appliedUpvoteColor, downColor: appliedDownvoteColor)

    if animated {
        if !showFold, status == .up { VoteFillStyle.animateCommit(upvoteButton) }
        if !showFold, status == .down { VoteFillStyle.animateCommit(downvoteButton) }
        if showFold { VoteFillStyle.animateCommit(voteFold) }
    }
}
```

`applyVoteState` is called in `configure` AFTER `applyLayout` (so `appliedShowVoteButtons` is set). Verify the call order in `configure`; if `applyVoteState` currently runs before `applyLayout`, move it after `applyLayout(...)`.

- [ ] **Step 4: Add buttons-hidden snapshot coverage**

In `PostListPostCellSnapshotTests.swift`, add a `showVoteButtons` param to `makeViewModel` (default `true`) and thread it through `renderCell` / `assertCell`, then add a trio. Change `makeViewModel`'s signature and body:

```swift
private func makeViewModel(row: PostListRow, density: PostDensity, showVoteButtons: Bool = true) -> PostListPostViewModel {
    let preferences = PreferencesService()
    preferences.postDensity = density
    preferences.thumbnailPosition = .left
    preferences.showVoteButtons = showVoteButtons
    let appearance = AppearanceService(preferencesService: preferences)
    return PostListPostViewModel(
        row: row,
        appearance: appearance,
        postContentDetector: PostContentDetectorService()
    )
}
```

Thread `showVoteButtons` through `assertCell` / `renderCell` (add the param, default `true`, pass into `makeViewModel`). Add tests:

```swift
func test_fold_upvoted() async {
    await assertCell(row(url: nil, voteStatus: 1), showVoteButtons: false)
}

func test_fold_downvoted() async {
    await assertCell(row(url: nil, voteStatus: 0), showVoteButtons: false)
}

func test_fold_neutral() async {
    await assertCell(row(url: nil, voteStatus: nil), showVoteButtons: false)
}
```

- [ ] **Step 5: Build, record the three new refs, verify**

Run: `make build`, then record + verify `PostListPostCellSnapshotTests` (as in Task 2 Step 4) for the three new `test_fold_*` names. Confirm: `test_fold_upvoted` shows a top-corner accent fold with a white up-arrow; `test_fold_downvoted` a bottom-corner periwinkle fold; `test_fold_neutral` no fold and no arrows.

- [ ] **Step 6: Format & commit**

```bash
mint run swiftformat .
make project   # picks up the new VoteFoldView.swift
git add Spud/Scenes/PostList/VoteFoldView.swift Spud/Scenes/PostList/PostListPostContentView.swift \
        SpudSnapshotTests/PostListPostCellSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostListPostCellSnapshotTests/test_fold_*
git commit -m "feat: dog-ear fold for voted posts when vote arrows are hidden"
```

---

### Task 4: Detail header — filled vote button

The header's active vote button goes solid (filled capsule + white glyph) instead of only recoloring the glyph.

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift` (the `upvoteBarButton` handler ~279-293, `downvoteBarButton` handler ~314-326)
- Test: `SpudSnapshotTests/PostDetailHeaderSnapshotTests.swift` (re-record voted cases; read the file first to find the exact test names, e.g. `test_image_upvoted` / a downvoted case — add a downvoted test if absent)

**Interfaces:**
- Consumes: `VoteFillStyle`, `ThemeManager.currentAccentColor`, `GeneralAppearance.downColor` (unchanged).
- Produces: nothing new; behavior change only.

- [ ] **Step 1: Fill the upvote button on select**

Replace the `if button.isSelected { ... }` body in `upvoteBarButton.configurationUpdateHandler` so it fills the background and whitens the glyph (a `.plain()` config ignores `baseBackgroundColor`; set `background.backgroundColor` + corner radius explicitly):

```swift
if button.isSelected {
    // Solid filled capsule: the accent as the fill, a white glyph on top —
    // a real weight change, not just a tint. Read live so it tracks accent.
    newConfiguration.imageColorTransformer = .init { _ in VoteFillStyle.filledGlyphColor }
    newConfiguration.background.backgroundColor = ThemeManager.currentAccentColor
    newConfiguration.background.cornerRadius = VoteFillStyle.capsuleCornerRadius
} else {
    newConfiguration.imageColorTransformer = .init { $0 }
    newConfiguration.background.backgroundColor = .clear
}
```

- [ ] **Step 2: Fill the downvote button on select**

Symmetrically in `downvoteBarButton.configurationUpdateHandler`:

```swift
if button.isSelected {
    newConfiguration.imageColorTransformer = .init { _ in VoteFillStyle.filledGlyphColor }
    newConfiguration.background.backgroundColor = GeneralAppearance.downColor
    newConfiguration.background.cornerRadius = VoteFillStyle.capsuleCornerRadius
} else {
    newConfiguration.imageColorTransformer = .init { $0 }
    newConfiguration.background.backgroundColor = .clear
}
```

- [ ] **Step 3: Animate the fill on user-initiated vote**

Find where the header applies vote state (`upvoteBarButton.isSelected = viewModel.isUpvoted` ~656-658 and the tap handlers ~913/971 that fire `Haptics.tap()`). In the tap handlers only (not the reuse `configure`), after toggling `isSelected`, add `VoteFillStyle.animateCommit(<button>)` so the fill springs in on an actual tap but not on scroll/reuse. Read the handlers to place this precisely; if the header rebinds via `configure`, guard the animation behind the tap path.

- [ ] **Step 4: Build**

Run: `make build` — clean.

- [ ] **Step 5: Re-record header voted snapshots (reference sim)**

Read `PostDetailHeaderSnapshotTests.swift` for the voted test names. Re-record the upvoted (and downvoted, adding one if missing) refs, one class at a time, per Task 2 Step 4's pattern with `-only-testing:SpudSnapshotTests/PostDetailHeaderSnapshotTests`. Confirm the upvoted button renders as a filled accent capsule with a white arrow.

- [ ] **Step 6: Format & commit**

```bash
mint run swiftformat .
git add Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift \
        SpudSnapshotTests/PostDetailHeaderSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailHeaderSnapshotTests/<voted refs>
git commit -m "feat: fill the detail-header vote button when voted"
```

---

### Task 5: Comment score mini-pill

Render a comment's inline score as a filled mini-pill (white arrow + white number) when the comment is voted; neutral keeps the current tertiary arrow+number. Must coexist with the fresh wash, OP badge, saved bookmark, "NEW" pill, and depth rails.

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` (add a `scorePillLabel` in the header stack ~152; render it in `configure`)
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift` (expose the score + voteStatus separately so the cell can render the pill; remove the score piece from the attributed `subtitle` when it moves to the pill — OR keep the subtitle for age/saved and add a `scoreText`/`voteStatus`)
- Test: `SpudSnapshotTests/PostDetailCommentSnapshotTests.swift` (re-record voted cases; add up+fresh and OP+up if not present)

**Interfaces:**
- Consumes: `VoteFillStyle`; `VoteAccessibility.scoreLabel(score:voteStatus:)`; the comment's `score` (Int64) and `voteStatus` (`VoteStatus`).
- Produces: a `BadgeLabel`/`UILabel`-based `scorePillLabel` on the cell; view-model exposes `commentScore: Int64` and `voteStatus: VoteStatus` (names must match what the cell reads).

- [ ] **Step 1: Expose score + voteStatus on the view model; drop score from the subtitle**

Read `PostDetailCommentViewModel.swift` around the subtitle assembly (~288-324). The score is currently the first `IconValueFormatter` piece of `subtitle`. Change so:
- Add `let voteStatus: VoteStatus` (already computed locally ~288-294 — promote it to a stored property) and `let score: Int64` (from `row.score`).
- Remove the score `IconValueFormatter` piece from the `subtitlePieces` (keep age, saved). The score now renders via the pill.
- Keep the spoken accessibility via `VoteAccessibility.scoreLabel` — the cell sets it on the pill.

Provide exact names: `voteStatus` and `score` on `PostDetailCommentViewModel`.

- [ ] **Step 2: Add the score-pill to the comment header stack**

In `PostDetailCommentCell.swift`, add a label styled as a pill and insert it into the header stack right after the author/badges, before the (now score-less) `subtitleLabel`:

```swift
lazy var scorePillLabel: BadgeLabel = {
    let label = BadgeLabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.layer.cornerRadius = VoteFillStyle.capsuleCornerRadius
    label.clipsToBounds = true
    label.accessibilityIdentifier = "score"
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    return label
}()
```

Insert it in the `subviews` array of the header stack (near `subtitleLabel` at ~152). `BadgeLabel` already exists in the codebase (used for the collapsed-new pill) and gives inset padding; confirm its padding API and reuse it.

- [ ] **Step 3: Render the pill in `configure`**

In the comment cell's `configure`, build the pill content — an arrow glyph + the formatted number — filled when voted, plain tertiary when neutral:

```swift
let voteStatus = viewModel.voteStatus
let scoreString = UpvotesFormatter.string(from: viewModel.score)
let glyph = voteStatus == .down ? "arrow.down" : "arrow.up"
let filled = voteStatus != .neutral
let fill = VoteFillStyle.fillColor(for: voteStatus, appearance: viewModel.appearance.general)
let glyphColor: UIColor = filled ? VoteFillStyle.filledGlyphColor : .tertiaryLabel
var attrs: [NSAttributedString.Key: Any] = [
    .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: filled ? .bold : .regular),
    .foregroundColor: glyphColor,
]
let pill = NSMutableAttributedString()
pill.append(NSAttributedString.symbol(from: UIImage(systemName: glyph)!, attributes: attrs))
pill.append(NSAttributedString(string: " " + scoreString, attributes: attrs))
scorePillLabel.attributedText = pill
scorePillLabel.backgroundColor = filled ? fill : .clear
scorePillLabel.accessibilityLabel = VoteAccessibility.scoreLabel(score: viewModel.score, voteStatus: voteStatus)
```

Confirm `NSAttributedString.symbol(from:attributes:)` exists (it's used in the view model today) and that `viewModel.appearance.general` is reachable from the cell (the header cell reaches appearance; mirror that access path — if the cell has no appearance, resolve the fill via the two colors the view model already exposes, adding `upvoteActiveColor`/`downvoteActiveColor` to the comment VM like the list VM has). Prefer passing the two resolved colors from the view model to avoid the cell reaching into appearance.

Reset the pill in `prepareForReuse` (`scorePillLabel.attributedText = nil; scorePillLabel.backgroundColor = .clear`).

- [ ] **Step 4: Build**

Run: `make build` — clean. Fix any access-path issues surfaced (appearance reachability, `BadgeLabel` padding).

- [ ] **Step 5: Re-record comment voted snapshots (reference sim)**

Read `PostDetailCommentSnapshotTests.swift` for the voted / fresh / OP test names. Re-record the upvoted + downvoted refs; add `test_upvoted_fresh` and `test_op_upvoted` if the matrix doesn't already cover "pill over the fresh wash" and "pill beside the OP badge". Verify the pill is legible on the teal fresh wash and doesn't collide with OP/saved/rails.

- [ ] **Step 6: Format & commit**

```bash
mint run swiftformat .
git add Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift \
        Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift \
        SpudSnapshotTests/PostDetailCommentSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/PostDetailCommentSnapshotTests/<voted refs>
git commit -m "feat: render voted comment scores as a filled mini-pill"
```

---

### Task 6: Docs — feature docs, README table & by-area map

**Files:**
- Modify: `docs/features/voting.md`
- Modify: `docs/features/README.md` (capability table row + "Feature coverage by area" map)
- Modify: `docs/features/post-list-appearance.md` (or the closest existing post-list doc) and `docs/features/post-detail-and-comments.md` and `docs/features/accessibility.md` — reconcile the voted-state description
- (No test.)

- [ ] **Step 1: Update `voting.md`**

Read it, then add a "Voted-state presentation" section documenting: the filled vote pill (arrows shown) vs the dog-ear fold (arrows hidden), gated by `showVoteButtons`; the filled header button; the comment score mini-pill; colors (accent up / periwinkle down, white glyph); Reduce-Motion behavior; and the `.selected` VoiceOver trait. Add Given/When/Then scenarios: "Scanning the feed, an upvoted post shows a filled up-capsule"; "With vote arrows hidden, an upvoted post shows a top-corner fold"; "A downvoted comment shows a filled periwinkle score-pill". Keep `Status:` honest and update `Surfaces:` to the union of scenario tags.

- [ ] **Step 2: Update the README capability table + by-area map**

In `docs/features/README.md`, update the voting capability row to mention the structural voted-state cue, and update the "Feature coverage by area" entry (post list / post detail) accordingly. Reconcile any adjacent mention in `post-list-appearance.md`, `post-detail-and-comments.md`, and `accessibility.md` (the `.selected` trait + Reduce-Motion note).

- [ ] **Step 3: Commit**

```bash
git add docs/features/voting.md docs/features/README.md \
        docs/features/post-detail-and-comments.md docs/features/accessibility.md
# plus post-list-appearance.md if it exists
git commit -m "docs: document the structural voted-state treatment"
```

---

### Task 7: Full verification pass (orchestrator)

**Files:** none (verification only).

- [ ] **Step 1: Format the whole tree**

Run: `mint run swiftformat .` — no diffs expected (each task already formatted).

- [ ] **Step 2: Full unit-test plan**

Run: `make test`
Expected: green — `✔ Test run ... passed`, including `VoteFillStyleTests`.

- [ ] **Step 3: Full snapshot plan on the reference sim**

Run: `make snapshot`
Expected: green EXCEPT for downvote-showing refs beyond the ones re-recorded per task — the `downColor` change (Task 1 Step 0) repaints every downvoted score/arrow/swipe across the suite (e.g. Activity/Person cells, any downvoted subtitle). Enumerate the mismatches, confirm each diff is ONLY the periwinkle→indigo hue shift (a PIL `ImageChops.difference` heatmap localized to the downvote glyph/pill — NOT a layout/size change), then re-record each affected class ONE at a time per the ceremony and re-run. If a ref is "No reference" it was mis-recorded. A runtime mismatch also reads as a diff — verify the booted sim is the reference device (`make snapshot` fails fast otherwise).

- [ ] **Step 4: Accessibility spot-check (manual, documented)**

With VoiceOver reasoning: confirm each surface sets the `.selected` trait on the active control (list button, header button) and the comment pill carries `VoteAccessibility.scoreLabel`. Confirm the fold is not an accessibility element. Note the outcome in the finishing summary (snapshots don't catch a11y).

- [ ] **Step 5: Confirm the branch is clean and ready**

Run: `git status -uall` (ensure only intended files staged/committed; `.remember/` stays untracked). Summarize commits and hand off to `superpowers:finishing-a-development-branch`.

---

## Self-Review

**Spec coverage:**
- Vote pill (arrows shown) → Task 2. Dog-ear fold (arrows hidden) → Task 3. Header filled button → Task 4. Comment score mini-pill → Task 5. Shared color/metrics/animation → Task 1. Reduce Motion → Task 1 (`animateCommit`) applied in 2/3/4/5. `.selected` trait → Task 2 (list), Task 4 (header); comment pill is non-interactive (score display) so it carries the spoken score label, not a control trait — matches today's behavior. Up token reused / down token changed to indigo `#5b57e0` → Global Constraints + Task 1 Step 0 (single source, app-wide). Docs → Task 6 (note the downvote color change in voting.md + appearance doc). Verification (build + unit + snapshot incl. the broader downvote re-record + a11y) → Task 7.
- Gap check: the mock's "commit spring + light haptic" — haptic already exists (Global Constraints notes not to double-fire); the spring is Task 1's `animateCommit`, wired on the tap paths in Tasks 2/4 and on the fold in Task 3.

**Placeholder scan:** No TBD/TODO. Each code step shows real code. The two spots that say "read the file first / confirm the access path" (Task 4 Step 3 tap-handler placement, Task 5 Step 3 appearance reachability) are genuine per-codebase confirmations, not deferred work — the surrounding code is given.

**Type consistency:** `VoteFillStyle.fillColor(for:appearance:)`, `.filledGlyphColor`, `.capsuleCornerRadius`, `.animateCommit(_:)` are used with the same signatures in Tasks 2–5. `VoteStatus` cases `.up/.down/.neutral` used consistently. `VoteFoldView.configure(status:upColor:downColor:)` produced in Task 3 Step 1, consumed in Step 3. Comment VM exposes `voteStatus` + `score`, read by the cell in Task 5 Step 3.
