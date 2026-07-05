# PostDetail VC-to-VM Migration Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shrink the 3,098-line `PostDetailViewController` via pure-motion sibling-extension extractions, and fold its post-level vote/save into the shared post-actions protocol (with a vote/save protocol split + an offline-toast dispatch hook). ZERO behavior change.

**Architecture:** Phase 1 deliberately EXCLUDES the GRDB observation-loop move (Phase 2 — needs an observable comments-revision signal because `orderedComments` is intentionally `@ObservationIgnored`, plus DB-backed VM tests). This phase is: (a) five sibling extension files following the `PostListViewController+OfflineDownload.swift` precedent (cross-file access raises get `// internal: shared with +X` markers, LemmyService-split style); (b) `PostActionDispatching` split into `PostVoteDispatching` / `PostSaveDispatching: PostVoteDispatching`, `presentSignInGate` requirement dropped (the `UIViewController+SignInGate.swift:16` extension already provides it to all conformers), an optional offline pre-dispatch hook added, and PostDetail conformed.

**Tech Stack:** Swift 6 strict concurrency (@MainActor VCs), UIKit, Swift Testing, XCTest snapshots/UITests.

## Global Constraints

- ZERO user-visible behavior change: strings, haptics, menu ordering, toast behavior byte-identical. Pure motion means zero edits to moved bodies (only access-level raises with marker comments and the removal of `private` on the moved funcs that need cross-file visibility).
- Line anchors were verified at branch base 1714ed4b by a scout; re-verify by content.
- The comment-level vote/save path MUST keep working after the post-level fold: `canSaveOrPresentSignInAlert`, `showOfflineActionToastIfNeeded`, `offlineVoteToast`/`offlineSaveToast` are SHARED by both paths — they stay on the VC (or the +Content seam), never deleted.
- After adding files: `make project`. SwiftFormat changed paths BEFORE final verify. Stage explicit paths. Branch check (`worktree-postdetail-vm-phase1`) before each commit. NEVER cd into the shared main checkout.
- Per-task verify: `make build` + `make test-only ONLY=SpudTests` (382 baseline). Full `make snapshot` (258 baseline, currently green) + full `make test` once, at the final task. If a snapshot run hits mass phantom failures, suspect the stale-app-on-shared-sim mode FIRST (uninstall app + clean build) before any other diagnosis.

---

