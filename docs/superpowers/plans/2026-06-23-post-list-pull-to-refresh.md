# Post list pull-to-refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pull-to-refresh to the post list that re-pulls the feed from the top while keeping the existing posts on screen, and surfaces a failed refresh as a toast.

**Architecture:** All changes live in `PostListViewController.swift`. Pull-to-refresh reuses the existing fresh-feed reload (`viewModel.didClickReload()`, which mints a new feed key) and mirrors the `InboxViewController` convention: the `UIRefreshControl` is the only progress indicator while `refreshControl.isRefreshing`, so the loading skeleton is suppressed and the current posts stay visible until the new feed's first GRDB snapshot swaps them in. No view-model or data-layer changes.

**Tech Stack:** UIKit, `UITableViewDiffableDataSource`, GRDB-backed `AsyncStream` observation, `ToastPresenter` (existing app-target pill toast).

## Global Constraints

- All edits are confined to `Spud/Scenes/PostList/PostListViewController.swift`. No view-model or data-layer changes.
- No emojis in code, comments, or commit messages.
- Conventional commit subjects (`feat:`).
- Spud target is Swift 6 language mode / strict concurrency; the edits are synchronous `@MainActor` view-controller methods, so they add no new cross-actor hops.
- Run SwiftFormat before staging: `mint run swiftformat <changed paths>` (pre-commit hook lints).
- Build check command: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` (auto-picks the booted sim; otherwise pass `--simulator "iPhone 17 Pro"`).
- Existing conventions to match: `InboxViewController.swift:90` (refresh control lazy var + `endRefreshing()` in render), `MainWindow.swift:326` (`ToastPresenter.shared.show(message, in: window)`).
- The working tree has pre-existing modified snapshot PNGs (git-annex, cosmetic) — do NOT stage them. Stage only `PostListViewController.swift` (and this plan/spec). Never `git add -A`.

## File Structure

- **Modify** `Spud/Scenes/PostList/PostListViewController.swift`:
  - new `refreshControl` lazy property (UI Properties section, after `tableView`)
  - attach `tableView.refreshControl` in `viewDidLoad()`
  - new `@objc refreshTriggered()`
  - `feedChanged()` gains a `keepingContent: Bool = false` parameter
  - `applyLoadState(_:)` suppresses the skeleton while refreshing, ends the control on every settle state, and (Task 2) keeps posts + toasts on a failed refresh
  - new `showRefreshFailureToast(for:)` (Task 2)

No test files: this is UIKit integration glue over existing, already-tested view-model methods (`didClickReload()`, `loadFirstPage()`), with no new unit-testable seam. Each task is verified by a clean build plus a scripted manual simulator check. See each task's verification steps.

---

### Task 1: Pull-to-refresh gesture, keeping posts on a successful refresh

Wires up the `UIRefreshControl`, the fresh-feed reload, the content-preserving `feedChanged` path, and the skeleton suppression / `endRefreshing` in `applyLoadState`. After this task, pulling to refresh keeps the posts visible and swaps in fresh content on success. A *failed* refresh still falls back to the full error surface (refined in Task 2).

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (UI properties `:73-86`, `viewDidLoad` `:373-378`, `feedChanged` `:708-718`, `applyLoadState` `:814-835`)

**Interfaces:**
- Consumes (existing, unchanged): `viewModel.didClickReload()`, `viewModel.prepareForReload()`, `showLoadingSkeleton()`, `hideLoadingSkeleton()`, `loadingSkeletonView.setShowsSlowHint(_:)`, `viewModel.emptyState`, `makeErrorConfiguration(for:)`, properties `rowsByServerPostId`, `orderedRows`, `displayedRows`, `pinnedReadIds`, `markedReadIds`, `hasReceivedFirstSnapshot`.
- Produces (used by Task 2): `refreshControl: UIRefreshControl`, `feedChanged(keepingContent: Bool)`.

- [ ] **Step 1: Add the `refreshControl` lazy property**

In the `// MARK: UI Properties` section, immediately after the `tableView` lazy var (ends at `:86`), add:

