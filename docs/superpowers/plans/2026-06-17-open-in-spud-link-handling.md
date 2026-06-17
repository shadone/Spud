# Open in Spud — link handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open any Lemmy post / comment / community / user link in Spud — from Safari (an injected banner across a bundled instance allowlist) and from any app's share sheet (a new Action extension) — by funnelling everything through one custom-scheme deep link the app resolves.

**Architecture:** Both entry points are thin: they emit a single uniform deep link `info.ddenis.spud://internal/resolve?url=<encoded page URL>` for any recognized Lemmy page. All routing intelligence lives in the app's `.objectAtURL` resolver (`AppCoordinator.open`), which resolves the URL via Lemmy `resolve_object` and dispatches by object type to `MainWindow.display(...)`. This also closes the existing gap where `.community` / `.person` internal links (from body-text taps) went nowhere.

**Tech Stack:** Swift 6 / UIKit / GRDB (app + SpudDataKit), Swift App-extension target (Action extension), JavaScript/CSS (Safari web extension), XcodeGen (`project.yml`), `build_and_test.py` wrapper for iOS builds/tests.

## Global Constraints

- iOS deployment target **18.0**; Swift language mode **6.0**, `SWIFT_STRICT_CONCURRENCY = complete` (copy from `project.yml`).
- Build/test via `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme <Scheme> --simulator "iPhone 17 Pro"`. Fresh derived data needs `-skipPackagePluginValidation -skipMacroValidation` (already handled by the wrapper).
- The project (`Spud.xcodeproj`) is **generated**; after editing `project.yml` run `make project` (the worktree is a fresh checkout — run `make project` before the first build).
- No emojis in code/comments/commits. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`/`chore:`). Small focused commits. Stage explicit paths (never `git add -A`; `.remember/remember.md` is not ours and git-annex snapshot refs show as cosmetically modified).
- SwiftFormat is authoritative; run `mint run swiftformat <changed paths>` before staging Swift files.
- Deep-link wire format is fixed by `SpudUtilKit/Extensions/URL+spud.swift`: `info.ddenis.spud://internal/resolve?url=<percent-encoded canonical URL>` parses to `.objectAtURL(url:)`.

---

## Slice A — App-side routing backbone (no extensions; unit-testable)

Closes the routing gap and makes every downstream entry point land correctly. Shippable on its own (also fixes body-text community/person taps).

### Task A1: Enrich `ResolvedLemmyObject.comment` with data

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/ResolvedLemmyObject.swift`
- Test: `SpudDataKitTests/ResolvedLemmyObjectTests.swift` (create if absent)

**Interfaces:**
- Produces: `case comment(postId: Components.Schemas.PostID, commentId: Components.Schemas.CommentID, instance: InstanceActorId)` — replaces the dataless `case comment`. (Verify `Components.Schemas.CommentID` exists in the pinned LemmyKit; if not, use `Int32`.)

- [ ] **Step 1: Verify the schema field names.** Inspect the generated types: search the resolved LemmyKit checkout / build for `ResolveObjectResponse` and `CommentView` to confirm `response.comment?.comment.post_id` and `response.comment?.comment.id`, and whether `Components.Schemas.CommentID` is a typealias. Run:
  `grep -rn "var comment_view\|struct CommentView\|typealias CommentID\|var post_id" $(find ~/Library/Developer/Xcode/DerivedData -type d -name "LemmyKit" 2>/dev/null | head -1) 2>/dev/null | head` and check `ResolvedLemmyObject.swift` neighbors. Adjust the field path below to match.

- [ ] **Step 2: Write the failing test**

```swift
import LemmyKit
import XCTest
@testable import SpudDataKit

