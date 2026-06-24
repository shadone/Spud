# Configurable Link Instance (Open in Browser + Share) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose, per action, whether "Open in Browser" and "Share" produce a link on their home instance or on the post/comment's original (canonical `ap_id`) instance — defaulting to today's behavior.

**Architecture:** A single `Preferences.LinkInstance` enum models the choice. A single pure helper `LinkURL` (generalized from the existing `ShareURL`) takes that choice plus `(originalUrl, serverId, instanceActorId)` and returns the right `URL?`. Two independent `@UserDefaultsBacked` preferences (`openInBrowserInstance` = `.myInstance`, `shareLinkInstance` = `.originalInstance`) feed the two action types. Canonical routing URLs (Handoff / Spotlight) are pinned to `.originalInstance` explicitly and never read a preference.

**Tech Stack:** Swift 6 (strict concurrency, language mode 6.0), UIKit, SwiftUI (settings), GRDB (read of instance actor id), XCTest, XcodeGen.

## Global Constraints

- Spud app target is at Swift 6.0 language mode with `SWIFT_STRICT_CONCURRENCY = complete`. New types must be Sendable-clean (the enum is `Codable`/value-type Sendable; `LinkURL` is an enum of `static` funcs — no stored state).
- New source and test files require `make project` (XcodeGen) before they compile — run it before the first build in any task that adds a file.
- Run SwiftFormat on touched files before staging: `mint run swiftformat <paths>` (the pre-commit hook lints, it does not format).
- No emojis in code, comments, or commit messages. Conventional commit subjects (`feat:`, `refactor:`, `test:`).
- `Components.Schemas.PostID` bridges to `Int64` via `Int64(_:)` (see existing `sharePost()`).
- User-facing copy: option titles are exactly **"My Instance"** and **"Original Instance"**; the settings section header is exactly **"Post & Comment Links"**.
- Test simulator: `iPhone 17` (unit tests). Build verification may use the `build_and_test.py` wrapper with `--simulator "iPhone 17 Pro"`.
- Default values must preserve current behavior: Open in Browser = `.myInstance`, Share = `.originalInstance`.

---

## File Structure

New:
- `Spud/Services/Preferences/LinkInstance.swift` — the `Preferences.LinkInstance` enum (choice + `title`).
- `Spud/Utils/Sharing/LinkURL.swift` — pure URL builder for posts/comments, parameterized by `LinkInstance`.
- `SpudTests/LinkURLTests.swift` — matrix tests for `LinkURL`.
- `SpudTests/LinkInstancePreferenceTests.swift` — asserts the two `PreferencesService` defaults.

Modified:
- `Spud/Services/Preferences/PreferencesService.swift` — two preferences (protocol + impl + streams).
- `Spud/Utils/Sharing/ShareService.swift` — remove `ShareURL` (moved/renamed to `LinkURL`); keep `presentShareSheet`.
- `Spud/Services/App/AppService.swift` — `openInBrowser` gains `originalPostUrl:` and uses `LinkURL` + the preference.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — 4 call sites migrated.
- `Spud/Scenes/PostList/PostListViewController.swift` — 1 share call site migrated.
- `Spud/Integration/ContentSpotlightIndexer.swift` — 1 canonical call site migrated (pinned `.originalInstance`).
- `Spud/Scenes/Preferences/PreferencesViewModel.swift` — mirrored properties + update methods + observation.
- `Spud/Scenes/Preferences/PreferencesGeneralView.swift` — new settings section.

---

## Task 1: `Preferences.LinkInstance` enum + `PreferencesService` preferences

**Files:**
- Create: `Spud/Services/Preferences/LinkInstance.swift`
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (protocol near line 31; impl near line 154)
- Test: `SpudTests/LinkInstancePreferenceTests.swift`

**Interfaces:**
- Produces:
  - `Preferences.LinkInstance` — `enum: String, RawRepresentable, Codable, CaseIterable, Identifiable`, cases `.myInstance` / `.originalInstance`, `var id: String`, `var title: String`.
  - `PreferencesServiceType.openInBrowserInstance: Preferences.LinkInstance { get set }` + `openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> { get }`.
  - `PreferencesServiceType.shareLinkInstance: Preferences.LinkInstance { get set }` + `shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> { get }`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/LinkInstancePreferenceTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class LinkInstancePreferenceTests: XCTestCase {
    func test_defaults_preserveCurrentBehavior() {
        // Clear any persisted values so we observe the declared defaults.
        UserDefaults.standard.removeObject(forKey: "openInBrowserInstance")
        UserDefaults.standard.removeObject(forKey: "shareLinkInstance")

        let service = PreferencesService()

        XCTAssertEqual(service.openInBrowserInstance, .myInstance)
        XCTAssertEqual(service.shareLinkInstance, .originalInstance)
    }

    func test_title_isStable() {
        XCTAssertEqual(Preferences.LinkInstance.myInstance.title, "My Instance")
        XCTAssertEqual(Preferences.LinkInstance.originalInstance.title, "Original Instance")
    }
}
```

- [ ] **Step 2: Regenerate the project and run the test to verify it fails**

Run:
```sh
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LinkInstancePreferenceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL — compile error "cannot find 'Preferences' member 'LinkInstance'" / "value of type 'PreferencesService' has no member 'openInBrowserInstance'".

