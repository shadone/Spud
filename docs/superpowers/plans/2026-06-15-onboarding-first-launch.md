# Onboarding-first launch (slice A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the crashing first-launch account auto-bootstrap with an onboarding gate — a Welcome screen whose "Get started" CTA enters the existing instance-picker flow, with `MainWindow` showing onboarding as its root until the first account is created.

**Architecture:** `MainWindow` gates its `rootViewController` on account presence. A new non-mutating `AccountService.currentDefaultAccountKeychainId()` returns `nil` when no account exists (instead of bootstrapping). When `nil`, `MainWindow` roots an onboarding `UINavigationController` (Welcome → existing `SiteListViewController`); the existing `observeDefaultAccount()` stream cross-fades the root to the tab bar the moment the first account is created.

**Tech Stack:** UIKit, GRDB, Swift 6, pointfreeco/swift-snapshot-testing. Build via `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`. Snapshot tests via `xcodebuild ... -testPlan SpudSnapshots`. Spec: `docs/superpowers/specs/2026-06-15-onboarding-first-launch-design.md`.

---

## File structure

- `SpudDataKit/Services/Account/AccountService.swift` — replace bootstrapping accessor with non-mutating one; delete `bootstrapDefaultKeychainId()`.
- `SpudDataKitTests/AccountServiceDefaultAccountTests.swift` (new) — unit tests for the accessor.
- `Spud/Scenes/Onboarding/OnboardingWelcomeViewController.swift` (new) — Welcome screen.
- `SpudSnapshotTests/OnboardingSnapshotTests.swift` (new) — Welcome snapshot (light/dark).
- `Spud/Scenes/MainWindow/MainWindow.swift` — gate root on account presence; show onboarding; swap to tabs on first account.

---

## Task 1: Add a non-bootstrapping default-account accessor (additive)

This task is purely additive — it adds `currentDefaultAccountKeychainId()` next to
the existing `defaultAccountKeychainId()` and leaves the bootstrap in place, so
everything still compiles. The old method, the bootstrap, and the caller rewires
are removed in Task 3 (once the Welcome screen exists to be the new no-account
root).

**Files:**
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (protocol ~line 75; add impl near line 198)
- Test: `SpudDataKitTests/AccountServiceDefaultAccountTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/AccountServiceDefaultAccountTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest
@testable import SpudDataKit

@MainActor
final class AccountServiceDefaultAccountTests: XCTestCase {
    private func makeService() throws -> (AccountService, AppDatabase) {
        let db = try AppDatabase.inMemory()
        return (AccountService(appDatabase: db), db)
    }

    func test_emptyDatabase_returnsNil_doesNotCrash() throws {
        let (service, _) = try makeService()
        XCTAssertNil(service.currentDefaultAccountKeychainId())
    }

    func test_withAccount_returnsItsKeychainId() throws {
        let (service, db) = try makeService()
        let instance = try XCTUnwrap(InstanceActorId(from: "https://lemmy.world"))
        let keychainId = try db.ensureSignedOutAccountKeychainId(
            forInstance: instance,
            isServiceAccount: false
        )
        try db.setDefaultAccountSync(keychainId: keychainId)

        XCTAssertEqual(service.currentDefaultAccountKeychainId(), keychainId)
    }
}
```

(`InstanceActorId` lives in `SpudUtilKit`; `ensureSignedOutAccountKeychainId`/
`setDefaultAccountSync` are internal `AppDatabase` methods reachable via
`@testable import SpudDataKit`.)

- [ ] **Step 2: Run tests to verify they fail (compile error: no such method)**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/AccountServiceDefaultAccountTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
```
Expected: build failure — `value of type 'AccountService' has no member 'currentDefaultAccountKeychainId'`.

- [ ] **Step 3: Add the protocol declaration (alongside the existing one)**

In `SpudDataKit/Services/Account/AccountService.swift`, immediately after the
existing `defaultAccountKeychainId()` declaration (line 73-75), add:

```swift
    /// Returns the `accountKeychainId` of the current default / first non-service
    /// account, or `nil` when none exists. Read-only: never creates an account.
    /// `MainWindow` uses `nil` to decide to show onboarding instead of the tabs.
    func currentDefaultAccountKeychainId() -> String?