### Task 1: Extract `+Content.swift` (shared helpers) + `+Report.swift` + `+DeleteRestore.swift`

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/PostDetailViewController+Content.swift` — move `isOwnContent` (~line 1745; reads `appDatabase.accountOwnPersonIdsSync`) and `canSaveOrPresentSignInAlert` (~1690) and `canReportOrPresentSignInAlert` (~within Report block) and the offline-toast helpers `showOfflineActionToastIfNeeded`/`offlineVoteToast`/`offlineSaveToast` (~1582-1597). These are the cross-seam shared members.
- Create: `Spud/Scenes/PostDetail/Content/PostDetailViewController+Report.swift` — the Report MARK (~1740-1808) MINUS the members moved to +Content: `reportPost`, `submitPostReport`, `reportComment`, `submitCommentReport` (+ their `presentReportReasonAlert`/`presentReportSubmittedConfirmation` helpers if they live in the block).
- Create: `Spud/Scenes/PostDetail/Content/PostDetailViewController+DeleteRestore.swift` — both Delete/Restore MARKs (~1809-1909): `promptDeleteComment`, `editOwnComment`, `setDeletedOnComment`, `promptDeletePost`, `setDeletedOnPost`.
- Modify: `PostDetailViewController.swift` (deletions + access raises only).

**Rules:** moved funcs lose `private` only where a DIFFERENT file calls them (check each call site; same-file callers moved together need nothing). Main-file members the moved code touches (`viewModel`, `alertService`, `presentComposer`, `headerRow`, dicts) — `private` is file-scoped, so raise to `internal` with the marker comment ONLY what the new files reference. Copy the file-header style from `PostListViewController+OfflineDownload.swift`.

- [ ] Step 1: Read the precedent file + the three blocks; build the move-map (func -> destination, member -> raise) and put it in your report.
- [ ] Step 2: Move verbatim; `make project`; build.
- [ ] Step 3: `make test-only ONLY=SpudTests` green (382). Motion audit: main file shrinks by ≈ sum of new files (± headers); `git diff` shows essentially no added lines in the main file beyond raises.
- [ ] Step 4: SwiftFormat; commit `refactor: extract PostDetail content/report/delete seams into sibling files`.

---

### Task 2: Extract `+Moderation.swift` + `+PendingComments.swift` + `+OverflowMenu.swift`

**Files:**
- Create: `.../PostDetailViewController+Moderation.swift` — the Moderation MARK (~1910-2185): `postModerationMenu`, `commentModerationMenu`, the 7 `perform*`/`prompt*`, `presentModerationReasonAlert`, `presentBanFromCommunityConfirmation`. EXCLUDE the composer presenters (`replyToPost`/`replyToComment`/`presentComposer`/`presentEditPost`, ~2187-2249) — they stay in the main file (several seams call them); raise `presentComposer` to `internal` with a marker.
- Create: `.../PostDetailViewController+PendingComments.swift` — Pending MARK (~2251-2384): `handlePendingTap`, `handleEditOverlayTap`, `editFailedComment`. These are invoked from cell-provider closures in the main file — they must be `internal`. The pending dicts (`pendingTokenByElementId`, `pendingStateByElementId`, `editOverlayByElementId`) STAY in the main file (populated by `mergedCommentItems`); raise to `internal`.
- Create: `.../PostDetailViewController+OverflowMenu.swift` — Overflow MARK (~2386-2570): `makePostOverflowMenu` (called from the header-observation closure in the main file — `internal`), `makeMuteCommunityMenu`, `muteCommunity`, `blockAuthor`, `submitBlockAuthor`, `presentTextSelection`.
- Modify: `PostDetailViewController.swift`.

Same rules as Task 1. `moderationCapability` and `headerRow` will need raises.

- [ ] Step 1: move-map (include every raise with its consuming file).
- [ ] Step 2: Move verbatim; `make project`; build.
- [ ] Step 3: `make test-only ONLY=SpudTests` green. Motion audit as Task 1.
- [ ] Step 4: SwiftFormat; commit `refactor: extract PostDetail moderation/pending/overflow seams into sibling files`.

---

### Task 3: Protocol split + hook (PostVoteDispatching / PostSaveDispatching)

**Files:**
- Modify: `Spud/Utils/PostActions.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`, `Spud/Scenes/Person/Content/PersonViewController.swift`, `Spud/Scenes/Activity/ActivityViewController.swift` (conformance lines + Activity's stub deletion)

**Interfaces (produces):**
```swift
@MainActor protocol PostVoteDispatching: UIViewController {
    var postActionsAccountScope: AccountScope { get }
    var postActionsAlertService: AlertServiceType { get }
    /// Called just before a vote/save dispatches while offline-queued behavior may apply.
    /// Default: no-op. PostDetail shows its offline-action toast here.
    func postActionWillDispatch(_ action: PostActionKind)
}
@MainActor protocol PostSaveDispatching: PostVoteDispatching {
    func currentSavedState(serverPostId: Int64) -> Bool
}
enum PostActionKind { case vote, save }
```
- `presentSignInGate` REMOVED as a requirement (default impls keep calling it — resolves via the `UIViewController` extension; add a one-line comment saying that is deliberate, citing the shadowing footgun).
- `vote(serverPostId:action:)` moves to `PostVoteDispatching`'s extension and calls `postActionWillDispatch(.vote)` after the haptic, before the lemmyService call. `toggleSaved`/`setSaved` move to `PostSaveDispatching`'s extension; `setSaved` calls `postActionWillDispatch(.save)` after its haptic.
- Conformers: PostList + Person adopt `PostSaveDispatching` (no body changes — `postActionWillDispatch` default no-op preserves today's no-toast behavior). Activity adopts `PostVoteDispatching` only and DELETES its stub `currentSavedState` (+ its comment).

**Behavior guard:** for PostList/Person/Activity, rendered behavior must be byte-identical (the hook defaults to no-op). This is a protocol-shape refactor, not a feature.

- [ ] Step 1: Implement; `make project`; build.
- [ ] Step 2: `make test-only ONLY=SpudTests` green. Grep guard: `currentSavedState` gone from ActivityViewController; no conformer implements `presentSignInGate`.
- [ ] Step 3: SwiftFormat; commit `refactor: split post-action protocol into vote/save halves with dispatch hook`.

---

### Task 4: Fold PostDetail's post-level vote/save into the protocol

**Files:**
- Modify: `PostDetailViewController.swift` (or the +Content seam — wherever the fold reads cleanest): delete `voteOnPost` (~1599), `toggleSavedOnPost`/`setSavedOnPost` (~1700-1718); add `PostSaveDispatching` conformance:
  - `postActionsAccountScope` -> `viewModel.accountScope`
  - `postActionsAlertService` -> `alertService`
  - `currentSavedState(serverPostId:)` -> `headerRow?.isSaved ?? false`
  - `postActionWillDispatch(_:)` -> `showOfflineActionToastIfNeeded(offlineVoteToast)` for `.vote`, `...(offlineSaveToast)` for `.save` — EXACTLY the toasts the deleted methods showed, same call order (post-haptic, pre-send).
- Re-point the post-level call sites (swipe actions, context menu, header cell callbacks — find them: they call `voteOnPost`/`toggleSavedOnPost`) to the protocol methods `vote(serverPostId:action:)`/`toggleSaved(serverPostId:)` — the serverPostId comes from the VM/headerRow; verify each site has it in scope.
- COMMENT-LEVEL vote/save (`voteOnComment`, `toggleSavedOnComment`, `setSavedOnComment`) stay untouched and keep using the shared helpers (which is why they live in +Content).

**Behavior guard:** sign-in gates (post-level used `canSaveOrPresentSignInAlert` for save — the protocol's `toggleSaved` uses `presentSignInGate(title: "Sign in to save")`; VERIFY the user-visible result is identical (read `canSaveOrPresentSignInAlert` — if it presents a different alert/copy than the protocol's gate, STOP and report the delta rather than silently changing UX; the resolution may be keeping a thin PostDetail override that calls the old gate).

- [ ] Step 1: Read the deleted methods + every call site + the gate-copy comparison FIRST; report the gate verdict before editing if they differ.
- [ ] Step 2: Implement; build; `make test-only ONLY=SpudTests` green.
- [ ] Step 3: Manual-diff audit: strings/haptics/toast order identical; grep "Sign in to vote|Sign in to save" count unchanged or accounted.
- [ ] Step 4: SwiftFormat; commit `refactor: PostDetail post-level vote/save via PostSaveDispatching`.

---

### Task 5: Final verify + docs + merge

- [ ] Step 1: `wc -l PostDetailViewController.swift` — report the shrink (expect roughly 900-1,000 lines out).
- [ ] Step 2: Full `make test` (all unit targets + UITests incl. the PostDetail UITests) green; full `make snapshot` green (258; stale-app guard first if mass failures).
- [ ] Step 3: Docs: follow-ups spec section 1 — "Landed (2026-07-06): Phase 1a/1b" note (seam files, protocol split, fold; observation move = Phase 2 open). No CLAUDE.md change needed unless a reviewer finds a stale claim.
- [ ] Step 4: Whole-branch review (fresh reviewer, most capable model): verbatim-motion audit on both extraction commits, protocol-refactor behavior guard on the 3 conformers, the fold's gate-copy verdict, ledger triage.
- [ ] Step 5: Fix findings; merge --no-ff into main (re-check main advance + main-checkout state first; merge main INTO branch if moved), byte-identical check, cleanup.