- [ ] **Step 3: Create the enum**

Create `Spud/Services/Preferences/LinkInstance.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension Preferences {
    /// Which instance a post/comment link should point at.
    enum LinkInstance: String, RawRepresentable, Codable, CaseIterable, Identifiable {
        /// The account's home instance: `<home>/post|comment/<serverId>`.
        case myInstance

        /// The canonical federation permalink (`ap_id`), falling back to the
        /// home instance when absent.
        case originalInstance

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .myInstance:
                return "My Instance"
            case .originalInstance:
                return "Original Instance"
            }
        }
    }
}
```

- [ ] **Step 4: Add the two preferences to `PreferencesService`**

In `Spud/Services/Preferences/PreferencesService.swift`, in the `PreferencesServiceType` protocol, immediately after the `openExternalLinksStream` declaration (line 31):

```swift
    var openInBrowserInstance: Preferences.LinkInstance { get set }
    var openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> { get }

    var shareLinkInstance: Preferences.LinkInstance { get set }
    var shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> { get }
```

In the `PreferencesService` class, immediately after the `openExternalLinksStream` computed property (line 155):

```swift
    @UserDefaultsBacked(key: "openInBrowserInstance")
    var openInBrowserInstance: Preferences.LinkInstance = .myInstance

    var openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> {
        $openInBrowserInstance
    }

    @UserDefaultsBacked(key: "shareLinkInstance")
    var shareLinkInstance: Preferences.LinkInstance = .originalInstance

    var shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> {
        $shareLinkInstance
    }
```

- [ ] **Step 5: Regenerate and run the test to verify it passes**

Run:
```sh
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LinkInstancePreferenceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: PASS (2 tests).

- [ ] **Step 6: Format and commit**

```sh
mint run swiftformat Spud/Services/Preferences/LinkInstance.swift \
  Spud/Services/Preferences/PreferencesService.swift \
  SpudTests/LinkInstancePreferenceTests.swift
git add Spud/Services/Preferences/LinkInstance.swift \
  Spud/Services/Preferences/PreferencesService.swift \
  SpudTests/LinkInstancePreferenceTests.swift
git commit -m "feat: add LinkInstance preference (open-in-browser + share instance)"
```

---

## Task 2: `LinkURL` helper + retire `ShareURL` + migrate all call sites

**Files:**
- Create: `Spud/Utils/Sharing/LinkURL.swift`
- Modify: `Spud/Utils/Sharing/ShareService.swift` (remove the `ShareURL` enum; keep the `UIViewController.presentShareSheet` extension)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift:383, 868, 887`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift:1353`
- Modify: `Spud/Integration/ContentSpotlightIndexer.swift:43`
- Test: `SpudTests/LinkURLTests.swift`

**Interfaces:**
- Consumes: `Preferences.LinkInstance` (Task 1); `PreferencesServiceType.shareLinkInstance` (Task 1).
- Produces:
  - `LinkURL.forPost(instance: Preferences.LinkInstance, originalPostUrl: String?, serverPostId: Int64, instanceActorId: String?) -> URL?`
  - `LinkURL.forComment(instance: Preferences.LinkInstance, originalCommentUrl: String?, serverCommentId: Int64, instanceActorId: String?) -> URL?`

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/LinkURLTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import Spud

final class LinkURLTests: XCTestCase {
    private let home = "https://discuss.tchncs.de"
    private let apId = "https://lemmy.world/post/123"
    private let commentApId = "https://lemmy.world/comment/99"

    // MARK: forPost

    func test_post_originalInstance_usesApId() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://lemmy.world/post/123")
    }

    func test_post_myInstance_ignoresApIdAndUsesHome() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_originalInstance_missingApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_originalInstance_emptyApId_fallsBackToHome() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: "",
            serverPostId: 5,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/post/5")
    }

    func test_post_myInstance_noInstanceActorId_returnsNil() {
        let url = LinkURL.forPost(
            instance: .myInstance,
            originalPostUrl: apId,
            serverPostId: 5,
            instanceActorId: nil
        )
        XCTAssertNil(url)
    }

    func test_post_originalInstance_noApIdNoInstance_returnsNil() {
        let url = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: nil,
            serverPostId: 5,
            instanceActorId: nil
        )
        XCTAssertNil(url)
    }

    // MARK: forComment

    func test_comment_originalInstance_usesApId() {
        let url = LinkURL.forComment(
            instance: .originalInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://lemmy.world/comment/99")
    }

    func test_comment_myInstance_usesHome() {
        let url = LinkURL.forComment(
            instance: .myInstance,
            originalCommentUrl: commentApId,
            serverCommentId: 7,
            instanceActorId: home
        )
        XCTAssertEqual(url?.absoluteString, "https://discuss.tchncs.de/comment/7")
    }
}
```