final class ResolvedLemmyObjectTests: XCTestCase {
    func test_init_mapsCommentResponse_toCommentCaseWithPostAndCommentIds() throws {
        // Build a ResolveObjectResponse carrying only a comment view.
        // Reuse the SpudDataKitTests fake builders if present; otherwise decode
        // a minimal JSON fixture for ResolveObjectResponse with a comment.
        let response = try ResolveObjectResponseFixture.comment(postId: 42, commentId: 7)
        let home = InstanceActorId(from: "https://lemmy.world")!

        let resolved = ResolvedLemmyObject(response: response, homeInstance: home)

        guard case let .comment(postId, commentId, instance) = resolved else {
            return XCTFail("expected .comment, got \(resolved)")
        }
        XCTAssertEqual(postId, 42)
        XCTAssertEqual(commentId, 7)
        XCTAssertEqual(instance, home)
    }
}
```

  If no fake builder exists, add `ResolveObjectResponseFixture` in the test target that constructs the `Components.Schemas.ResolveObjectResponse` via JSON decode (the generated types are `Codable`) — mirror how existing `SpudDataKitTests` fakes build `Components.Schemas.*`.

- [ ] **Step 3: Run test, verify it fails** (`.comment` has no associated values yet → compile error / mismatch).

Run: `python3 .../build_and_test.py --scheme SpudDataKit --simulator "iPhone 17 Pro"`

- [ ] **Step 4: Implement.** In `ResolvedLemmyObject.swift` replace the case and the initializer branch:

```swift
/// Resolved to a comment, by local post + comment id under the resolving account.
case comment(postId: Components.Schemas.PostID, commentId: Components.Schemas.CommentID, instance: InstanceActorId)
```

```swift
} else if let comment = response.comment {
    self = .comment(
        postId: comment.comment.post_id,
        commentId: comment.comment.id,
        instance: homeInstance
    )
} else {
    self = .unresolved
}
```

- [ ] **Step 5: Run tests, verify pass.**
- [ ] **Step 6: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy/ResolvedLemmyObject.swift SpudDataKitTests/ResolvedLemmyObjectTests.swift
git add SpudDataKit/Services/Lemmy/ResolvedLemmyObject.swift SpudDataKitTests/ResolvedLemmyObjectTests.swift
git commit -m "feat: carry post+comment ids on ResolvedLemmyObject.comment"
```

### Task A2: Classify `/comment/N` URLs in `LemmyURLParser`

**Files:**
- Modify: `Spud/Utils/LemmyURLParser.swift:56-57`
- Test: `SpudTests/LemmyURLParserTests.swift`

**Interfaces:**
- Produces: `classify(url:isKnownInstance:)` now returns `.objectAtURL(url:)` for `("comment", 2)` on a known instance (was `nil`).

- [ ] **Step 1: Write the failing test** (add to `LemmyURLParserTests`):

```swift
func test_classify_commentUrlOnKnownInstance_returnsObjectAtURL() throws {
    let url = URL(string: "https://lemmy.world/comment/12345")!
    let result = LemmyURLParser.classify(url: url) { $0 == "lemmy.world" }
    guard case let .objectAtURL(resolved) = result else {
        return XCTFail("expected .objectAtURL, got \(String(describing: result))")
    }
    XCTAssertEqual(resolved, url)
}

func test_classify_commentUrlOnUnknownInstance_returnsNil() {
    let url = URL(string: "https://example.com/comment/12345")!
    XCTAssertNil(LemmyURLParser.classify(url: url) { _ in false })
}
```

- [ ] **Step 2: Run, verify the first test fails** (`("comment", _)` currently returns nil).

Run: `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"` (Spud test plan includes SpudTests)

- [ ] **Step 3: Implement.** Replace the deferred case:

```swift
case ("comment", 2):
    guard Int32(parts[1]) != nil else { return nil }
    return .objectAtURL(url: url)
```

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat Spud/Utils/LemmyURLParser.swift SpudTests/LemmyURLParserTests.swift
git add Spud/Utils/LemmyURLParser.swift SpudTests/LemmyURLParserTests.swift
git commit -m "feat: classify /comment/ URLs as objectAtURL links"
```

### Task A3: `MainWindow.display(community:)` and `display(person:)`

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (add two methods next to `display(serverPostId:accountKeychainId:)`)

**Interfaces:**
- Consumes: `CommunityOrLoadingViewController(communityName:instance:accountKeychainId:dependencies:)`, `PersonOrLoadingViewController(personId:instance:accountKeychainId:dependencies:)`, existing `dependencies.nested`, `tabBarController`, `pushDetail(viewController:)`.
- Produces:
  - `func display(communityName: String, instance: InstanceActorId, accountKeychainId: String)`
  - `func display(personId: Components.Schemas.PersonID, instance: InstanceActorId, accountKeychainId: String)`

- [ ] **Step 1: Implement** the two methods, mirroring the tab-selection logic of `display(serverPostId:accountKeychainId:)` (push into the current tab's nav controller; fall back to the Posts split tab for a cold deep link). Extract the shared "push into current context" logic into a private helper to stay DRY:

```swift
/// Push a screen into whichever tab the user is currently in (so Back returns
/// there), falling back to the Posts split tab for cold deep links.
private func pushIntoCurrentContext(_ viewController: UIViewController) {
    let selected = tabBarController.selectedViewController
    if selected === splitViewController {
        pushDetail(viewController: viewController)
    } else if let navigationController = selected as? UINavigationController {
        navigationController.pushViewController(viewController, animated: true)
    } else {
        tabBarController.selectedIndex = 0
        pushDetail(viewController: viewController)
    }
}