```swift
private lazy var refreshControl: UIRefreshControl = {
    let control = UIRefreshControl()
    control.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
    return control
}()
```

- [ ] **Step 2: Attach the control and add the action in `viewDidLoad`**

Replace `viewDidLoad` (`:373-378`):

```swift
override func viewDidLoad() {
    super.viewDidLoad()

    tableView.refreshControl = refreshControl
    startObservations()
    feedChanged()
}
```

Add the action method. Place it directly above `feedChanged` (just before `private func feedChanged(...)` at `:708`):

```swift
@objc private func refreshTriggered() {
    // Pull-to-refresh re-pulls the feed from the top via a fresh feed key,
    // keeping the current posts on screen until the new content swaps in.
    viewModel.didClickReload()
    feedChanged(keepingContent: true)
}
```

- [ ] **Step 3: Add the `keepingContent` parameter to `feedChanged`**

Replace the head of `feedChanged` (`:708-718`, from the signature through `refreshModerationCapability()`). Leave the rest of the method body (the `let feedKey = ...` observation task) unchanged:

```swift
private func feedChanged(keepingContent: Bool = false) {
    viewModel.prepareForReload()
    observationTask?.cancel()
    // A pull-to-refresh keeps the existing posts on screen — the refresh
    // control is the only progress indicator — until the new feed's first
    // snapshot swaps them in. Read-id pins belong to the prior feed session,
    // so they reset either way; the new first snapshot re-pins.
    if !keepingContent {
        rowsByServerPostId.removeAll()
        orderedRows.removeAll()
        displayedRows.removeAll()
    }
    pinnedReadIds.removeAll()
    markedReadIds.removeAll()
    hasReceivedFirstSnapshot = false
    if !keepingContent {
        showLoadingSkeleton()
    }
    refreshModerationCapability()
```

- [ ] **Step 4: Suppress the skeleton while refreshing and end the control on settle**

Replace `applyLoadState(_:)` (`:814-835`). Note the `.failed` case here still uses the full error surface — Task 2 refines it:

```swift
private func applyLoadState(_ state: FeedLoadState) {
    switch state {
    case let .loading(slow):
        // During a pull-to-refresh the control is the only progress
        // indicator; keep the existing posts and skip the skeleton.
        if !refreshControl.isRefreshing {
            showLoadingSkeleton()
            loadingSkeletonView.setShowsSlowHint(slow)
        }
        contentUnavailableConfiguration = nil
    case .loaded:
        refreshControl.endRefreshing()
        hideLoadingSkeleton()
        contentUnavailableConfiguration = nil
    case .empty:
        refreshControl.endRefreshing()
        hideLoadingSkeleton()
        let empty = viewModel.emptyState
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: empty.symbolName)
        config.text = empty.title
        config.secondaryText = empty.message
        contentUnavailableConfiguration = config
    case let .failed(failure):
        refreshControl.endRefreshing()
        hideLoadingSkeleton()
        contentUnavailableConfiguration = makeErrorConfiguration(for: failure)
    }
}
```

- [ ] **Step 5: Format**

Run: `mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift`
Expected: completes, file conforms (no manual changes needed).

- [ ] **Step 6: Build**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: BUILD SUCCEEDED, 0 new warnings (the pre-existing benign `Duplicate -rpath '@executable_path'` warning is unchanged).

- [ ] **Step 7: Manual simulator check (success path)**

Boot a sim, run Spud, open a feed with several posts. Pull down to refresh.
Expected: the spinner appears, the existing posts stay on screen (no full-screen skeleton), and the list swaps to fresh posts when the fetch returns; the spinner then disappears.

- [ ] **Step 8: Commit**

```bash
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "feat: add pull-to-refresh to the post list"
```

---

### Task 2: Keep posts and toast on a failed refresh

Refines the `.failed` branch of `applyLoadState` so a pull-to-refresh that fails while posts are on screen keeps those posts and shows a transient toast, instead of replacing the list with the full error surface. A failed refresh with no posts (and every normal initial-load failure) is unchanged.

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (`applyLoadState` `.failed` case; new `showRefreshFailureToast(for:)`)