```

- [ ] **Step 4: Add the implementation (alongside the existing one)**

In the same file, immediately after the existing `public func defaultAccountKeychainId()`
implementation (ends line 214), add:

```swift
    public func currentDefaultAccountKeychainId() -> String? {
        assert(Thread.current.isMainThread)
        do {
            return try appDatabase.writer.read { db -> String? in
                try AccountRecord
                    .filter(Column("isServiceAccount") == false)
                    .order(sql: "isDefault DESC, id ASC")
                    .fetchOne(db)?
                    .accountKeychainId
            }
        } catch {
            logger.error("currentDefaultAccountKeychainId GRDB read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/AccountServiceDefaultAccountTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | grep -E "Test Case|Executed"
```
Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git add SpudDataKit/Services/Account/AccountService.swift SpudDataKitTests/AccountServiceDefaultAccountTests.swift
git commit -m "feat(account): add non-bootstrapping currentDefaultAccountKeychainId()

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: OnboardingWelcomeViewController

**Files:**
- Create: `Spud/Scenes/Onboarding/OnboardingWelcomeViewController.swift`
- Test: `SpudSnapshotTests/OnboardingSnapshotTests.swift` (new)

- [ ] **Step 1: Create the Welcome view controller**

Create `Spud/Scenes/Onboarding/OnboardingWelcomeViewController.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// First-launch Welcome screen. Brand mark, wordmark, tagline and a single
/// "Get started" CTA. Owns no dependencies; the host wires `onGetStarted` to
/// push the instance picker. Matches the onboarding design's Welcome screen
/// minus the (removed) "Browse without an account" secondary button.
final class OnboardingWelcomeViewController: UIViewController {
    /// Invoked when the user taps "Get started".
    var onGetStarted: (() -> Void)?

    private let accentGradient = CAGradientLayer()

    private lazy var logoImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "AppIconPreview-Default"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 28
        imageView.layer.cornerCurve = .continuous
        return imageView
    }()

    private lazy var wordmarkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Spud"
        label.font = .systemFont(ofSize: 40, weight: .heavy)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private lazy var taglineLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString(
            "Communities worth your time.",
            comment: "Onboarding welcome tagline"
        )
        label.font = .systemFont(ofSize: 19, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString(
            "Thousands of communities, real threaded discussion, and a feed you actually control — no ads, no algorithm.",
            comment: "Onboarding welcome body"
        )
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var getStartedButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = NSLocalizedString("Get started", comment: "Onboarding primary CTA")
        configuration.cornerStyle = .large
        configuration.contentInsets = .init(top: 15, leading: 16, bottom: 15, trailing: 16)
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        accentGradient.type = .radial
        view.layer.insertSublayer(accentGradient, at: 0)

        let textStack = UIStackView(arrangedSubviews: [wordmarkLabel, taglineLabel, bodyLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = 12
        textStack.setCustomSpacing(26, after: logoImageView)

        view.addSubview(logoImageView)
        view.addSubview(textStack)
        view.addSubview(getStartedButton)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: 96),
            logoImageView.heightAnchor.constraint(equalToConstant: 96),
            logoImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 96),

            textStack.topAnchor.constraint(equalTo: logoImageView.bottomAnchor, constant: 26),
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 34),
            textStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -34),

            getStartedButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            getStartedButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            getStartedButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        accentGradient.frame = view.bounds
        let accent = (view.tintColor ?? .systemBlue).withAlphaComponent(0.18)
        accentGradient.colors = [accent.cgColor, UIColor.clear.cgColor]
        // Radial gradient centred near the top, fading out by ~58%.
        accentGradient.startPoint = CGPoint(x: 0.5, y: 0.26)
        accentGradient.endPoint = CGPoint(x: 1.08, y: 0.84)
    }

    @objc
    private func getStartedTapped() {
        onGetStarted?()
    }
}
```

- [ ] **Step 2: Write the snapshot test (records references on first run = the RED state)**

Create `SpudSnapshotTests/OnboardingSnapshotTests.swift`:

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

/// Snapshots of the first-launch Welcome screen in light and dark, pinned to a
/// device config so the references are simulator-independent.
@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    func test_welcome() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let viewController = OnboardingWelcomeViewController()
            viewController.view.tintColor = lemmyTeal
            assertSnapshot(
                matching: viewController,
                as: .image(on: .iPhone13Pro, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
```

