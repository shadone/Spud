# iOS 26 Liquid Glass Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Spud look and feel like an app designed for iOS 26 by removing the custom appearance code that suppresses Liquid Glass, adopting the new structural affordances, and re-doing our own chrome on real glass.

**Architecture:** Four phases, bottom-up. Phase 0 is almost entirely deletion (deployment floor, True-Black retirement, appearance-proxy removal) and carries most of the visual payoff. Phase 1 audits what the system now provides. Phase 2 adopts `UITab` / `UISearchTab` / tab minimization / background extension. Phase 3 converts our own `UIBlurEffect` chrome to `UIGlassEffect`. Phase 4 is iOS 27 adaptivity hygiene.

**Tech Stack:** UIKit (predominant) + SwiftUI islands, Swift 6 strict concurrency, XcodeGen, Swift Testing, pointfreeco/swift-snapshot-testing, git-annex-tracked snapshot references.

**Spec:** `docs/superpowers/specs/2026-07-27-liquid-glass-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Worktree:** all work happens in `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/liquid-glass` on branch `feat/liquid-glass`. Read/Edit/Write **worktree-rooted paths only** — never the bare `/Users/denis/dev/info.ddenis/Spud/Spud/...` path, which is the shared main checkout.
- **Deployment floor:** iOS 26.0. No `#available(iOS 26, *)` guards are needed or wanted after Task 1.
- **No emojis** in code, comments, documentation, or commit messages.
- **Conventional commit subjects:** `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`.
- **Stage explicit paths.** Never `git add -A` or `git add .` — `.remember/` is a gitignored session buffer and annex refs carry cosmetic modified markers.
- **SwiftFormat runs BEFORE the final verify, never after:** `mint run swiftformat <paths>`. The pre-commit hook lints and blocks on violation.
- **Swift Testing, not XCTest:** `struct` suites, `@Test func` (no `test` prefix), `#expect` / `#require`. `import Testing` does not re-export Foundation.
- **Build/test commands** (run from the worktree root):
  - `make project` — regenerate `Spud.xcodeproj` after touching `project.yml` or adding/removing sources.
  - `make build` — build the app.
  - `make test` — full unit-test plan.
  - `make test-only ONLY=SpudUIKitTests` — a single target.
  - `make snapshot` — snapshot plan on the reference device (iPhone 17 Pro / iOS 26.3.x); fails fast on the wrong simulator.
- **Swift Testing prints "Executed 0 tests"** in xcodebuild's XCTest summary. Trust the `✔ Test run with N tests in M suites passed` line instead.
- **Do not touch** `Spud/Scenes/ShareAsImage/` (fixed designed artifacts, must never use `UIVisualEffectView`) or `Spud/Scenes/Shared/NsfwBlurOverlayView.swift` (a content obscurer, must stay opaque-ish blur).
- **Snapshot references are git-annex-tracked.** Re-record one class at a time; `git add` only the explicit refs changed; run `git annex restage` if committed refs show cosmetic modified markers. Full ceremony in `SpudSnapshotTests/CLAUDE.md`.
- **Single booted simulator.** Booting a second simulator causes "SBMainWorkspace Busy" failures.

---

## Phase 0 — Foundation

### Task 1: Raise the deployment target to iOS 26.0

**Files:**
- Modify: `project.yml` (the `deploymentTarget.iOS` key)

**Interfaces:**
- Consumes: nothing.
- Produces: an iOS 26.0 floor for every target, which lets Tasks 2-19 call iOS 26 APIs with no availability guards.

- [ ] **Step 1: Inspect the current value**

Run: `grep -n -A3 "deploymentTarget" project.yml`
Expected: a block containing `iOS: "18.0"`.

- [ ] **Step 2: Change the floor**

In `project.yml`, change:

```yaml
  deploymentTarget:
    iOS: "18.0"
```

to:

```yaml
  deploymentTarget:
    iOS: "26.0"
```

- [ ] **Step 3: Check for per-target overrides**

Run: `grep -n "IPHONEOS_DEPLOYMENT_TARGET\|deploymentTarget" project.yml`
Expected: only the single project-level `deploymentTarget` block. If any per-target `IPHONEOS_DEPLOYMENT_TARGET` override exists, raise it to `26.0` too — a target left at 18.0 silently keeps the old floor.

- [ ] **Step 4: Regenerate and build**

Run: `make project && make build`
Expected: build succeeds. Deprecation warnings that only fire at the higher floor are acceptable at this step and are addressed by later tasks; hard errors are not.

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "chore: raise deployment target to iOS 26.0

Liquid Glass adoption requires the iOS 26 API surface. A single floor
avoids availability forks and keeps one snapshot baseline."
```

---

### Task 2: Remove the appearance-proxy opt-out

This is the change that actually turns Liquid Glass on. Setting an explicit `backgroundColor` on a bar appearance replaces the glass material with a flat fill.

**Files:**
- Modify: `Spud/App/AppCoordinator.swift:39` (the `configureAppeareance()` call) and `:46-70` (the method)

**Interfaces:**
- Consumes: the iOS 26.0 floor from Task 1.
- Produces: stock Liquid Glass chrome on every navigation bar, tab bar, sheet, popover, menu and alert in the app. Later tasks assume no global appearance proxies exist.

- [ ] **Step 1: Read the current method**

Run: `sed -n '35,75p' Spud/App/AppCoordinator.swift`
Expected: `configureAppeareance()` containing a `UINavigationBarAppearance` block, a `UITabBarAppearance` block, and a `UITableView.appearance().backgroundColor` line.

- [ ] **Step 2: Delete the method and its call site**

Remove the entire `private func configureAppeareance() { ... }` method (including its explanatory comment about routing bars through the theme-aware background token — that rationale dies with the True-Black theme) and the `configureAppeareance()` call in `init`.

Do **not** replace it with `configureWithTransparentBackground()` or any other appearance configuration. The correct amount of bar appearance code is none.

- [ ] **Step 3: Build**

Run: `make build`
Expected: succeeds. `Theme` is still referenced elsewhere at this point; that is Task 4's job.

- [ ] **Step 4: Visually verify glass is live**

Run: `make build` then launch the app on the booted simulator and screenshot the feed:

```bash
xcrun simctl io booted screenshot /tmp/glass-check.png
```

Expected: the navigation bar and tab bar are translucent — feed content is visibly refracted beneath them as it scrolls, rather than sitting behind a flat fill. Compare against a pre-change screenshot if unsure. If the bars are still flat, an appearance proxy survives somewhere: re-run `grep -rn "UINavigationBar.appearance()\|UITabBar.appearance()\|UIToolbar.appearance()" --include='*.swift' .`

- [ ] **Step 5: Commit**

```bash
git add Spud/App/AppCoordinator.swift
git commit -m "feat: stop overriding bar appearance so Liquid Glass renders