func display(communityName: String, instance: InstanceActorId, accountKeychainId: String) {
    let vc = CommunityOrLoadingViewController(
        communityName: communityName,
        instance: instance,
        accountKeychainId: accountKeychainId,
        dependencies: dependencies.nested
    )
    pushIntoCurrentContext(vc)
}

func display(personId: Components.Schemas.PersonID, instance: InstanceActorId, accountKeychainId: String) {
    let vc = PersonOrLoadingViewController(
        personId: personId,
        instance: instance,
        accountKeychainId: accountKeychainId,
        dependencies: dependencies.nested
    )
    pushIntoCurrentContext(vc)
}
```

  Refactor `display(serverPostId:accountKeychainId:)` to also call `pushIntoCurrentContext(postDetailVC)` so the three share one path. Confirm `CommunityOrLoadingViewController` / `PersonOrLoadingViewController` `Dependencies` are satisfied by `dependencies.nested` (the same value `PostDetailOrEmptyViewController` receives).

- [ ] **Step 2: Build** the app target, verify it compiles.

Run: `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"`

- [ ] **Step 3: Format + commit**

```bash
mint run swiftformat Spud/Scenes/MainWindow/MainWindow.swift
git add Spud/Scenes/MainWindow/MainWindow.swift
git commit -m "feat: add MainWindow.display(community:) and display(person:)"
```

### Task A4: Route `.community` / `.person` / `.objectAtURL`-by-type in `AppCoordinator`

**Files:**
- Modify: `Spud/App/AppCoordinator.swift:63-94`
- Test: `SpudTests/AppCoordinatorRoutingTests.swift` (create) — only if `MainWindow.display(...)` can be faked; otherwise cover the pure `url.spud` → intent mapping and leave the window dispatch to manual test (documented).

**Interfaces:**
- Consumes: `url.spud` (`URL.SpudInternalLink`), `dependencies.accountService.{accountKeychainId(forInstance:),currentDefaultAccountKeychainId(),lemmyService(forAccountKeychainId:)}`, `MainWindow.display(serverPostId:accountKeychainId:)` / `display(communityName:instance:accountKeychainId:)` / `display(personId:instance:accountKeychainId:)`, `alertService` for the failure toast/haptic.

- [ ] **Step 1: Implement** the extended switch. `.community` / `.person` route directly; `.objectAtURL` resolves then routes by type; `.comment` from a resolve opens the post (scroll added in Slice D); unresolved → warning haptic + toast:

```swift
func open(_ url: URL, in window: MainWindow) {
    switch url.spud {
    case let .post(postId, instance):
        let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
        window.display(serverPostId: postId, accountKeychainId: accountKeychainId)

    case let .community(name, instance):
        let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
        window.display(communityName: name, instance: instance, accountKeychainId: accountKeychainId)

    case let .person(personId, instance):
        let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
        window.display(personId: personId, instance: instance, accountKeychainId: accountKeychainId)

    case let .objectAtURL(canonicalURL):
        resolveAndDisplay(canonicalURL, in: window)

    case .instance:
        logger.error("Instance links are not handled yet: \(url.absoluteString, privacy: .public)")

    case .none:
        logger.error("Received open url request for url that we can't handle: \(url.absoluteString, privacy: .public)")
    }
}

private func resolveAndDisplay(_ canonicalURL: URL, in window: MainWindow) {
    Task { @MainActor in
        guard let keychainId = dependencies.accountService.currentDefaultAccountKeychainId() else {
            logger.error("No default account to resolve link: \(canonicalURL.absoluteString, privacy: .public)")
            return
        }
        let lemmyService = dependencies.accountService.lemmyService(forAccountKeychainId: keychainId)
        let resolved = try? await lemmyService.resolveObject(query: canonicalURL.absoluteString)
        switch resolved {
        case let .post(postId, _):
            window.display(serverPostId: postId, accountKeychainId: keychainId)
        case let .community(name, instance):
            window.display(communityName: name, instance: instance, accountKeychainId: keychainId)
        case let .person(personId, instance):
            window.display(personId: personId, instance: instance, accountKeychainId: keychainId)
        case let .comment(postId, _, _):
            // Slice D adds scroll-to-comment; for now open the parent post.
            window.display(serverPostId: postId, accountKeychainId: keychainId)
        case .unresolved, .none:
            logger.error("Could not resolve object for: \(canonicalURL.absoluteString, privacy: .public)")
            dependencies.alertService.errorHaptic()
        }
    }
}
```

  Verify `dependencies` exposes `alertService` and an error-haptic call (search `AlertService` for the existing warning-haptic API used by `sharing`); if the method name differs, use that. If `alertService` is not on `AppCoordinator.dependencies`, drop the haptic line and keep the log (toast wiring tracked in Slice E).