- [ ] **Step 3: Regenerate the project and run the snapshot test to record references**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/OnboardingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | grep -E "error:|Recorded|Executed"
```
Expected: FAIL with "No reference was found on disk. Automatically recorded snapshot" for `test_welcome.light` and `test_welcome.dark` — references now written under `SpudSnapshotTests/__Snapshots__/OnboardingSnapshotTests/`.

- [ ] **Step 4: Visually inspect the two recorded PNGs**

Open and eyeball the references for layout sanity (logo near top, wordmark/tagline/body centred, "Get started" pinned to bottom, accent tint visible):
```bash
open "SpudSnapshotTests/__Snapshots__/OnboardingSnapshotTests/test_welcome.light.png"
open "SpudSnapshotTests/__Snapshots__/OnboardingSnapshotTests/test_welcome.dark.png"
```
If the logo asset renders blank, confirm the asset name with `ls Spud/Resources/Assets.xcassets | grep AppIconPreview` and adjust `UIImage(named:)` in Step 1.

- [ ] **Step 5: Re-run to verify the test now passes against the recorded references**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/OnboardingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | grep -E "Test Case|Executed"
```
Expected: `test_welcome` passes.

- [ ] **Step 6: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git add Spud/Scenes/Onboarding/OnboardingWelcomeViewController.swift SpudSnapshotTests/OnboardingSnapshotTests.swift SpudSnapshotTests/__Snapshots__/OnboardingSnapshotTests/
git commit -m "feat(onboarding): Welcome screen with Get started CTA

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: MainWindow onboarding gate + remove the bootstrap

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (init lines 65-98; observation lines 112-127; caller line 422; new members + `showOnboarding()` + `swapRootToTabBar()`)
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (remove old method + bootstrap; fix caller line 571; remove protocol decl line 73-75)

- [ ] **Step 1: Add onboarding state and the gate in `init`**

In `MainWindow.swift`, add a stored property next to `currentDefaultAccountKeychainId` (line 61):

```swift
    /// The onboarding navigation controller while it is the window's root; nil
    /// once an account exists and the tab bar is installed.
    private var onboardingNavigationController: UINavigationController?
```

Then replace the bootstrap block in `init` (lines 75-86 — the comment, the `let keychainId = accountService.defaultAccountKeychainId()`, the `applyDefaultAccount(...)` call, and `rootViewController = tabBarController`) with:

```swift
        // Gate on account presence: an existing account builds the tab bar; a
        // fresh install (no account) gets the onboarding flow as the root, and
        // the default-account observation swaps in the tab bar once the flow
        // creates the first account.
        if let keychainId = accountService.currentDefaultAccountKeychainId() {
            applyDefaultAccount(
                keychainId: keychainId,
                isSignedIn: !accountService.isSignedOut(forAccountKeychainId: keychainId),
                defaultPostSortType: accountService.defaultSortType(forAccountKeychainId: keychainId)
            )
            rootViewController = tabBarController
        } else {
            showOnboarding()
        }
```

- [ ] **Step 2: Add `showOnboarding()` and `swapRootToTabBar()`**

Add these methods to `MainWindow` (e.g. just after `init`/`deinit`, before `startObservingDefaultAccount`):