An explicit backgroundColor on a bar appearance replaces the glass
material with a flat fill. The overrides existed only to serve the
True-Black theme, which Task 3 retires."
```

---

### Task 3: Retire `AppTheme.trueBlack` with a decode-time migration

`UserDefaultsBacked` stores values as JSON strings and **silently falls back to the default on a decode failure** (`SpudUtilKit/UserDefaultsBacked.swift:61-76`). Without a migration, a device with `"trueBlack"` persisted would reset to `.system` — the user's light/dark choice lost, not just their OLED preference.

**Files:**
- Modify: `SpudUIKit/Theme/AppTheme.swift`
- Modify: `SpudUIKit/Theme/ThemeManager.swift`
- Modify: `SpudUIKitTests/ThemeResolutionTests.swift`
- Create: `SpudUIKitTests/AppThemeMigrationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `AppTheme` with exactly three cases (`system`, `light`, `dark`), a custom `init(from:)` that maps legacy `"trueBlack"` to `.dark`, and a `ThemeManager` with no True-Black surface. `ThemeManager.usesTrueBlackBackgrounds` and `AppTheme.usesTrueBlackBackgrounds` no longer exist — Task 4 removes their last consumer.

- [ ] **Step 1: Write the failing migration test**

Create `SpudUIKitTests/AppThemeMigrationTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUIKit

/// The True Black (OLED) theme was retired when the app adopted Liquid Glass.
/// A device that persisted it must degrade to the nearest equivalent rather
/// than silently resetting, which is what `UserDefaultsBacked` would otherwise
/// do on a decode failure.
struct AppThemeMigrationTests {
    @Test
    func legacyTrueBlackDecodesAsDark() throws {
        let data = Data(#""trueBlack""#.utf8)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(decoded == .dark)
    }

    @Test
    func liveCasesStillRoundTrip() throws {
        for theme in AppTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            #expect(try JSONDecoder().decode(AppTheme.self, from: data) == theme)
        }
    }

    @Test
    func unknownRawValueStillThrows() {
        let data = Data(#""notATheme""#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AppTheme.self, from: data)
        }
    }

    @Test
    func trueBlackIsNoLongerAnOfferedChoice() {
        #expect(AppTheme.allCases.count == 3)
        #expect(!AppTheme.allCases.map(\.rawValue).contains("trueBlack"))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make test-only ONLY=SpudUIKitTests`
Expected: FAIL. `legacyTrueBlackDecodesAsDark` fails because `"trueBlack"` currently decodes to `.trueBlack`, and `trueBlackIsNoLongerAnOfferedChoice` fails because `allCases.count == 4`.

- [ ] **Step 3: Narrow `AppTheme` and add the migrating decoder**

In `SpudUIKit/Theme/AppTheme.swift`: delete the `case trueBlack`, delete the `usesTrueBlackBackgrounds` property, remove `trueBlack` from every `switch`, and update the type doc comment (it currently describes `.trueBlack`). Then add the decoder:

```swift
    /// Legacy raw value of the retired True Black (OLED) theme.
    private static let retiredTrueBlackRawValue = "trueBlack"

    /// Decodes a persisted selection, mapping the retired True Black theme
    /// onto `.dark`.
    ///
    /// True Black existed only to force opaque bars on OLED displays; Liquid
    /// Glass replaces that chrome entirely, so the theme was retired. Without
    /// this mapping `UserDefaultsBacked` would fail to decode the stored value
    /// and silently fall back to `.system`, discarding the user's dark-mode
    /// choice along with their OLED preference.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if rawValue == Self.retiredTrueBlackRawValue {
            self = .dark
            return
        }

        guard let theme = AppTheme(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognised AppTheme raw value '\(rawValue)'"
            )
        }
        self = theme
    }
```

`AppTheme.swift` currently only imports UIKit; the decoder needs no extra import (`DecodingError` comes from the Swift standard library, and UIKit re-exports Foundation).

- [ ] **Step 4: Strip True-Black from `ThemeManager`**

In `SpudUIKit/Theme/ThemeManager.swift` remove:
- the `trueBlackFlag` static property,
- the `usesTrueBlackBackgrounds` static accessor,
- the `private final class TrueBlackFlag` declaration,
- the `Self.trueBlackFlag.value = theme.usesTrueBlackBackgrounds` line in `setTheme(_:)`,
- the paragraph of the type doc comment describing the True-Black swap.

`setTheme(_:)` keeps assigning `self.theme`, and the whole `AccentColor` side (`accentColorBox`, `currentAccentColor`, `setAccent`) is untouched.

- [ ] **Step 5: Update the existing theme tests**

In `SpudUIKitTests/ThemeResolutionTests.swift`:
- delete the `AppTheme.trueBlack.userInterfaceStyle` assertion and its comment from `appTheme_userInterfaceStyle`,
- delete the whole `appTheme_usesTrueBlackBackgrounds` test.

Leave `appTheme_roundTripsThroughRawValue` and every `AccentColor` test as they are.

- [ ] **Step 6: Run tests**

Run: `mint run swiftformat SpudUIKit SpudUIKitTests && make test-only ONLY=SpudUIKitTests`
Expected: PASS. `Theme.swift` still compiles — it reads `ThemeManager.usesTrueBlackBackgrounds`, which is now gone, so **this step will fail to build until you also stub it**. Take the smallest bridge: in `SpudUIKit/Theme/Theme.swift`, replace the `dynamic(standard:trueBlackDark:)` helper body with `standard` and drop the now-unused `trueBlackDark` argument at each call site. Task 4 deletes the file outright; this keeps the tree building between commits.

- [ ] **Step 7: Commit**

```bash
git add SpudUIKit/Theme/AppTheme.swift SpudUIKit/Theme/ThemeManager.swift SpudUIKit/Theme/Theme.swift SpudUIKitTests/ThemeResolutionTests.swift SpudUIKitTests/AppThemeMigrationTests.swift
git commit -m "feat: retire the True Black theme with a decode-time migration

True Black existed only to force opaque bars, which Liquid Glass
replaces. A persisted selection decodes to .dark rather than falling
back to .system, which is what UserDefaultsBacked does on a decode
failure."
```

---

### Task 4: Delete the `Theme` token layer

`Theme` is now a pure pass-through to system colors. It exists only as the True-Black shim, so it goes.

**Files:**
- Delete: `SpudUIKit/Theme/Theme.swift`
- Modify: 48 files under `Spud/` (71 call sites — enumerate with the command in Step 1)

**Interfaces:**
- Consumes: `ThemeManager` from Task 3 (which survives, for `AccentColor`).
- Produces: no `Theme` type. Later tasks use `UIColor` system colors directly.

- [ ] **Step 1: Enumerate the call sites**

Run: `grep -rn "Theme\." --include='*.swift' Spud/ SpudUIKit/ Shared/ | grep -v "ThemeManager\.\|AppTheme\."`
Expected: 71 hits across 48 files (3 of which were already deleted with `AppCoordinator.configureAppeareance()` in Task 2, so expect 68 now).

- [ ] **Step 2: Apply the substitution table**

Every token is a straight substitution. This table is exhaustive — `Theme` has no other members:

| Replace | With |
|---|---|
| `Theme.background` | `UIColor.systemBackground` |
| `Theme.secondaryBackground` | `UIColor.secondarySystemBackground` |
| `Theme.groupedBackground` | `UIColor.systemGroupedBackground` |
| `Theme.secondaryGroupedBackground` | `UIColor.secondarySystemGroupedBackground` |
| `Theme.tertiaryBackground` | `UIColor.tertiarySystemBackground` (currently unused — expect zero hits) |
| `Theme.trueBlack` | (internal to `Theme.swift` only — deleted with the file) |