**Interfaces:**
- Consumes: `refreshControl` and `feedChanged(keepingContent:)` (Task 1); existing `displayedRows`, `makeErrorConfiguration(for:)`, `hideLoadingSkeleton()`, `LoadFailure` (its `.kind == .offline`), `ToastPresenter.shared.show(_:in:)`.
- Produces: none (terminal task).

- [ ] **Step 1: Replace the `.failed` case in `applyLoadState`**

In `applyLoadState(_:)`, replace the `case let .failed(failure):` block from Task 1 with:

```swift
    case let .failed(failure):
        // A failed pull-to-refresh keeps the existing posts on screen and
        // surfaces the failure as a transient toast, rather than replacing
        // the list with the full error surface. With no posts to keep (or a
        // normal initial-load failure), fall back to the error surface.
        if refreshControl.isRefreshing, !displayedRows.isEmpty {
            refreshControl.endRefreshing()
            showRefreshFailureToast(for: failure)
        } else {
            refreshControl.endRefreshing()
            hideLoadingSkeleton()
            contentUnavailableConfiguration = makeErrorConfiguration(for: failure)
        }
```

- [ ] **Step 2: Add `showRefreshFailureToast(for:)`**

Add directly below `makeErrorConfiguration(for:)` (ends at `:860`):

```swift
/// Surfaces a failed pull-to-refresh as a transient toast, keeping the
/// existing posts on screen.
private func showRefreshFailureToast(for failure: LoadFailure) {
    guard let window = view.window else { return }
    let message = failure.kind == .offline
        ? NSLocalizedString("You're offline", comment: "Toast when pull-to-refresh fails while offline")
        : NSLocalizedString("Couldn't refresh", comment: "Toast when pull-to-refresh fails")
    ToastPresenter.shared.show(message, in: window)
}
```

- [ ] **Step 3: Format**

Run: `mint run swiftformat Spud/Scenes/PostList/PostListViewController.swift`
Expected: completes, file conforms.

- [ ] **Step 4: Build**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: BUILD SUCCEEDED, 0 new warnings.

- [ ] **Step 5: Manual simulator check (failure path)**

With posts on screen, enable airplane mode (or a 100%-loss Network Link Conditioner profile), then pull to refresh.
Expected: the existing posts stay on screen, a "You're offline" toast appears near the bottom for ~2s, and the spinner ends. Disable airplane mode and pull again to confirm the success path still swaps in fresh content.

- [ ] **Step 6: Commit**

```bash
git add Spud/Scenes/PostList/PostListViewController.swift
git commit -m "feat: keep posts and toast on a failed post-list refresh"
```

---

## Self-Review

**Spec coverage:**
- Decision 1 (refresh = fresh feed key) → Task 1 Step 2 (`refreshTriggered` calls `didClickReload()`).
- Decision 2 (keep posts; control is sole indicator) → Task 1 Steps 3-4 (`keepingContent` branch + skeleton suppression).
- Decision 3 (failed refresh keeps posts + toast) → Task 2.
- Decision 4 (all feed types) → inherent: the change is in the shared `PostListViewController`; no feed-type gating added.
- Edge: empty after refresh → handled by the existing `apply(rows: [])` + `.empty` case (Task 1 Step 4), unchanged.
- Edge: failed refresh with no content / normal load failure → Task 2 Step 1 `else` branch.
- Edge: offline auto-retry on reconnect → untouched (`reachabilityObservationTask` still calls `feedChanged()` with default `keepingContent: false`).
- Testing approach (build + manual) → each task's Steps.

**Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows complete code; commands have expected output.

**Type consistency:** `refreshControl: UIRefreshControl` and `feedChanged(keepingContent: Bool)` are named identically in Tasks 1 and 2. `showRefreshFailureToast(for: LoadFailure)` matches `applyLoadState`'s `failure` binding (`FeedLoadState.failed(LoadFailure)`). `failure.kind == .offline` matches the existing usage at `PostListViewController.swift:444`.