- [ ] **Step 2: Regenerate and run the tests to verify they fail**

Run:
```sh
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LinkURLTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL — compile error "cannot find 'LinkURL' in scope".

- [ ] **Step 3: Create `LinkURL`**

Create `Spud/Utils/Sharing/LinkURL.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Builds the canonical browser/share URL for a post or comment.
///
/// `.originalInstance` prefers the federation permalink (`ap_id`) carried on the
/// row and falls back to `<home>/post|comment/<id>`. `.myInstance` always uses
/// the account's home instance, ignoring the `ap_id`.
enum LinkURL {
    static func forPost(
        instance: Preferences.LinkInstance,
        originalPostUrl: String?,
        serverPostId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(
            instance: instance,
            preferred: originalPostUrl,
            instanceActorId: instanceActorId,
            path: "post/\(serverPostId)"
        )
    }

    static func forComment(
        instance: Preferences.LinkInstance,
        originalCommentUrl: String?,
        serverCommentId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(
            instance: instance,
            preferred: originalCommentUrl,
            instanceActorId: instanceActorId,
            path: "comment/\(serverCommentId)"
        )
    }

    private static func url(
        instance: Preferences.LinkInstance,
        preferred: String?,
        instanceActorId: String?,
        path: String
    ) -> URL? {
        // Original Instance with a usable ap_id wins; everything else
        // (My Instance, or Original Instance with no/invalid ap_id) uses home.
        if
            instance == .originalInstance,
            let preferred,
            !preferred.isEmpty,
            let url = URL(string: preferred)
        {
            return url
        }
        guard
            let instanceActorId,
            let instanceUrl = URL(string: instanceActorId)
        else { return nil }
        return instanceUrl.appending(path: path)
    }
}
```

- [ ] **Step 4: Remove `ShareURL` from `ShareService.swift`**

In `Spud/Utils/Sharing/ShareService.swift`, delete the entire `enum ShareURL { ... }` block (lines 17-65), keeping the file header `import`s and the `extension UIViewController { func presentShareSheet... }` (lines 67-93). Update the file's top doc comment to drop the URL-building description (it now only hosts `presentShareSheet`):

```swift
/// Helper for presenting the system share sheet for posts and comments.
/// URL construction lives in `LinkURL`.
```

- [ ] **Step 5: Migrate the user-Share call sites to the preference**

In `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `sharePost()` (line 868):

```swift
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: headerRow?.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else {
```

`shareComment(serverCommentId:)` (line 887):

```swift
        guard let url = LinkURL.forComment(
            instance: preferencesService.shareLinkInstance,
            originalCommentUrl: row?.originalCommentUrl,
            serverCommentId: serverCommentId,
            instanceActorId: instanceActorId
        ) else {
```

In `Spud/Scenes/PostList/PostListViewController.swift`, `sharePost(serverPostId:)` (line 1353):

```swift
        guard let url = LinkURL.forPost(
            instance: preferencesService.shareLinkInstance,
            originalPostUrl: rowsByServerPostId[serverPostId]?.originalPostUrl,
            serverPostId: serverPostId,
            instanceActorId: instanceActorId
        ) else {
```

- [ ] **Step 6: Migrate the canonical-routing call sites (pinned `.originalInstance`)**

These build account/device-independent routing URLs and must NOT read a user preference.

In `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `updateUserActivity()` (line 383):

```swift
        guard let canonical = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: headerRow?.originalPostUrl,
            serverPostId: Int64(viewModel.serverPostId),
            instanceActorId: instanceActorId
        ) else { return }