In an expression that already has `UIColor` type context (e.g. `view.backgroundColor = Theme.background`), prefer the leading-dot form `.systemBackground` to match the surrounding code.

In SwiftUI files, the SwiftUI equivalent is `Color(uiColor: .systemBackground)` — check what each SwiftUI call site already does with the value rather than assuming.

- [ ] **Step 3: Delete the file**

```bash
git rm SpudUIKit/Theme/Theme.swift
```

- [ ] **Step 4: Regenerate and verify no references remain**

Run:

```bash
make project
grep -rn '\bTheme\.' --include='*.swift' Spud/ SpudUIKit/ Shared/ | grep -v 'ThemeManager\.\|AppTheme\.'
```

Expected: no output.

- [ ] **Step 5: Build and test**

Run: `mint run swiftformat Spud SpudUIKit && make build && make test`
Expected: build succeeds, full test plan passes.

- [ ] **Step 6: Commit**

```bash
git add Spud SpudUIKit
git commit -m "refactor: delete the Theme token layer

Every token was a pass-through to a system color once True Black was
retired. Call sites now use the system colors directly."
```

---

### Task 5: Snapshot re-record, wave 1

Phase 0 changed chrome on essentially every screen, so nearly all 517 references churn. This is the larger of the two re-record waves.

**Files:**
- Modify: `SpudSnapshotTests/__Snapshots__/**/*.png` (git-annex tracked)

**Interfaces:**
- Consumes: the completed Phase 0 tree.
- Produces: a green snapshot baseline that Phases 1-4 diff against.

- [ ] **Step 1: Confirm the reference simulator**

Run: `xcrun simctl list devices booted`
Expected: exactly one booted device, an iPhone 17 Pro on an iOS 26.3.x runtime. If a different device is booted, shut it down and boot the reference one — `make snapshot` fails fast on the wrong simulator by design.

- [ ] **Step 2: Establish the damage**

Run: `make snapshot 2>&1 | tee /tmp/snapshot-wave1.log; grep -c "✘" /tmp/snapshot-wave1.log`
Expected: a large number of failures. Extract the failing classes:

```bash
grep -oE "SpudSnapshotTests/[A-Za-z]+Tests" /tmp/snapshot-wave1.log | sort -u
```

- [ ] **Step 3: Re-record one class at a time**

For each class from Step 2, in turn:

```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/<ClassName> \
  -destination "$(scripts/resolve-test-destination.sh --reference)" \
  -skipPackagePluginValidation -skipMacroValidation test
```

Re-recording follows the ceremony in `SpudSnapshotTests/CLAUDE.md`: flip the class to record mode, run (records + fails), flip back, run again (verifies).

**Inspect each re-recorded image before staging it.** The expected diff is chrome only: translucent bars, content visible beneath them, revised control shapes. A diff that changes *content* layout — text reflowing, cells resizing, images cropping — is a regression introduced by Phase 0, not a glass change. Stop and investigate rather than blessing it.

- [ ] **Step 4: Stage explicitly, per class**

```bash
git add SpudSnapshotTests/__Snapshots__/<ClassName>/
```

Never `git add -A`. If committed refs you did not touch show as modified, run `git annex restage` — that marker is cosmetic.

- [ ] **Step 5: Full verify**

Run: `make snapshot`
Expected: `✔ Test run with N tests in M suites passed`.

- [ ] **Step 6: Commit**

```bash
git commit -m "test: re-record snapshots for Liquid Glass chrome

Phase 0 changed bar rendering on every screen. Diffs are chrome-only;
content layout is unchanged."
```

---

## Phase 1 — Chrome correctness

### Task 6: Remove custom backgrounds from sheets and popovers

Apple's adoption guide is explicit: remove custom background views from popovers and sheets so they match the system experience.

**Files:**
- Modify: whichever of the 47 presentation sites carry a custom background (enumerate in Step 1)

**Interfaces:**
- Consumes: Phase 0.
- Produces: sheets and popovers on the stock glass material.

- [ ] **Step 1: Enumerate presentation sites**

Run:

```bash
grep -rn "sheetPresentationController\|popoverPresentationController\|modalPresentationStyle = .popover\|modalPresentationStyle = .pageSheet\|modalPresentationStyle = .formSheet" --include='*.swift' Spud/
```

- [ ] **Step 2: Find the ones with custom backdrops**

For each presented view controller found in Step 1, check its root view for a `backgroundColor` assignment, a `UIVisualEffectView` backdrop, or a custom `overrideUserInterfaceStyle`. Remove those; let the presentation controller supply the background.

Keep an explicit `backgroundColor` only where the presented content is genuinely opaque content (a full-screen editor, the media viewer) rather than a floating panel.

- [ ] **Step 3: Check edge clearance**

iOS 26 sheets have a larger corner radius and half sheets are inset from the display edge. For each sheet, confirm no control or text is clipped by the rounder corners, and that content peeking between an inset half-sheet and the display edge looks intentional.

- [ ] **Step 4: Verify**

Run: `mint run swiftformat Spud && make build && make snapshot`
Expected: build succeeds. Snapshot classes covering the changed sheets fail; re-record them per the Task 5 Step 3 ceremony and stage explicitly.

- [ ] **Step 5: Commit**

```bash
git add <explicit paths>
git commit -m "fix: drop custom sheet and popover backgrounds

Custom backdrops overlay the system's glass material. The presentation
controller supplies the background."
```

---

### Task 7: Correct scroll edge effects

**Files:**
- Modify: view controllers with custom bars overlaying scroll views (enumerate in Step 1)

**Interfaces:**
- Consumes: Phase 0.
- Produces: edge effects that shape themselves correctly around overlaying controls, with the style left at the system default.

- [ ] **Step 1: Find existing overrides and missing registrations**

Run:

```bash
grep -rn "scrollEdgeEffectStyle\|topEdgeEffect\|bottomEdgeEffect\|UIScrollEdgeElementContainerInteraction\|setContentScrollView" --include='*.swift' Spud/
```

- [ ] **Step 2: Remove style overrides**

Delete any assignment that pins `scrollEdgeEffectStyle` / `topEdgeEffect.style` / `bottomEdgeEffect.style` away from `.automatic`.

**Rationale to preserve in the commit message, not a code comment:** in iOS 27 `.automatic` stops switching between `soft` and `hard` and grows its own visuals. Pinning `.soft` today produces a bar that no longer matches the system on iOS 27.

- [ ] **Step 3: Register content scroll views**

For every view controller whose bar overlays a scroll view that is not the controller's primary view, call `setContentScrollView(_:for:)` so the bar observes the right scroll view for its edge effect.

- [ ] **Step 4: Register custom overlay containers**