- [ ] **Step 2: Build, verify compiles.** Run the Spud scheme build/test.
- [ ] **Step 3: Format + commit**

```bash
mint run swiftformat Spud/App/AppCoordinator.swift
git add Spud/App/AppCoordinator.swift
git commit -m "feat: route community/person/comment deep links in AppCoordinator"
```

---

## Slice B — Action extension ("Open in Spud" from the share sheet)

Depends on Slice A for non-post landing. Independently shippable once A is in.

### Task B1: Declare the `OpenInSpudAction` target

**Files:**
- Create: `OpenInSpudAction/Info.plist`, `OpenInSpudAction/OpenInSpudAction.entitlements` (app group only — needed only if future resolution moves in-extension; for the thin design, NO entitlements file is required, so omit unless the build wants one), `OpenInSpudAction/ActionRequestHandler.swift`
- Modify: `project.yml` (new target + embed in `Spud`)

**Interfaces:**
- Produces: a bundled app-extension `info.ddenis.Spud.OpenInSpudAction` embedded in the app.

- [ ] **Step 1: Add the target to `project.yml`** under `targets:` and as a dependency of `Spud` (so it embeds):

```yaml
  OpenInSpudAction:
    type: app-extension
    platform: iOS
    sources:
      - OpenInSpudAction
    dependencies:
      - target: SpudUtilKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: info.ddenis.Spud.OpenInSpudAction
        INFOPLIST_FILE: OpenInSpudAction/Info.plist
        GENERATE_INFOPLIST_FILE: "YES"
        SWIFT_VERSION: "6.0"
```

  And add `- target: OpenInSpudAction` to the `Spud` target's `dependencies:` list.

- [ ] **Step 2: Write `OpenInSpudAction/Info.plist`** with an Action-extension activation rule gated to Lemmy-ish web URLs (path contains `/post/`, `/comment/`, `/c/`, `/u/`). Use a predicate string:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Open in Spud</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.ui-services</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).ActionRequestHandler</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <dict>
                <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
                <integer>1</integer>
            </dict>
            <key>NSExtensionServiceAllowsFinderPreviewItem</key>
            <false/>
        </dict>
    </dict>