```swift
    private func showOnboarding() {
        let welcomeViewController = OnboardingWelcomeViewController()
        welcomeViewController.onGetStarted = { [weak self] in
            guard let self else { return }
            let siteListViewController = SiteListViewController(dependencies: dependencies.nested)
            onboardingNavigationController?.pushViewController(siteListViewController, animated: true)
        }
        let navigationController = UINavigationController(rootViewController: welcomeViewController)
        onboardingNavigationController = navigationController
        rootViewController = navigationController
    }

    /// Cross-fade the window's root from onboarding to the (already-populated)
    /// tab bar once the first account exists.
    private func swapRootToTabBar() {
        UIView.transition(
            with: self,
            duration: 0.3,
            options: .transitionCrossDissolve,
            animations: { [self] in rootViewController = tabBarController },
            completion: { [weak self] _ in self?.onboardingNavigationController = nil }
        )
    }
```

- [ ] **Step 3: Trigger the swap when the first account appears**

In `startObservingDefaultAccount()` (lines 112-127), the loop currently calls `applyDefaultAccount(...)` on each new record. Add the root swap immediately after that call. Replace the loop body:

```swift
                guard record.accountKeychainId != currentDefaultAccountKeychainId else { continue }
                applyDefaultAccount(
                    keychainId: record.accountKeychainId,
                    isSignedIn: !record.isSignedOutAccountType,
                    defaultPostSortType: record.resolvedDefaultSortType
                )
```

with:

```swift
                guard record.accountKeychainId != currentDefaultAccountKeychainId else { continue }
                applyDefaultAccount(
                    keychainId: record.accountKeychainId,
                    isSignedIn: !record.isSignedOutAccountType,
                    defaultPostSortType: record.resolvedDefaultSortType
                )
                if onboardingNavigationController != nil {
                    swapRootToTabBar()
                }
```

- [ ] **Step 4: Repoint the `restoreEmptySecondaryColumn` caller (line 421-426)**

In `MainWindow.swift`, `restoreEmptySecondaryColumn(in:)` ends with:

```swift
        let emptyDetailViewController = PostDetailOrEmptyViewController(
            accountKeychainId: currentDefaultAccountKeychainId ?? accountService.defaultAccountKeychainId(),
            dependencies: dependencies.nested
        )
        let detailNav = UINavigationController(rootViewController: emptyDetailViewController)
        svc.setViewController(detailNav, for: .secondary)
```

Replace that tail with (this method runs only with tabs present, so the account exists; bail defensively if not):

```swift
        guard let keychainId = currentDefaultAccountKeychainId ?? accountService.currentDefaultAccountKeychainId() else {
            return
        }
        let emptyDetailViewController = PostDetailOrEmptyViewController(
            accountKeychainId: keychainId,
            dependencies: dependencies.nested
        )
        let detailNav = UINavigationController(rootViewController: emptyDetailViewController)
        svc.setViewController(detailNav, for: .secondary)
```

- [ ] **Step 5: Remove the old accessor + bootstrap, fix the `removeAccount` caller**

In `SpudDataKit/Services/Account/AccountService.swift`:

1. Delete the protocol declaration (lines 73-75):
```swift
    /// Returns the `accountKeychainId` of the account that is shown on app
    /// launch. Bootstraps a signed-out default on first launch.
    func defaultAccountKeychainId() -> String
```

2. Delete the implementation `public func defaultAccountKeychainId() -> String { ... }` (lines 198-214) AND the `private func bootstrapDefaultKeychainId() -> String { ... }` that follows it (lines ~216-234, including its `fatalError("Cannot bootstrap default account: no sites available")`). Keep the `currentDefaultAccountKeychainId()` added in Task 1.

3. In `removeAccount(forAccountKeychainId:)` (line 571), change:
```swift
        let wasDefault = defaultAccountKeychainId() == keychainId
```
to:
```swift
        let wasDefault = currentDefaultAccountKeychainId() == keychainId
```