For any custom container view holding controls that sit over a scroll view edge (the media viewer control bars, the feed's floating affordances), add a `UIScrollEdgeElementContainerInteraction` for the relevant edge so the effect shapes itself around the descendants.

- [ ] **Step 5: Verify**

Run: `mint run swiftformat Spud && make build`
Expected: succeeds. Then launch on the booted simulator, scroll the feed and a post detail, and confirm content fades correctly under the bars rather than sliding under a hard line or vanishing abruptly.

- [ ] **Step 6: Commit**

```bash
git add <explicit paths>
git commit -m "fix: let the system own scroll edge effect style

iOS 27 gives .automatic its own visuals rather than switching between
soft and hard, so a pinned style stops matching the system. Custom
overlay containers now register a scroll edge element interaction."
```

---

### Task 8: Make nested corners concentric

**Files:**
- Modify: a subset of the 135 `cornerRadius` sites (triage in Step 2)

**Interfaces:**
- Consumes: Phase 0.
- Produces: nested rounded containers whose curvature is concentric with their parent.

- [ ] **Step 1: Enumerate**

Run: `grep -rn "cornerRadius = \|cornerRadius:" --include='*.swift' Spud/ SpudUIKit/`
Expected: 135 hits.

- [ ] **Step 2: Triage each hit against this rule**

- **Convert** to `view.cornerConfiguration = .corners(radius: .containerConcentric())` when the view is nested inside a rounded or glass container and its radius should track the parent's curvature. Pass `minimum:` to `containerConcentric(minimum:)` where the corner must not collapse to square in a container with no radius. For a pill, `.capsule()` replaces the `cornerRadius = height / 2` idiom.
- **Leave alone** when the radius is part of the content's own identity: avatars, community icons, thumbnails, media tiles, share-card artwork.

Expect a minority to convert.

- [ ] **Step 3: Record the triage**

Write the decision list into the commit body — one line per site, `path:line — convert` or `path:line — keep (reason)`. A reviewer must be able to check the judgement, not just the mechanics. There is no automated test for "is this corner concentric".

- [ ] **Step 4: Verify**

Run: `mint run swiftformat Spud SpudUIKit && make build && make snapshot`
Expected: build succeeds; re-record only the snapshot classes covering converted views.

- [ ] **Step 5: Commit**

```bash
git add <explicit paths>
git commit -F <file containing the triage list>
```

---

### Task 9: Adopt glass button configurations

**Files:**
- Modify: a subset of the 59 `UIButton.Configuration` sites (triage in Step 2)

**Interfaces:**
- Consumes: Phase 0.
- Produces: buttons that float over content rendered on glass.

- [ ] **Step 1: Enumerate**

Run: `grep -rn "UIButton.Configuration\." --include='*.swift' Spud/`

- [ ] **Step 2: Triage each hit**

- Floats **over** content (media viewer controls, overlay affordances, floating actions): `.glass()` or, for the primary action in its context, `.prominentGlass()`.
- Sits **in** content (inline row actions, form buttons, empty-state calls to action): unchanged — keep `.filled()` / `.tinted()` / `.plain()`.

Apply the same triage to SwiftUI buttons in the files listed by `grep -rln "^import SwiftUI" Spud/`, using `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)`.

- [ ] **Step 3: Record the triage**

As in Task 8, list the decisions in the commit body.

- [ ] **Step 4: Verify tap targets survive**

For each converted button, confirm it is still hit-test reachable. A button inside an `isUserInteractionEnabled = false` superview renders fine but can never be tapped, and neither `sendActions(for:)` nor VoiceOver activation catches it. Follow the pattern in `SpudTests` (`ImageBlockViewTests.failedPlateButtonsAreHitTestReachable`) for any converted button that is not already covered.

- [ ] **Step 5: Verify**

Run: `mint run swiftformat Spud && make build && make test`
Expected: build succeeds, tests pass. Re-record affected snapshot classes.

- [ ] **Step 6: Commit**

```bash
git add <explicit paths>
git commit -F <file containing the triage list>
```

---

### Task 10: Bar and header hygiene

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift:495`
- Modify: `Spud/Scenes/Account/InstanceDetail/Components/InstanceAdminsView.swift:197`
- Modify: toolbar-configuring view controllers (enumerate in Step 3)

**Interfaces:**
- Consumes: Phase 0.
- Produces: title-case section headers and grouped toolbar items.

- [ ] **Step 1: Fix the uppercased section headers**

iOS 26 lists use title-style capitalization for section headers. Change `InstanceDetailViewController.swift:495` from `captionLabel.text = label.uppercased()` to `captionLabel.text = label`, and `InstanceAdminsView.swift:197` from `titleLabel.text = title.uppercased()` to `titleLabel.text = title`.

Check the call sites supply title-case strings; if a caller passes `"admins"`, fix the caller's literal to `"Admins"` rather than re-adding a transform.

- [ ] **Step 2: Confirm the other uppercase sites stay**

Run: `grep -rn "\.uppercased()" --include='*.swift' Spud/`
Expected: the remaining hits are single-letter avatar monograms (`ShareCardCommunityIconView`, `ProfileAvatarView`, `InstanceBannerHeaderView`, `DiscoverView`, `SubscriptionsView`) and language codes (`SiteListViewController`, `InstanceDetailViewController:541`). Leave all of them.

- [ ] **Step 3: Group toolbar items**

Run: `grep -rn "toolbarItems\|rightBarButtonItems\|leftBarButtonItems" --include='*.swift' Spud/`

For each bar with multiple items: group items that perform related actions, and separate groups with `UIBarButtonItem.fixedSpace(_:)`. Within a group that shares a background, use all icons or all text, never a mix. Every icon-only item keeps an `accessibilityLabel`.

- [ ] **Step 4: Fix item hiding**

Run: `grep -rn "customView?.isHidden\|\.customView?.alpha" --include='*.swift' Spud/`

Where an item is hidden by hiding its inner view, switch to `UIBarButtonItem.isHidden` — hiding the view leaves an empty item slot in the bar.

- [ ] **Step 5: Adopt `UIBarButtonItem.badge` where a count is hand-drawn**

Only for bar buttons carrying a hand-drawn count decoration. The Inbox **tab** badge is set via `applyUnreadBadge` on the tab bar item and is not in scope here — Task 12 moves it to `UITab`.

- [ ] **Step 6: Verify**

Run: `mint run swiftformat Spud && make build && make test`
Expected: passes. Re-record affected snapshot classes.

- [ ] **Step 7: Commit**

```bash
git add <explicit paths>
git commit -m "fix: title-case section headers and group toolbar items

iOS 26 lists capitalize section headers in title style rather than
rendering them uppercase. Toolbar items are grouped by relatedness with
fixed spacers between groups."
```

---

### Task 11: Accessibility and display-settings audit, pass 1

**Files:**
- Modify: whichever surfaces fail the audit

**Interfaces:**
- Consumes: Tasks 6-10.
- Produces: an app that is legible and correct under the three settings that modify Liquid Glass. Repeated as Task 18 after the bespoke-glass conversions.

- [ ] **Step 1: Audit under Reduce Transparency**

Enable it:

```bash
xcrun simctl ui booted increase_contrast disabled
xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool true
```

Walk the feed, post detail, community, search, inbox, account and preferences. Expected: bars become opaque; text remains legible; nothing disappears or renders as an unreadable low-contrast smear.

- [ ] **Step 2: Audit under Increase Contrast**

Run: `xcrun simctl ui booted increase_contrast enabled`
Expected: control borders strengthen; no custom color falls below contrast requirements.

- [ ] **Step 3: Audit under Reduce Motion**

Enable Reduce Motion in Settings > Accessibility > Motion on the simulator. Expected: glass morph animations are replaced by cross-fades; no animation is left running that the setting should have suppressed.

- [ ] **Step 4: Fix what fails**

Stock components adapt automatically, so any failure is ours. The usual cause is a hardcoded color that assumed a specific backdrop. Replace hardcoded colors with system semantic colors, which carry increased-contrast variants.

- [ ] **Step 5: Reset the simulator settings**

```bash
xcrun simctl ui booted increase_contrast disabled
xcrun simctl spawn booted defaults write com.apple.Accessibility ReduceTransparencyEnabled -bool false
```

- [ ] **Step 6: Verify and commit**

Run: `mint run swiftformat Spud && make build && make test`

```bash
git add <explicit paths>
git commit -m "fix: accessibility fixes for Liquid Glass display settings

Audited under Reduce Transparency, Increase Contrast and Reduce Motion."
```

If nothing failed, record that in the task notes and skip the commit — an empty commit is noise.

---

## Phase 2 — Structure

### Task 12: Migrate to `UITab` with a search-role tab

The tab bar is built with the legacy API and addressed by hard-coded indices. Both change here. This is the task most likely to break UI tests.

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` — tab construction (`:344-397`), `inboxTabIndex` (`:59`), `applyUnreadBadge` (`:416-422`), `selectAccountTab` (`:576-584`), `selectCommunitiesTab` (`:588-596`), `selectSearch` (`:844-852`)
- Modify: `SpudUITests/` and `IPadSplitUITests/` — any tab-index or tab-order assumption

**Interfaces:**
- Consumes: Phase 0 and Phase 1.
- Produces: `UITab`-based tabs addressed by stable string identifiers. Later code must never index into `tabBarController.viewControllers`.

- [ ] **Step 1: Define tab identifiers**

Add to `MainWindow`, replacing the `inboxTabIndex` / `accountTabIndex` / `communitiesTabIndex` constants:

```swift
    /// Stable identifiers for the root tabs.
    ///
    /// Tabs are addressed by identifier, never by index: the system relocates
    /// the search tab to the trailing edge, so an index is not a stable
    /// reference to a tab.
    ///
    /// Search is absent deliberately — `UISearchTab` assigns its own
    /// system identifier, available as the type property
    /// `UISearchTab.identifier`.
    private enum TabIdentifier {
        static let posts = "posts"
        static let communities = "communities"
        static let inbox = "inbox"
        static let account = "account"
    }
```

- [ ] **Step 2: Build tabs instead of view controllers**

Replace the `tabBarController.setViewControllers([...], animated: false)` call with `setTabs(_:animated:)`.

Each non-search tab becomes a `UITab(title:image:identifier:viewControllerProvider:)`. `UITab` has no `selectedImage` initializer parameter — it is a settable property, so the Communities tab's `person.3.fill` is assigned after construction:

```swift
        let communitiesTab = UITab(
            title: NSLocalizedString("Communities", comment: "Communities tab title"),
            image: UIImage(systemName: "person.3"),
            identifier: TabIdentifier.communities
        ) { _ in
            communitiesNavigationController
        }
        communitiesTab.selectedImage = UIImage(systemName: "person.3.fill")
```

Search becomes a `UISearchTab`, whose only initializer takes the provider alone — it supplies its own system-localized title, image and identifier:

```swift
        let searchTab = UISearchTab { _ in
            searchNavigationController
        }
```

Delete the per-controller `tabBarItem` assignments (for example `communitiesNavigationController.tabBarItem = UITabBarItem(...)` at `:354`) — title and image now live on the `UITab`. Keep the existing titles, SF Symbol names and `enableForwardNavigationGesture()` calls.

Update the `// Tabs: Posts | Communities | Search | Inbox | Account` comment: the system places the search tab at the trailing edge, so the rendered order is Posts | Communities | Inbox | Account | Search.

- [ ] **Step 3: Address tabs by identifier**

- `applyUnreadBadge(_:)`: set `UITab.badgeValue` on the tab looked up by `TabIdentifier.inbox`, instead of `tabBarController.tabBar.items[3].badgeValue`.
- `selectAccountTab()` / `selectCommunitiesTab()`: select by identifier and pop the resolved tab's `viewController` (cast to `UINavigationController`) to root.
- `selectSearch(query:)`: replace both the `selectedIndex = 2` and the `viewControllers[2]` lookup with a lookup for `UISearchTab.identifier`.

Delete the `inboxTabIndex`, `accountTabIndex` and `communitiesTabIndex` constants once nothing references them.

- [ ] **Step 4: Opt into tab bar minimization**

Where the tab bar controller is configured, add:

```swift
        // Let the tab bar recede on scroll so the feed gets the full screen.
        tabBarController.tabBarMinimizeBehavior = .onScrollDown
```

- [ ] **Step 5: Build**

Run: `mint run swiftformat Spud && make build`
Expected: succeeds. Then run `grep -rn "selectedIndex\|viewControllers\[" Spud/Scenes/MainWindow/MainWindow.swift` and confirm no index-based tab addressing survives.

- [ ] **Step 6: Fix the UI tests**

Run: `make test`
Expected: UI-test failures where a test taps a tab by index or by position. Update those queries to select the tab by its accessible name. Search moving to the trailing edge is the expected new behavior, not a bug to work around.

- [ ] **Step 7: Verify on device**

Launch on the booted simulator. Confirm: five tabs; Search rendered at the trailing edge and visually separated; the Inbox badge appears with an unread count; scrolling the feed down minimizes the tab bar and scrolling up restores it.

- [ ] **Step 8: Re-record affected snapshots and commit**

```bash
git add Spud/Scenes/MainWindow/MainWindow.swift SpudUITests <explicit snapshot paths>
git commit -m "feat: adopt UITab with a search-role tab

Search becomes a UISearchTab, which the system relocates to the trailing
edge. Tabs are addressed by stable identifier rather than by index,
since the relocation makes indices meaningless. The tab bar now
minimizes on scroll down."
```

---

### Task 13: Extend content beneath the iPad sidebar

**Files:**
- Modify: the iPad split's detail-column hero surfaces — `Spud/Scenes/Community/Content/CommunityHeaderView.swift`, `Spud/Scenes/Person/Content/PersonHeaderView.swift`, `Spud/Scenes/Account/InstanceDetail/Components/InstanceBannerHeaderView.swift`

**Interfaces:**
- Consumes: Task 12.
- Produces: banner imagery that reads as extending under the sidebar.

- [ ] **Step 1: Wrap each hero image in a background extension view**

For each banner/hero image view in the detail column, wrap it in a `UIBackgroundExtensionView` and assign the image view to `contentView`. The extension view mirrors and blurs the adjacent content to give the impression of stretching under the sidebar, without actually placing content there.

Leave `automaticallyPlacesContentView` at its default unless the content needs to ignore safe-area placement, in which case set it to `false` and constrain the content view explicitly.

- [ ] **Step 2: Verify on iPad**

Respect the single-booted-simulator rule: shut down the iPhone, boot `iPad Pro 11-inch (M5)` by id, run the app, then shut the iPad down and reboot the reference iPhone afterwards.

Expected: a community or person banner in the detail column visually continues under the sidebar rather than stopping at the column edge.

The `iPad Pro 11-inch (M4)` simulator on the iOS 18.5 runtime is a dud for this app and dyld-crashes at launch — use the M5.

- [ ] **Step 3: Verify and commit**

Run: `mint run swiftformat Spud && make build && make test`

```bash
git add <explicit paths>
git commit -m "feat: extend hero imagery beneath the iPad sidebar

UIBackgroundExtensionView mirrors and blurs adjacent content so banners
read as continuing under the sidebar."
```

---

### Task 14: Spike `tabSidebar` mode and record the decision

Spud already ships a bespoke `MainWindowSplitViewController` (sidebar + detail). `UITabBarController.Mode.tabSidebar` adds a *second* sidebar concept. This task decides whether they can coexist. **A rejection is an acceptable outcome; an unexamined omission is not.**

**Files:**
- Modify (only if adopted): `Spud/Scenes/MainWindow/MainWindow.swift`
- Create: notes for the ADR written in Task 19

**Interfaces:**
- Consumes: Task 12 (`UITab` objects are a prerequisite for sidebar mode).
- Produces: either `tabSidebar` adopted, or a written rationale for rejecting it.

- [ ] **Step 1: Try it**

On a throwaway commit, set `tabBarController.mode = .tabSidebar` and run on `iPad Pro 11-inch (M5)`.

- [ ] **Step 2: Evaluate against three questions**

1. Does the tab sidebar collide with `MainWindowSplitViewController`'s own sidebar — two sidebars on screen, or a sidebar inside a sidebar?
2. Does the Posts tab (itself a split view controller) still behave correctly as a tab's content in sidebar mode?
3. Is the result better than today's layout for a user, or merely more modern?

- [ ] **Step 3: Decide and record**

If all three answers are favourable, keep the change and continue to Step 4. Otherwise `git reset --hard` the spike and write the rationale into `/tmp/tabsidebar-decision.md` for Task 19 to fold into the ADR — specifically which of the three questions failed and what was observed.

- [ ] **Step 4: If adopted, verify and commit**

Run: `mint run swiftformat Spud && make build && make test`

```bash
git add Spud/Scenes/MainWindow/MainWindow.swift
git commit -m "feat: adopt tab sidebar mode on iPad"
```

If rejected, there is no commit from this task — only notes carried into Task 19.

---

## Phase 3 — Bespoke glass

### Task 15: Add glass tokens and convert the media viewer chrome

The media viewer is the clearest case for glass: floating controls over photos. Its two bars belong in one container effect so they merge and morph correctly.

**Files:**
- Create: `SpudUIKit/Design/GlassTokens.swift`
- Modify: `Spud/Scenes/MediaViewer/MediaViewerViewController.swift:86` (top chrome), `:143` (bottom chrome)

**Interfaces:**
- Consumes: Phase 0.
- Produces: `GlassTokens.controlSurface` (a configured `UIGlassEffect`) and `GlassTokens.controlContainerSpacing` (`CGFloat`), consumed by Task 16.

- [ ] **Step 1: Create the tokens file**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Shared Liquid Glass constants for the app's own floating chrome.
///
/// These are tokens, not a wrapper: call sites build their own
/// `UIVisualEffectView` and apply glass through UIKit's API directly. The
/// tokens exist so the handful of bespoke glass surfaces agree on material and
/// spacing rather than each choosing their own.
///
/// Glass belongs to the navigation layer. Do not apply these to content — see
/// `NsfwBlurOverlayView`, which is deliberately a blur because a content
/// obscurer must not be see-through.
public enum GlassTokens {
    /// The material for floating controls layered over content.
    public static var controlSurface: UIGlassEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        return effect
    }

    /// Distance at which sibling glass elements begin to merge, for a
    /// `UIGlassContainerEffect` grouping related controls.
    public static let controlContainerSpacing: CGFloat = 12
}
```

- [ ] **Step 2: Register the file and build**

Run: `make project && make build`
Expected: succeeds. (XcodeGen picks up new sources; a stale project yields spurious "cannot find in scope" errors.)

- [ ] **Step 3: Convert the media viewer chrome**

At `MediaViewerViewController.swift:86` and `:143`, replace:

```swift
let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
```

and

```swift
let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
```

with `UIVisualEffectView(effect: GlassTokens.controlSurface)`.

Then group both bars under a shared `UIGlassContainerEffect` whose `spacing` is `GlassTokens.controlContainerSpacing`, so they merge and morph as one system rather than two independent panes.

Note the `-Dark` suffix disappears: glass adapts to what is behind it, so a fixed dark variant is no longer meaningful.

- [ ] **Step 4: Verify visually**

Launch, open a post with an image, tap to open the media viewer. Expected: control bars read as glass over the photo — refracting the image beneath rather than flatly frosting it — and the two bars behave as one material when both are visible.

Verify the controls remain legible over both a very light and a very dark image.

- [ ] **Step 5: Verify and commit**

Run: `mint run swiftformat Spud SpudUIKit && make build && make test`

```bash
git add SpudUIKit/Design/GlassTokens.swift Spud/Scenes/MediaViewer/MediaViewerViewController.swift project.yml
git commit -m "feat: media viewer chrome on Liquid Glass