</dict>
</plist>
```

  Note: a string-predicate `NSExtensionActivationRule` matching the URL path is the precise gate, but the dictionary form (`...SupportsWebURLWithMaxCount = 1`) is the reliable baseline. Start with the dictionary form (offers for any web URL); the app's resolve fails gracefully on non-Lemmy URLs. A path-shape `NSPredicate` string can be substituted later if the share row should appear less often — verify predicate syntax against a device before committing to it.

- [ ] **Step 3: Write `ActionRequestHandler.swift`** — a non-UI handler that extracts the URL, builds the resolve deep link, opens the host app, and completes:

```swift
import SpudUtilKit
import UIKit
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        Task { @MainActor in
            guard let url = await Self.firstWebURL(in: context) else {
                context.completeRequest(returningItems: [], completionHandler: nil)
                return
            }
            let deepLink = URL.SpudInternalLink.objectAtURL(url: url).url
            await Self.open(deepLink, from: context)
            context.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private static func firstWebURL(in context: NSExtensionContext) async -> URL? {
        for item in context.inputItems.compactMap({ $0 as? NSExtensionItem }) {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   url.scheme == "http" || url.scheme == "https" {
                    return url
                }
            }
        }
        return nil
    }

    @MainActor
    private static func open(_ url: URL, from context: NSExtensionContext) async {
        // Prefer the extension context; fall back to walking the responder chain.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            context.open(url) { _ in cont.resume() }
        }
    }
}
```

  **Verify at execution:** `NSExtensionContext.open(_:completionHandler:)` opening a custom scheme from a UI-services action extension. If it no-ops on device/sim, replace `Self.open` with the responder-chain technique (walk `self`’s responder chain for a `UIApplication` and call `open(_:options:completionHandler:)`), which requires the handler to be a `UIViewController`-based action extension instead — in that case switch `NSExtensionPrincipalClass` to a storyboard-less `ActionViewController: UIViewController`.

- [ ] **Step 4: Generate + build.**

```bash
make project
python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"
```

- [ ] **Step 5: Commit**

```bash
git add project.yml OpenInSpudAction/
git commit -m "feat: add Open in Spud action extension"
```

### Task B2: Manual verification of the share-sheet path

- [ ] Build/run the app on the sim, then from Safari/Notes share a `https://lemmy.world/post/<id>` URL → "Open in Spud" → app opens the post. Repeat for `/c/<name>`, `/u/<name>`, `/comment/<id>`. Record results in `docs/features/`. (No automated test; document the matrix.)

---

## Slice C — Safari extension (banner + bundled allowlist)

Depends on Slice A. Independently shippable.

### Task C1: Generate the content-script `matches` allowlist from the Explorer seed

**Files:**
- Create: `scripts/generate-safari-matches.swift` (or `.py`) + a `make safari-matches` target in `Makefile`
- Modify: `OpenInAppExtension/Resources/manifest.json`

- [ ] **Step 1: Find the seed + decode path.** The bundled Explorer instance directory ships as `SpudDataKit/Resources/*.lzfse` and is decoded by `ExplorerService`. Inspect how it is decoded and what host field each instance carries (`grep -rn "lzfse\|decompress\|baseurl\|host" SpudDataKit/Services/Explorer SpudDataKit/Resources` and the importer). The generator must produce one match per host: `"*://<host>/*"`.
- [ ] **Step 2: Write the generator** that reads the seed (reusing the same decode the app uses, or a one-off decompressor) and emits a JSON array of `*://<host>/*` strings, then injects it into `manifest.json`'s `content_scripts[0].matches`. Keep it deterministic (sorted hosts) so regenerating produces a stable diff.
- [ ] **Step 3: Run it; confirm `manifest.json` now lists the instances** and the file is valid JSON (`jq . OpenInAppExtension/Resources/manifest.json >/dev/null`).
- [ ] **Step 4: Commit**

```bash
git add scripts/generate-safari-matches.* Makefile OpenInAppExtension/Resources/manifest.json
git commit -m "feat: generate Safari content-script allowlist from Explorer seed"
```

### Task C2: Rewrite `content.js` — path detection + banner (no auto-redirect)

**Files:**
- Modify: `OpenInAppExtension/Resources/content.js`
- Create: `OpenInAppExtension/Resources/banner.css` (or inline styles)
- Test: `OpenInAppExtension/Resources/__tests__/content.test.mjs` (node, no framework — assert URL → deep-link mapping and page-type detection)

- [ ] **Step 1: Write the node test** for a pure `lemmyDeepLink(href)` helper and `isLemmyContentPath(pathname)`:

```js
import assert from "node:assert";
import { lemmyDeepLink, isLemmyContentPath } from "../content.js";

assert.equal(isLemmyContentPath("/post/123"), true);
assert.equal(isLemmyContentPath("/comment/9"), true);
assert.equal(isLemmyContentPath("/c/news"), true);
assert.equal(isLemmyContentPath("/u/alice"), true);
assert.equal(isLemmyContentPath("/about"), false);

assert.equal(
  lemmyDeepLink("https://lemmy.world/post/123"),
  "info.ddenis.spud://internal/resolve?url=" + encodeURIComponent("https://lemmy.world/post/123")
);
console.log("ok");
```

  (Export the two pure helpers from `content.js` behind a guard so the browser side still runs; e.g. `export` + a non-module IIFE that no-ops when `window` is undefined.)