```

In `Spud/Integration/ContentSpotlightIndexer.swift`, `makeItem(from:)` (line 43):

```swift
        guard let canonical = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: row.originalPostUrl,
            serverPostId: row.serverPostId,
            instanceActorId: nil
        ) else { return nil }
```

- [ ] **Step 7: Regenerate, run the new tests, and build the app**

Run:
```sh
make project
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/LinkURLTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: 8 `LinkURLTests` PASS; app build succeeds with no new errors (the `ShareURL` symbol is fully removed — a leftover reference would fail here).

- [ ] **Step 8: Format and commit**

```sh
mint run swiftformat Spud/Utils/Sharing/LinkURL.swift \
  Spud/Utils/Sharing/ShareService.swift \
  Spud/Scenes/PostDetail/Content/PostDetailViewController.swift \
  Spud/Scenes/PostList/PostListViewController.swift \
  Spud/Integration/ContentSpotlightIndexer.swift \
  SpudTests/LinkURLTests.swift
git add Spud/Utils/Sharing/LinkURL.swift \
  Spud/Utils/Sharing/ShareService.swift \
  Spud/Scenes/PostDetail/Content/PostDetailViewController.swift \
  Spud/Scenes/PostList/PostListViewController.swift \
  Spud/Integration/ContentSpotlightIndexer.swift \
  SpudTests/LinkURLTests.swift
git commit -m "refactor: generalize ShareURL into LinkURL parameterized by LinkInstance"
```

---

## Task 3: `AppService.openInBrowser` reads the preference

**Files:**
- Modify: `Spud/Services/App/AppService.swift` (protocol lines 16-21; impl lines 47-58)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (`openInBrowser()` lines 852-860)

**Interfaces:**
- Consumes: `LinkURL.forPost` (Task 2); `PreferencesServiceType.openInBrowserInstance` (Task 1).
- Produces: `AppServiceType.openInBrowser(serverPostId:originalPostUrl:accountKeychainId:on:)`.

- [ ] **Step 1: Update the protocol signature**

In `Spud/Services/App/AppService.swift`, the `AppServiceType` protocol method (lines 17-21):

```swift
    /// Opens the post itself in a browser.
    func openInBrowser(
        serverPostId: Components.Schemas.PostID,
        originalPostUrl: String?,
        accountKeychainId: String,
        on viewController: UIViewController
    ) async
```

- [ ] **Step 2: Update the implementation to use `LinkURL` + the preference**

Replace the `openInBrowser` implementation (lines 47-58) with:

```swift
    func openInBrowser(
        serverPostId: Components.Schemas.PostID,
        originalPostUrl: String?,
        accountKeychainId: String,
        on viewController: UIViewController
    ) {
        guard let postUrl = LinkURL.forPost(
            instance: preferencesService.openInBrowserInstance,
            originalPostUrl: originalPostUrl,
            serverPostId: Int64(serverPostId),
            instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
        ) else { return }
        presentSafariViewController(url: postUrl, on: viewController)
    }
```

- [ ] **Step 3: Update the call site to pass `originalPostUrl`**

In `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`, `openInBrowser()` (lines 852-860):

```swift
    private func openInBrowser() {
        Task {
            await appService.openInBrowser(
                serverPostId: viewModel.serverPostId,
                originalPostUrl: headerRow?.originalPostUrl,
                accountKeychainId: viewModel.accountKeychainId,
                on: self
            )
        }
    }
```

- [ ] **Step 4: Build to verify**

Run:
```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds, no new warnings. (No new unit test: the URL logic is covered by `LinkURLTests`; this task is pure wiring through a `@MainActor`/UIKit boundary.)

- [ ] **Step 5: Format and commit**

```sh
mint run swiftformat Spud/Services/App/AppService.swift \
  Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git add Spud/Services/App/AppService.swift \
  Spud/Scenes/PostDetail/Content/PostDetailViewController.swift
git commit -m "feat: open-in-browser honors the openInBrowserInstance preference"
```

---

## Task 4: Settings UI (PreferencesViewModel + PreferencesGeneralView)

**Files:**
- Modify: `Spud/Scenes/Preferences/PreferencesViewModel.swift` (properties ~84; real-init ~167; observation ~215; preview-init ~328; update methods ~373)
- Modify: `Spud/Scenes/Preferences/PreferencesGeneralView.swift` (bindings ~30; new section in `body` after the existing "Links" section, before `.navigationTitle`)

**Interfaces:**
- Consumes: `PreferencesServiceType.openInBrowserInstance` / `shareLinkInstance` + their `*Stream`s (Task 1).
- Produces (on `PreferencesViewModel`): `var openInBrowserInstance`, `var shareLinkInstance`, `func updateOpenInBrowserInstance(_:)`, `func updateShareLinkInstance(_:)`.

- [ ] **Step 1: Add mirrored stored properties**

In `Spud/Scenes/Preferences/PreferencesViewModel.swift`, after `var openExternalLinkAsUniversalLinkInApp: Bool` (line 86):

```swift
    var openInBrowserInstance: Preferences.LinkInstance
    var shareLinkInstance: Preferences.LinkInstance