Floating controls over photos are exactly what glass is for. Both bars
share a container effect so they merge and morph as one material.
Shared tokens keep the bespoke glass surfaces consistent."
```

---

### Task 16: Convert the remaining bespoke chrome

**Files:**
- Modify: `Spud/Utils/Views/LowResPreviewPillView.swift:33`
- Modify: `Spud/Scenes/Common/Toast/ToastPresenter.swift`
- Modify: `Spud/Scenes/Community/Content/CommunityHeaderView.swift:205`
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift:636`

**Interfaces:**
- Consumes: `GlassTokens` from Task 15.
- Produces: no remaining iOS 18-era blur on floating chrome.

- [ ] **Step 1: Convert each site**

Replace each `UIVisualEffectView(effect: UIBlurEffect(style: ...))` with `UIVisualEffectView(effect: GlassTokens.controlSurface)`.

`ToastPresenter` floats over all content and is the strongest candidate after the media viewer. `LowResPreviewPillView` is a small floating pill. `CommunityHeaderView:205` and `InstanceDetailViewController:636` are banner scrims — check each renders as intended over a banner image; if a scrim's job is legibility rather than chrome, keep it a blur and note why in the commit body.

- [ ] **Step 2: Confirm the excluded sites are untouched**

Run: `grep -rn "UIBlurEffect" --include='*.swift' Spud/`
Expected: the surviving hits are `Spud/Scenes/Shared/NsfwBlurOverlayView.swift:24` and nothing under `Spud/Scenes/ShareAsImage/`. Both exclusions are deliberate — an NSFW cover must not be see-through, and share cards must render identically off-screen.

