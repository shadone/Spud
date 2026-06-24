# Configurable instance for Open in Browser and Share

Date: 2026-06-24

## Summary

Add two independent, user-configurable preferences that decide which instance a
post/comment link points at:

- **Open in Browser** (post-detail overflow menu) — defaults to **My Instance**
  (today's behavior).
- **Share** (post and comment) — defaults to **Original Instance** (today's
  behavior).

Both preferences offer the same two choices:

- **My Instance** — `https://<your-instance>/post|comment/<serverId>`.
- **Original Instance** — the canonical federation permalink (`ap_id`), falling
  back to your instance when the item is local or its `ap_id` is missing.

Defaults are chosen so shipped behavior is unchanged until the user opts in.

## Background: current behavior

Two divergent code paths build these URLs today:

- `AppService.openInBrowser(serverPostId:accountKeychainId:on:)`
  (`Spud/Services/App/AppService.swift`) always builds
  `<home-instance>/post/<serverPostId>` from the account's instance actor id,
  ignoring the post's `ap_id`. This is the **My Instance** behavior.
- `ShareURL.forPost` / `ShareURL.forComment`
  (`Spud/Utils/Sharing/ShareService.swift`) prefer the canonical `ap_id`
  (`originalPostUrl` / `originalCommentUrl`) and fall back to
  `<home-instance>/post|comment/<serverId>`. This is the **Original Instance**
  behavior.

The post-detail call sites are in
`Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`:
`openInBrowser()`, `sharePost()`, and `shareComment(serverCommentId:)`. The
overflow menu's "Open in Browser" `UIAction` calls `openInBrowser()`.

The preferences pattern to follow is the existing
`Preferences.OpenExternalLink` ("Open External Links in"):
`Spud/Services/Preferences/OpenExternalLink.swift` (enum) →
`@UserDefaultsBacked` + `*Stream` in `PreferencesService` →
mirrored property + `update…(_:)` + stream observation in
`PreferencesViewModel` → `Picker` in `PreferencesGeneralView`.

## Design

Both actions reduce to the same decision — "given a preference, a canonical
`ap_id`, a server id, and the home instance actor id, produce a URL" — so the
selection logic lives in one shared enum and one pure helper.

### 1. Shared enum: `Preferences.LinkInstance`

New file `Spud/Services/Preferences/LinkInstance.swift`:

```swift
extension Preferences {
    /// Which instance a post/comment link should point at.
    enum LinkInstance: String, RawRepresentable, Codable, CaseIterable, Identifiable {
        /// The account's home instance: `<home>/post|comment/<serverId>`.
        case myInstance
        /// The canonical federation permalink (`ap_id`), falling back to the
        /// home instance when absent.
        case originalInstance

        var id: String { rawValue }

        var title: String {
            switch self {
            case .myInstance: "My Instance"
            case .originalInstance: "Original Instance"
            }
        }
    }
}
```

One enum, reused by both settings.

### 2. Pure URL helper: `LinkURL` (generalized from `ShareURL`)

Today `ShareURL.forPost`/`forComment` hard-code the "prefer `ap_id`, else home"
rule. Generalize them with an `instance: Preferences.LinkInstance` parameter,
and — because the helper now serves Open-in-Browser as well as Share — rename
`ShareURL` to `LinkURL` and move it to its own file
`Spud/Utils/Sharing/LinkURL.swift`. `presentShareSheet(for:…)` stays in
`Spud/Utils/Sharing/ShareService.swift`.

```swift
enum LinkURL {
    static func forPost(
        instance: Preferences.LinkInstance,
        originalPostUrl: String?,
        serverPostId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(instance: instance, preferred: originalPostUrl,
            instanceActorId: instanceActorId, path: "post/\(serverPostId)")
    }

    static func forComment(
        instance: Preferences.LinkInstance,
        originalCommentUrl: String?,
        serverCommentId: Int64,
        instanceActorId: String?
    ) -> URL? {
        url(instance: instance, preferred: originalCommentUrl,
            instanceActorId: instanceActorId, path: "comment/\(serverCommentId)")
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

This collapses the two divergent code paths into one and makes the decision
unit-testable without UIKit.

### 3. `PreferencesService` (+ `PreferencesServiceType`)

Two `@UserDefaultsBacked` properties with `*Stream` accessors, both also exposed
on the `PreferencesServiceType` protocol (so `AppService` and the view
controller can read them):

```swift
@UserDefaultsBacked(key: "openInBrowserInstance")
var openInBrowserInstance: Preferences.LinkInstance = .myInstance

var openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> { $openInBrowserInstance }

@UserDefaultsBacked(key: "shareLinkInstance")
var shareLinkInstance: Preferences.LinkInstance = .originalInstance

var shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> { $shareLinkInstance }
```

Defaults preserve current behavior.

### 4. `AppService.openInBrowser`

Add an `originalPostUrl: String?` parameter (protocol + implementation) and
delegate URL choice to the helper:

```swift
func openInBrowser(
    serverPostId: Components.Schemas.PostID,
    originalPostUrl: String?,
    accountKeychainId: String,
    on viewController: UIViewController
) {
    guard let url = LinkURL.forPost(
        instance: preferencesService.openInBrowserInstance,
        originalPostUrl: originalPostUrl,
        serverPostId: Int64(serverPostId),
        instanceActorId: appDatabase.accountInstanceActorIdSync(forKeychainId: accountKeychainId)
    ) else { return }
    presentSafariViewController(url: url, on: viewController)
}
```

### 5. `PostDetailViewController`

- `openInBrowser()` passes `originalPostUrl: headerRow?.originalPostUrl`.
- `sharePost()` / `shareComment(serverCommentId:)` pass
  `instance: preferencesService.shareLinkInstance` into `LinkURL.forPost` /
  `LinkURL.forComment`. `preferencesService` is already reachable from the view
  controller's dependencies (same handle the rest of the screen uses); read the
  value at call time.

### 6. `PreferencesViewModel`

Two mirrored `@MainActor` properties (`openInBrowserInstance`,
`shareLinkInstance`), two `update…(_:)` methods (guard-on-change → write to
`preferencesService` → optional `Haptics.tap()`), and two stream-observation
tasks in `init`, all mirroring the existing `openExternalLink` wiring.

### 7. `PreferencesGeneralView`

Add a new dedicated `Section` (the existing "Links" header is for external links
in bodies, so use header **"Post & Comment Links"**) with two `Picker`s plus a
short explanatory footer:

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

Bindings follow the `openExternalLinks` pattern (computed `Binding` reading the
view-model property and calling the `update…` method).

## Data flow

```
PreferencesGeneralView (Picker)
  → PreferencesViewModel.update…(_:)
  → PreferencesService.<pref> (UserDefaults, broadcast via *Stream)

Open in Browser tap
  → PostDetailViewController.openInBrowser()  [passes headerRow.originalPostUrl]
  → AppService.openInBrowser(…)
  → LinkURL.forPost(instance: openInBrowserInstance, …)
  → SFSafariViewController

Share tap
  → PostDetailViewController.sharePost()/shareComment()
  → LinkURL.forPost/forComment(instance: shareLinkInstance, …)
  → presentShareSheet
```

## Error handling

- `LinkURL` returns `nil` when no usable URL can be built (no/invalid
  `instanceActorId` and no usable `ap_id`). Callers already handle `nil`:
  `openInBrowser` returns silently; `sharePost`/`shareComment` fire
  `Haptics.warning()` and return. Behavior unchanged.
- `.originalInstance` with an empty or unparseable `ap_id` falls back to the
  home-instance URL rather than failing.

## Testing

Unit tests (new `LinkURL` is pure and UIKit-free):

- `LinkURL.forPost` and `LinkURL.forComment`, each across the matrix:
  - `instance` ∈ {`.myInstance`, `.originalInstance`}
  - canonical url ∈ {present remote `ap_id`, empty/nil, unparseable}
  - `instanceActorId` ∈ {valid, nil}
  - Assert: `.originalInstance` + present `ap_id` → the `ap_id` URL;
    `.myInstance` (any `ap_id`) → `<instance>/post|comment/<id>`;
    `.originalInstance` + missing `ap_id` → home URL; nothing usable → `nil`.
- `PreferencesService` defaults: `openInBrowserInstance == .myInstance`,
  `shareLinkInstance == .originalInstance`.

The `@MainActor` `AppService`/`PreferencesViewModel`/Picker wiring stays thin and
is covered indirectly; no new snapshot tests required (a settings-screen
snapshot refresh is optional, not blocking).

## Scope / non-goals

- Does **not** change which browser app opens (the existing "Open External Links
  in" setting still governs In-App Safari vs system Safari).
- Does **not** add an "ask every time" option.
- Open in Browser remains post-only (there is no comment open-in-browser
  action); the share setting applies to both posts and comments.

## File touch list

New:

- `Spud/Services/Preferences/LinkInstance.swift`
- `Spud/Utils/Sharing/LinkURL.swift`
- Tests for `LinkURL` and the `PreferencesService` defaults.

Modified:

- `Spud/Utils/Sharing/ShareService.swift` (remove `ShareURL`, keep
  `presentShareSheet`)
- `Spud/Services/Preferences/PreferencesService.swift` (+ protocol)
- `Spud/Services/App/AppService.swift` (+ protocol signature)
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`
- `Spud/Scenes/Preferences/PreferencesViewModel.swift`
- `Spud/Scenes/Preferences/PreferencesGeneralView.swift`

New source files require `make project` (XcodeGen).