```

- [ ] **Step 2: Seed them in the real initializer**

After the `openExternalLinkAsUniversalLinkInApp = ...` assignment (line 171), add:

```swift
        openInBrowserInstance = dependencies.preferencesService.openInBrowserInstance
        shareLinkInstance = dependencies.preferencesService.shareLinkInstance
```

- [ ] **Step 3: Seed them in the preview initializer**

In `init(preview:)`, after `openExternalLinkAsUniversalLinkInApp = true` (line 328), add:

```swift
        openInBrowserInstance = .myInstance
        shareLinkInstance = .originalInstance
```

- [ ] **Step 4: Observe the streams**

After the `openExternalLinksStream` observation task (ends line 215), add:

```swift
        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openInBrowserInstanceStream {
                self?.openInBrowserInstance = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.shareLinkInstanceStream {
                self?.shareLinkInstance = value
            }
        })
```

- [ ] **Step 5: Add the update methods**

After `updateOpenExternalLink(_:)` (ends line 376), add:

```swift
    func updateOpenInBrowserInstance(_ value: Preferences.LinkInstance) {
        openInBrowserInstance = value
        preferencesService?.openInBrowserInstance = value
    }

    func updateShareLinkInstance(_ value: Preferences.LinkInstance) {
        shareLinkInstance = value
        preferencesService?.shareLinkInstance = value
    }
```

- [ ] **Step 6: Add bindings + section to `PreferencesGeneralView`**

In `Spud/Scenes/Preferences/PreferencesGeneralView.swift`, after the `openExternalLinks` computed binding (lines 30-36), add:

```swift
    private var openInBrowserInstance: Binding<Preferences.LinkInstance> {
        .init {
            viewModel.openInBrowserInstance
        } set: { newValue in
            viewModel.updateOpenInBrowserInstance(newValue)
        }
    }

    private var shareLinkInstance: Binding<Preferences.LinkInstance> {
        .init {
            viewModel.shareLinkInstance
        } set: { newValue in
            viewModel.updateShareLinkInstance(newValue)
        }
    }
```

In `body`, immediately after the existing "Links" `Section { ... } header: { Text("Links") } footer: { ... }` block closes (after line 147) and before `.navigationTitle("General")` (line 149), add:

```swift
            Section {
                Picker("Open in Browser", selection: openInBrowserInstance) {
                    ForEach(Preferences.LinkInstance.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Share", selection: shareLinkInstance) {
                    ForEach(Preferences.LinkInstance.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
            } header: {
                Text("Post & Comment Links")
            } footer: {
                Text("\"My Instance\" keeps links on your home instance (so you stay signed in). \"Original Instance\" uses the post's source instance.")
            }
```

- [ ] **Step 7: Build to verify**

Run:
```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: build succeeds, no new warnings.

- [ ] **Step 8: Run the full SpudTests suite to confirm nothing regressed**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all SpudTests PASS (includes `LinkURLTests`, `LinkInstancePreferenceTests`).

- [ ] **Step 9: Format and commit**

```sh
mint run swiftformat Spud/Scenes/Preferences/PreferencesViewModel.swift \
  Spud/Scenes/Preferences/PreferencesGeneralView.swift
git add Spud/Scenes/Preferences/PreferencesViewModel.swift \
  Spud/Scenes/Preferences/PreferencesGeneralView.swift
git commit -m "feat: add Post & Comment Links settings (instance for open-in-browser + share)"
```

---

## Manual verification (after all tasks)

On a booted simulator with the app running:
1. Open a post that originated on a *different* instance than your account.
2. Overflow menu -> Open in Browser -> confirm it opens `https://<your-instance>/post/<id>` (default).
3. Settings -> General -> Post & Comment Links -> set "Open in Browser" to "Original Instance".
4. Repeat step 2 -> confirm it now opens the post's `lemmy.world` (source) URL.
5. Share the post (default "Original Instance") -> confirm the shared URL is the source `ap_id`. Switch "Share" to "My Instance" -> confirm the shared URL is on your home instance.
6. Confirm Handoff/Spotlight still resolve (these stay canonical regardless of the settings).
```