- [ ] **Step 3: Verify**

Run: `mint run swiftformat Spud && make build && make test`
Expected: passes.

- [ ] **Step 4: Commit**

```bash
git add <explicit paths>
git commit -m "feat: convert remaining floating chrome to Liquid Glass

NsfwBlurOverlayView stays a blur: a content obscurer must not be
see-through. ShareAsImage cards are untouched by design."
```

---

### Task 17: Snapshot re-record wave 2 and accessibility pass 2

**Files:**
- Modify: snapshot references covering the Phase 2 and Phase 3 surfaces

**Interfaces:**
- Consumes: Tasks 12-16.
- Produces: a green snapshot baseline and a verified accessibility posture on the new glass surfaces.

- [ ] **Step 1: Re-record**

Run: `make snapshot 2>&1 | tee /tmp/snapshot-wave2.log`

Re-record only the failing classes, one at a time, following the Task 5 Step 3 ceremony. Inspect each diff: expected changes are the tab bar, the media viewer chrome, banner headers and the toast. Anything else is a regression.

Note: `SpudSnapshotTests/CLAUDE.md` documents that blur requires on-screen rendering. Glass has the same constraint — if a converted surface snapshots as transparent or black, the host window is not on screen.

- [ ] **Step 2: Repeat the accessibility audit**