- [ ] **Step 6: Confirm no residual callers or other conformers**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
grep -rn "defaultAccountKeychainId()" Spud SpudDataKit OpenInAppExtension --include="*.swift" | grep -vE "currentDefaultAccountKeychainId|defaultSortType"
grep -rln ": AccountServiceType" Spud SpudDataKit SpudSnapshotTests SpudDataKitTests --include="*.swift"
```
Expected: no remaining bare `defaultAccountKeychainId()` references; `AccountService` is the only `AccountServiceType` conformer. If a fake conformer turns up, add `func currentDefaultAccountKeychainId() -> String? { nil }` and remove its `defaultAccountKeychainId()`.

- [ ] **Step 7: Build**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud 2>&1 | tail -3
```
Expected: `Build: SUCCESS`.

- [ ] **Step 8: Commit**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
git add Spud/Scenes/MainWindow/MainWindow.swift SpudDataKit/Services/Account/AccountService.swift
git commit -m "feat(onboarding): gate MainWindow root on account presence; drop fatal bootstrap

Show the Welcome onboarding flow as the window root when no account
exists, and cross-fade to the tab bar once the instance-picker flow
creates the first account. Removes bootstrapDefaultKeychainId() and its
fresh-install fatalError.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Fresh-install verification

**Files:** none (manual verification on the simulator)

- [ ] **Step 1: Erase any existing install so the database is empty**

Run (uninstall to guarantee a cold first launch):
```bash
xcrun simctl uninstall booted info.ddenis.Spud
```

- [ ] **Step 2: Install and launch the freshly built app**

Run:
```bash
APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'Spud.app' -path '*Debug-iphonesimulator*' -type d | head -1)"
xcrun simctl install booted "$APP"
xcrun simctl launch booted info.ddenis.Spud
( sleep 3; xcrun simctl io booted screenshot /tmp/onboarding-welcome.png >/dev/null 2>&1; echo shot )
```

- [ ] **Step 3: Verify the Welcome screen appears (no crash)**

Open `/tmp/onboarding-welcome.png`. Expected: the Welcome screen (logo, "Spud", tagline, "Get started") — NOT a crash and NOT the old auto-bootstrapped feed.

- [ ] **Step 4: Verify Get started → instance picker → account → tabs**

Tap "Get started" in the simulator, pick an instance, then either log in / register / use "Browse without an account". Confirm the app cross-fades into the tab bar (Posts/Communities/Search/Inbox/Account). Screenshot for the record:
```bash
( sleep 1; xcrun simctl io booted screenshot /tmp/onboarding-tabs.png >/dev/null 2>&1; echo shot )
```

- [ ] **Step 5: Verify relaunch skips onboarding**

Run:
```bash
xcrun simctl terminate booted info.ddenis.Spud
xcrun simctl launch booted info.ddenis.Spud
( sleep 3; xcrun simctl io booted screenshot /tmp/onboarding-relaunch.png >/dev/null 2>&1; echo shot )
```
Expected: `/tmp/onboarding-relaunch.png` shows the tab bar directly (the created account persists, so onboarding does not re-show).

- [ ] **Step 6: Full unit + snapshot test pass**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud 2>&1 | tail -3
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/OnboardingSnapshotTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | grep -E "Test Case|Executed"
```
Expected: build success; onboarding snapshots pass.

---

## Notes

- `SiteService`'s async `discuss.tchncs.de` seed and `ensureSite` remain in place; they are no longer load-bearing for the bootstrap but are harmless. Removing them is out of scope for this slice.
- The reused `Login`/`Register` screens call `dismiss(animated:)` on success; in the onboarding nav stack this is tolerated because `MainWindow` replaces the entire root on account creation. If a stray dismiss animation is visible before the cross-fade, make `swapRootToTabBar()` run on the next runloop tick (`DispatchQueue.main.async`) — only if observed during Task 4.