- [ ] **Step 2: Run `node OpenInAppExtension/Resources/__tests__/content.test.mjs`, verify it fails** (helpers not exported yet).
- [ ] **Step 3: Implement** `content.js`: export `isLemmyContentPath` + `lemmyDeepLink`; when running in a page whose path matches, inject a dismissible fixed-position banner ("Open in Spud" button + close). On button tap set `window.location = lemmyDeepLink(window.location.href)`. Remember dismissal in `sessionStorage` per `location.pathname` so it does not reappear. No `window.stop()`, no auto-redirect.
- [ ] **Step 4: Run the node test, verify pass.**
- [ ] **Step 5: Commit**

```bash
git add OpenInAppExtension/Resources/content.js OpenInAppExtension/Resources/banner.css OpenInAppExtension/Resources/__tests__/content.test.mjs
git commit -m "feat: Safari banner for any allowlisted Lemmy page (no auto-redirect)"
```

### Task C3: Localized strings + manifest wiring

**Files:**
- Modify: `OpenInAppExtension/Resources/_locales/en/messages.json`, `OpenInAppExtension/Resources/manifest.json` (register `banner.css` as a content-script CSS resource if used)
- [ ] Add `open_in_spud` / `dismiss` message strings; reference them from the banner. Build the extension scheme (`SpudWidgetExtension` is separate; the Safari ext builds with the app) and load it on the sim to confirm the banner appears on an allowlisted page and the deep link opens the app.
- [ ] **Commit**

```bash
git add OpenInAppExtension/Resources/_locales/en/messages.json OpenInAppExtension/Resources/manifest.json
git commit -m "feat: localize Open in Spud banner strings"
```

---

## Slice D — Comment deep-link scroll (the hard part)

Depends on Slice A. Optional polish; the parent post already opens without it.

### Task D1: Scroll to and highlight a deep-linked comment

**Files:**
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (add `display(serverPostId:scrollToCommentId:accountKeychainId:)`), `Spud/Scenes/PostDetail/PostDetailOrEmptyViewController.swift`, `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (expose a "scroll to server comment id after load" entry), `Spud/App/AppCoordinator.swift` (wire `.comment` → the new display method)

- [ ] **Step 1: Investigate** how a server comment id maps to the table's `elementId` used by `scrollToComment(elementId:)` (`PostDetailViewController.swift:509`) and `viewModel.indexPath(forCommentElementId:)`. Determine whether the comment is guaranteed loaded (it may be paginated / nested). Decide the load strategy: pass the target comment id down so the comment loader fetches the comment context, then resolve element id and scroll once present.
- [ ] **Step 2: Implement** a `scrollToServerCommentId` parameter threaded from `MainWindow.display(...)` → `PostDetailOrEmptyViewController` → `PostDetailViewController`, scrolling + applying the existing highlight when the row becomes available (reuse the new-comment highlight styling). Add a unit test for the id→elementId mapping if the view model exposes it purely; otherwise document a manual test.
- [ ] **Step 3: Wire** `AppCoordinator.resolveAndDisplay`'s `.comment` case to `window.display(serverPostId:scrollToCommentId:accountKeychainId:)`.
- [ ] **Step 4: Build, manual-verify** with a real `/comment/<id>` link. **Commit.**

---

## Slice E — Docs

### Task E1: Rewrite the share-extension feature doc

**Files:**
- Modify: `docs/features/share-extension.md`; add the failure-toast behavior + manual matrix; cross-link from `docs/features/sharing.md` and `docs/features/external-link-handling.md`.
- [ ] Update status from "partial" to shipped; describe the banner (allowlist), the Action extension (universal), and full post/comment/community/user coverage; note instance-home + Universal Links remain out of scope and why. **Commit** `docs: update share-extension feature doc for Open in Spud`.

---

## Self-Review notes

- Spec coverage: A (routing + comment data + parser) ✓, B (action extension) ✓, C (Safari banner + allowlist) ✓, D (comment scroll) ✓, E (docs) ✓. Error handling (unresolved → haptic/log/toast) in A4 + E1.
- Verification points deliberately left as investigate-then-implement (not placeholders): schema field names (A1), `NSExtensionContext.open` from action extension (B1), seed host extraction (C1), server-comment-id→elementId (D1). Each has a concrete fallback.
- Type consistency: `display(communityName:instance:accountKeychainId:)` and `display(personId:instance:accountKeychainId:)` names are used identically in A3 (definition) and A4 (call sites).