Repeat Task 11's Steps 1-3 against the converted surfaces specifically: media viewer chrome, toast, pill, banner scrims. These are custom glass, so unlike stock components they do not adapt for free.

Under Reduce Transparency, each must become opaque and stay legible. Under Increase Contrast, controls must keep sufficient contrast against both light and dark photos.

- [ ] **Step 3: Full verify**

Run: `make snapshot && make test`
Expected: both pass.

- [ ] **Step 4: Commit**

```bash
git add <explicit snapshot paths> <any accessibility fixes>
git commit -m "test: re-record snapshots for structural and bespoke glass changes"
```

---

## Phase 4 — Adaptivity hygiene

### Task 18: Remove `UIScreen.main`

iOS 27 makes iPhone apps fully resizable under iPhone Mirroring and on iPad. A scene's screen is not the main screen, and a scene's size is not the screen's size.

**Files:**
- Modify: `Spud/Scenes/Activity/ActivityFootprintRailView.swift:38`
- Modify: `Spud/Scenes/Person/Content/PersonHeaderView.swift:285`
- Modify: `Spud/Scenes/Common/Toast/ToastPresenter.swift:162`
- Modify: `Spud/Scenes/Community/Content/CommunityHeaderView.swift:318`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailCrossPostsCell.swift:97`
- Modify: `Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift:314`
- Modify: `Spud/Scenes/Account/InstanceDetail/Components/InstanceWrapView.swift:36`

**Interfaces:**
- Consumes: nothing from earlier phases.
- Produces: no `UIScreen.main` references in shipped targets.

- [ ] **Step 1: Convert the five hairline widths**

`ActivityFootprintRailView.swift:38`, `PersonHeaderView.swift:285`, `ToastPresenter.swift:162`, `CommunityHeaderView.swift:318` and `PostDetailCrossPostsCell.swift:97` all compute a hairline as `1.0 / UIScreen.main.scale`. Replace with `1.0 / traitCollection.displayScale`.

Trait collections are tracked automatically inside `layoutSubviews()`, `updateConfiguration(using:)` and `draw(_:)`, so a view that computes its hairline in one of those re-computes it when the display scale changes. If the value is cached in a stored property set at init, move the computation into `layoutSubviews()` — a cached scale is exactly what breaks when a window moves to a different display.

`PostDetailCrossPostsCell.swift:97` already carries a comment acknowledging `UIScreen.main` is soft-deprecated; delete the comment along with the fallback it explains.

- [ ] **Step 2: Fix the two real adaptivity bugs**

`ProfileBannerHeaderView.swift:314` computes `let screenWidth = UIScreen.main.bounds.width` and `InstanceWrapView.swift:36` falls back to `UIScreen.main.bounds.width` when `bounds.width` is zero. Both size content to the *screen* rather than to the space the view actually has, so they render wrong in a resized scene.

Replace with the view's own `bounds.width`, or its `superview?.bounds.width`. Where the width is genuinely needed before layout, defer the computation to `layoutSubviews()` rather than reaching for a screen-sized fallback.

- [ ] **Step 3: Verify none remain**

Run: `grep -rn "UIScreen.main\|UIScreen.screens" --include='*.swift' Spud/ SpudUIKit/ SpudDataKit/ SpudUtilKit/ Shared/ SpudWidget/`
Expected: no output.

- [ ] **Step 4: Verify at a non-device size**

Run the app on the booted simulator and exercise the profile banner and the instance-detail wrap view in both orientations and, on iPad, in a narrow split. Expected: content sizes to its container at every width, with no clipping or overflow at sizes that are not a whole device width.

- [ ] **Step 5: Verify and commit**

Run: `mint run swiftformat Spud && make build && make test`

```bash
git add <explicit paths>
git commit -m "fix: size content to the view, not the screen

iOS 27 makes iPhone apps fully resizable under iPhone Mirroring and on
iPad, where the scene's size is not the screen's size. Hairlines now use
traitCollection.displayScale and the two screen-width layouts use their
own bounds."
```

---

### Task 19: Documentation

**Files:**
- Modify: the appearance/theming capability doc under `docs/features/`
- Modify: `docs/features/README.md` (**both** index sections)
- Create: `docs/adr/NNNN-liquid-glass-adoption.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: every preceding task, plus the `tabSidebar` decision notes from Task 14.
- Produces: docs consistent with shipped behavior.

- [ ] **Step 1: Find the affected feature docs**

Run: `grep -rln "True Black\|trueBlack\|theme" docs/features/`

Update each for shipped behavior: the theme picker now offers System / Light / Dark, a previously-selected True Black degrades to Dark, and Search is the trailing tab. Keep `Status:` honest.

- [ ] **Step 2: Update both README index sections**

`docs/features/README.md` carries a capability table **and** a "Feature coverage by area" map. They drift independently — update both.

- [ ] **Step 3: Write the ADR**

Find the next number: `ls docs/adr/`. The ADR covers three decisions in one document:

1. **Adopt Liquid Glass by deleting custom appearance code**, with the iOS 26.0 floor as a consequence.
2. **Retire the True Black theme** — it existed only to force opaque bars, which is precisely what the glass material replaces; a persisted selection degrades to Dark via a decode-time migration.
3. **The `tabSidebar` decision** from Task 14 — adopted, or rejected with the observed reason.

Follow the format of `docs/adr/0001-grdb-over-swiftdata.md`.

- [ ] **Step 4: Update CLAUDE.md**

Three changes:
- the deployment floor is iOS 26.0,
- the `Theme` token layer is gone — use system colors directly,
- tabs are addressed by `UITab` identifier, never by index.

- [ ] **Step 5: Audit the docs mechanically**

Run the feature-docs audit script (see the `ddenis:feature-docs` skill) to check index consistency.

- [ ] **Step 6: Commit**

```bash
git add docs CLAUDE.md
git commit -m "docs: record the Liquid Glass adoption

Feature docs, an ADR covering the adoption, the True Black retirement
and the tab sidebar decision, plus the CLAUDE.md conventions that
changed."
```

---

### Task 20: Final verification and merge

**Files:** none

**Interfaces:**
- Consumes: Tasks 1-19.
- Produces: `feat/liquid-glass` merged into local `main`.

- [ ] **Step 1: Format, then full verify**

Run, in this order (formatting after a green verify can slip a rewrite into the commit):

```bash
mint run swiftformat Spud SpudUIKit SpudUtilKit SpudDataKit SpudUIKitTests SpudTests
make build
make test
make snapshot
```

Expected: all green. Trust the `✔ Test run with N tests in M suites passed` lines, not the XCTest "Executed 0 tests" summary.

- [ ] **Step 2: Confirm the acceptance criteria**

```bash
grep -rn '\bTheme\.' --include='*.swift' Spud/ SpudUIKit/ | grep -v 'ThemeManager\.\|AppTheme\.'   # expect none
grep -rn "UIScreen.main" --include='*.swift' Spud/ SpudUIKit/ Shared/                              # expect none
grep -rn "UINavigationBar.appearance()\|UITabBar.appearance()" --include='*.swift' Spud/           # expect none
grep -rn "UIBlurEffect" --include='*.swift' Spud/    # expect only NsfwBlurOverlayView
grep -rn "selectedIndex\|viewControllers\[" Spud/Scenes/MainWindow/MainWindow.swift                # expect none
```

- [ ] **Step 3: Manual device pass**

iPhone 17 Pro and iPad Pro 11-inch (M5), both orientations, respecting the single-booted-simulator rule. Walk: feed, post detail, media viewer, community, person, search, inbox, account, preferences, composer.

Confirm: bars are glass and content scrolls beneath them; the tab bar minimizes on scroll; Search is the trailing tab; the media viewer chrome reads as glass; the theme picker offers three options.

- [ ] **Step 4: Re-check main before merging**

Local `main` is a shared checkout that advances mid-task.

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git log --oneline main -5
git diff --name-only $(git merge-base main feat/liquid-glass) feat/liquid-glass > /tmp/ours.txt
git diff --name-only $(git merge-base main feat/liquid-glass) main > /tmp/theirs.txt
comm -12 <(sort /tmp/ours.txt) <(sort /tmp/theirs.txt)
```

Any overlapping file needs review before merging. If the shared checkout has uncommitted edits to a file this branch also touches, the merge is blocked — do not stash another agent's work.

- [ ] **Step 5: Merge**

From the shared checkout with `main` checked out, run `git annex restage` **first** (cosmetic annex markers otherwise block the merge), then:

```bash
git merge --no-ff feat/liquid-glass
```

- [ ] **Step 6: Clean up the worktree**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
rm -rf .claude/worktrees/liquid-glass
git worktree prune
git branch -d feat/liquid-glass
```

`git worktree remove` fails in this repo (the worktree's `.git` is a symlink, not the gitdir file git expects) — the `rm -rf` above is the working form.

---

## Deferred to a follow-up (blocked on Xcode 27)

Not part of this plan. Recorded so they are not rediscovered:

- `UITabBarController.prominentTabIdentifier`
- iPhone sidebar opt-in: `tabBarController.sidebar.preferredPlacement = .sidebar`, gated on `sidebar.isAvailable`
- `UINavigationItem.barMinimizationBehavior` / `barMinimizationSafeAreaAdjustment`
- Re-evaluate scroll edge effect styles against iOS 27's revised `.automatic` visuals
- `UIMenuElement.preferredImageVisibility`
- View Annotations (annotating views with `AppEntity`) for the Ask Siri menu entry point
- Icon Composer layered app icon for the default icon and the five `AppIconVariant` alternates

---

### Task 21: Let content flow beneath the glass bars

Added during execution, after Task 7's review classified every
`safeAreaLayoutGuide.topAnchor` site in the app. Liquid Glass's premise is that
content passes under translucent chrome; a scroll view pinned to the safe area
leaves a dead zone under the bar with nothing to refract, which reads as
half-adopted.

Run this task AFTER Task 18 and BEFORE Task 19 (so the docs cover it).

**Files (the six genuine dead zones — the other twelve sites were checked and
are correct):**
- Modify: `Spud/Scenes/Inbox/DMThreadViewController.swift:174` (highest impact:
  a core, frequently-visited screen whose threads are genuinely long)
- Modify: `Spud/Scenes/PostDetail/SelectText/SelectableTextViewController.swift:60`
- Modify: `Spud/Scenes/Composer/ComposerViewController.swift:140`
- Modify: `Spud/Scenes/Composer/NewPostViewController.swift:300`
- Modify: `Spud/Scenes/Composer/PendingPostViewController.swift:237`
- Modify: `Spud/Scenes/ShareAsImage/ShareAsImageAltTextViewController.swift:88`
  (lowest impact: a short sheet rarely tall enough to scroll)

**Explicitly NOT in scope** — verified correct and must not be changed:
`PostListViewController`, `PostDetailViewController`, `SearchViewController`
(already pin to `view.topAnchor`); `RegisterViewController.swift:372` (its
`scrollView` already pins to `view.topAnchor`; the safe-area anchor is on an
inner `contentStackView` as resting padding — the correct Apple pattern);
`InboxViewController.swift:201` (pins a sticky segmented control, not scroll
content); `MediaViewerViewController.swift:404` (sizes a bar background, not
scroll content); `FeedLoadingSkeletonView.swift:65` (transient placeholder for a
table that is already correct); and the eight screens with no scroll view at all.

- [ ] **Step 1: Repin scroll content to the view, not the safe area**

For each of the six, change the scroll/text view's top constraint from
`view.safeAreaLayoutGuide.topAnchor` to `view.topAnchor`.

- [ ] **Step 2: Keep content from starting underneath the bar**

Repinning alone makes content start hidden behind the bar. Verify each scroll
view's `contentInsetAdjustmentBehavior` is `.automatic` (the default) so UIKit
inserts the safe-area content inset — content then RESTS below the bar and
SCROLLS under it, which is the desired behavior. Where a view overrides that to
`.never`, either restore `.automatic` or set the equivalent `contentInset`
explicitly. State per file which applied.

- [ ] **Step 3: Verify each screen visually**

Launch on the booted iPhone 17 Pro. For each screen, scroll and confirm content
passes under the nav bar with the glass effect refracting it, and that at rest
the first row is not hidden behind the bar. `DMThreadViewController` also has an
`inputAccessoryView` — confirm the bottom edge still behaves.

- [ ] **Step 4: Verify and commit**

Run `mint run swiftformat Spud && make build && make test`, re-record any
affected snapshot classes one at a time per the standard ceremony, and commit
with explicit paths.

```
git add <explicit paths>
git commit -m "fix: let scroll content flow beneath the glass bars

A scroll view pinned to the safe area leaves a dead zone under a
translucent bar with nothing to refract. Content now rests below the bar
and scrolls under it."
```
