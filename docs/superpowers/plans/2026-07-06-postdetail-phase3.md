# PostDetail VC-to-VM Migration Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PostDetailViewModel` owns every `lemmyService` call the PostDetail content scene makes — the VC layer's 16 inline call sites (19 distinct service methods) become thin, unit-tested VM methods; after this, `grep "lemmyService" Spud/Scenes/PostDetail/Content/PostDetailViewController*.swift` matches only the `linkRouterLemmyService` conformance property. This closes the last open scope of follow-ups spec section 1.

**Architecture (binding):** **VM dispatches; VC decorates.** Each VC call site keeps ALL its UI work in place — sign-in gates, haptics, offline toasts, confirmation prompts, menus, `alertService.handle(error, for:)` tags (including `+refreshPostInfo`'s deliberate empty catch and `refreshModerationCapability`'s `try?`) and its `Task { }` wrapping — and swaps only the `viewModel.accountScope.lemmyService.X(...)` expression for `viewModel.X(...)`. The VM methods are thin `async throws` forwarders with zero UI and zero new state. The test seam is a new scene-owned protocol, `PostDetailLemmyServicing` — exactly the 18 service methods PostDetail uses (option (b) from the Phase 1 scout; 18 closure init params would not scale, and the protocol matches the Phase 1 `PostVoteDispatching`/`PostSaveDispatching` house pattern). The existing `fetchCommentsOperation` closure seam stays **untouched** (Phase 2's fetch state-machine tests remain an unmodified regression net); the pull-to-refresh comments call routes through that same closure via a new `refreshComments()`, so `fetchComments` is deliberately NOT in the protocol. Two seams is accepted, documented state: closure = comment-fetching, protocol = everything else; unifying them is possible follow-up work, not this plan.

**Tech Stack:** Swift 6 strict concurrency (`@MainActor @Observable` VM; `LemmyServiceType` is an `Actor`; the new protocol is `Sendable` with `async` requirements — a `@MainActor` recording double satisfies them via isolated conformance), Swift Testing in SpudTests.

## Global Constraints

- **Zero behavior change.** Pure motion of the service-call expression; every gate/haptic/toast/alert/catch/`Task` shape stays byte-equivalent VC-side. If a move forces a semantic choice, STOP and report.
- Verify per task: `make build` + `make test-only ONLY=SpudTests`. Final gate: full `make test`. **Do NOT gate on `make snapshot`:** the reference Mac's snapshot rendering drifted at the host level on 2026-07-06 (see spec §5 addenda); this plan touches no rendering, and the refs in git are correct — do not re-record anything.
- Do not touch `startObservations`/`stopObservations`/`deinit` or the VC's `isolated deinit` teardown (Phase 2 template invariant).
- Out of scope (leave as-is): `linkRouterLemmyService` (`PostDetailViewController.swift:2249`, `InternalLinkRouting` conformance hands out the raw service — the Phase 2 grep-zero note already excuses it); post-level vote/save (`Spud/Utils/PostActions.swift` dispatchers, shared by 4 screens); `PostDetailLoadingViewController.swift:143` (separate VC, no content VM, read-only not-found probe).
- `mint run swiftformat <changed files>` before each commit; `mint run swiftformat --lint .` clean at the end. Stage explicit paths only (the worktree carries 440 cosmetic-`M` annex snapshot refs — never `git add -A`).
- Conventional commits. Push is user-gated; merge to local `main` only after the whole-branch review.

## Binding interfaces

New file `Spud/Scenes/PostDetail/Content/PostDetailLemmyServicing.swift` — protocol + live adapter. Signatures mirror `LemmyServiceType` (SpudDataKit/Services/Lemmy/LemmyService.swift) exactly; the protocol grows per task, and by Task 5 it is exactly:

```swift
/// The subset of `LemmyServiceType` the post-detail scene drives, seamed so
/// `PostDetailViewModel`'s dispatch methods are unit-testable from SpudTests
/// (which cannot import SpudDataKitTests' RecordingLemmyService).
protocol PostDetailLemmyServicing: Sendable {
    func reportPost(serverPostId: Components.Schemas.PostID, reason: String) async throws
    func reportComment(serverCommentId: Components.Schemas.CommentID, reason: String) async throws
    func deleteComment(serverCommentId: Components.Schemas.CommentID, deleted: Bool) async throws
    func deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool) async throws
    func removePost(serverPostId: Components.Schemas.PostID, removed: Bool, reason: String?) async throws
    func lockPost(serverPostId: Components.Schemas.PostID, locked: Bool) async throws
    func featurePost(serverPostId: Components.Schemas.PostID, featured: Bool, local: Bool) async throws
    func removeComment(serverCommentId: Components.Schemas.CommentID, removed: Bool, reason: String?) async throws
    func distinguishComment(serverCommentId: Components.Schemas.CommentID, distinguished: Bool) async throws
    func banFromCommunity(serverCommunityId: Components.Schemas.CommunityID, serverPersonId: Components.Schemas.PersonID, ban: Bool, removeData: Bool, reason: String?) async throws
    func retryComposition(clientToken: String) async
    func discardComposition(clientToken: String) async
    func setBlocked(serverPersonId: Components.Schemas.PersonID, blocked: Bool) async throws
    func markAsRead(serverPostId: Components.Schemas.PostID) async throws
    func fetchPostInfo(serverPostId: Components.Schemas.PostID) async throws
    func fetchModerationCapability() async throws -> ModerationCapability
    func vote(serverCommentId: Components.Schemas.CommentID, vote action: VoteStatus.Action) async throws
    func setSaved(serverCommentId: Components.Schemas.CommentID, saved: Bool) async throws
}

/// Production conformance: forwards to the account's `LemmyServiceType` actor.
struct PostDetailLemmyServiceAdapter: PostDetailLemmyServicing {
    let lemmyService: any LemmyServiceType
    // one-line forwarder per requirement
}
```

`PostDetailViewModel` additions (grows per task; final state):

```swift
@ObservationIgnored
private let lemmy: any PostDetailLemmyServicing
// init gains: lemmy: (any PostDetailLemmyServicing)? = nil
//   self.lemmy = lemmy ?? PostDetailLemmyServiceAdapter(lemmyService: accountScope.lemmyService)

// Thin dispatch methods (no UI, no new state). Where the target is always this
// post, the VM supplies its own serverPostId; Int64 comment/person ids convert
// to Components.Schemas types INSIDE the VM (the VC files lose that noise):
func reportPost(reason: String) async throws
func reportComment(serverCommentId: Int64, reason: String) async throws
func deleteComment(serverCommentId: Int64, deleted: Bool) async throws
func deletePost(serverPostId: Components.Schemas.PostID, deleted: Bool) async throws
func removePost(serverPostId: Components.Schemas.PostID, removed: Bool, reason: String?) async throws
func lockPost(serverPostId: Components.Schemas.PostID, locked: Bool) async throws
func featurePost(serverPostId: Components.Schemas.PostID, featured: Bool, local: Bool) async throws
func removeComment(serverCommentId: Int64, removed: Bool, reason: String?) async throws
func distinguishComment(serverCommentId: Int64, distinguished: Bool) async throws
func banFromCommunity(communityId: Components.Schemas.CommunityID, serverPersonId: Components.Schemas.PersonID, removeData: Bool, reason: String?) async throws // ban: true baked in — the UI only bans
func retryComposition(clientToken: String) async
func discardComposition(clientToken: String) async
func blockAuthor(serverPersonId: Int64) async throws // setBlocked(..., blocked: true) — the UI only blocks
func markAsRead() async throws
func refreshPostInfo() async throws
func fetchModerationCapability() async throws -> ModerationCapability
func refreshComments() async throws // try await fetchCommentsOperation(commentSortType) — reuses the EXISTING seam, NOT the protocol
func voteOnComment(serverCommentId: Int64, action: VoteStatus.Action) async throws
func setSavedOnComment(serverCommentId: Int64, saved: Bool) async throws
```

SpudTests additions:

- Create `SpudTests/Fakes/RecordingPostDetailLemmyService.swift`: `@MainActor final class RecordingPostDetailLemmyService: PostDetailLemmyServicing` with `enum Invocation: Equatable` (one case per method carrying its args), `private(set) var invocations: [Invocation]`, and `var errorToThrow: (any Error)?` (thrown by every throwing method before recording — records only successful dispatches). Grows per task alongside the protocol.
- Create `SpudTests/PostDetailViewModelMutationTests.swift`: one `@MainActor` Swift Testing suite, `makeViewModel(lemmy:)` fixture modeled on `PostDetailViewModelFetchTests.makeViewModel` (same `TestDependencies` shape; pass the double via the new `lemmy:` init arg, and `fetchCommentsOperation` where a test needs the refresh path). Per VM method: a forwarding test (call it, assert `invocations == [expected case with exact ids/args]` — for `banFromCommunity`/`blockAuthor` assert the baked `ban: true`/`blocked: true`) and, for throwing methods, a rethrow test (`errorToThrow` set → `#expect(throws:)`). `refreshComments` is tested through an injected `fetchCommentsOperation` spy asserting it receives the VM's current `commentSortType`.

Call-site map (from the 2026-07-06 scout; VC line anchors pre-change):

| VC site | Replaces | VM method |
|---|---|---|
| `+Report.swift:37` / `:59` | `reportPost` / `reportComment` | `reportPost(reason:)` / `reportComment(serverCommentId:reason:)` |
| `+DeleteRestore.swift:67` / `:113` | `deleteComment` / `deletePost` | same names |
| `+Moderation.swift:175/:189/:207/:235/:249/:284` | the six mod actions | same names (`banFromCommunity` drops `ban:`) |
| `+PendingComments.swift:46,:105` / `:62,:111,:140` | `retryComposition` / `discardComposition` | same names (non-throwing, `await` only) |
| `+OverflowMenu.swift:187` | `setBlocked(..., blocked: true)` | `blockAuthor(serverPersonId:)` |
| main `:590` / `:604` / `:1306` / `:1322` / `:1644` / `:1668` | `markAsRead` / `fetchModerationCapability` / `fetchComments` / `fetchPostInfo` / `vote` / `setSaved` | `markAsRead()` / `fetchModerationCapability()` / `refreshComments()` / `refreshPostInfo()` / `voteOnComment(...)` / `setSavedOnComment(...)` |

---

### Task 1: Seam foundation + Report group

**Files:**
- Create: `Spud/Scenes/PostDetail/Content/PostDetailLemmyServicing.swift` — protocol + adapter with the two report methods only.
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift` — `lemmy` stored property + optional init param (default `nil` → adapter; existing tests must compile unchanged) + `reportPost(reason:)` / `reportComment(serverCommentId:reason:)`.
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController+Report.swift` — swap both call expressions (`Haptics.tap()`, `Haptics.success()`, `presentReportSubmittedConfirmation()`, both `alertService` tags stay).
- Create (Test): `SpudTests/Fakes/RecordingPostDetailLemmyService.swift` + `SpudTests/PostDetailViewModelMutationTests.swift` (report tests: forwarding with exact `serverPostId`/`CommentID(id)`/reason + rethrow).

**STOP:** if the `Sendable` protocol + `@MainActor` double conformance fights strict concurrency (isolated-conformance diagnostics), report the exact diagnostic rather than sprinkling `nonisolated(unsafe)`/`@unchecked`.

- [ ] Steps: RED tests → seam + VM methods + VC swap → GREEN → `make build` + `make test-only ONLY=SpudTests` → swiftformat → commit `refactor: seam PostDetail lemmyService dispatch behind the view model (report group)` (explicit paths).

### Task 2: Delete/Restore group

**Files:**
- Modify: `PostDetailLemmyServicing.swift` (+`deleteComment`, `deletePost` in protocol + adapter), `PostDetailViewModel.swift` (+the two VM methods), `PostDetailViewController+DeleteRestore.swift` (swap `:67`, `:113`; `Task { @MainActor [weak self] }` shells and `Haptics.tap()` stay).
- Test: extend double + mutation tests (forwarding incl. `deleted: false` restore flavor + rethrow).

- [ ] Steps: RED → move → GREEN → build + SpudTests → swiftformat → commit `refactor: PostDetailViewModel dispatches delete/restore` (explicit paths).

### Task 3: Moderation group

**Files:**
- Modify: `PostDetailLemmyServicing.swift` (+6 mod methods), `PostDetailViewModel.swift` (+6 VM methods; `banFromCommunity` bakes `ban: true`), `PostDetailViewController+Moderation.swift` (swap the six `perform*` sites; capability gating, prompts, haptics, all six alert tags stay).
- Test: extend double + mutation tests (all six; assert `reason` nil/non-nil passthrough and `ban: true`).

- [ ] Steps: RED → move → GREEN → build + SpudTests → swiftformat → commit `refactor: PostDetailViewModel dispatches moderation actions` (explicit paths).

### Task 4: PendingComments + OverflowMenu groups

**Files:**
- Modify: `PostDetailLemmyServicing.swift` (+`retryComposition`/`discardComposition` — **non-throwing `async`**, mirror the service exactly — and `setBlocked`), `PostDetailViewModel.swift` (+`retryComposition`/`discardComposition`/`blockAuthor`), `PostDetailViewController+PendingComments.swift` (five sites: the four fire-and-forget `UIAlertAction` `Task { await self?.viewModel.… }` shapes and `:140`'s awaited discard-then-recompose stay structurally identical), `PostDetailViewController+OverflowMenu.swift` (`submitBlockAuthor` body calls `viewModel.blockAuthor`; `.setBlockedPerson` alert tag stays).
- Test: extend double + mutation tests (retry/discard record tokens; `blockAuthor` forwards `blocked: true` + rethrow).

- [ ] Steps: RED → move → GREEN → build + SpudTests → swiftformat → commit `refactor: PostDetailViewModel dispatches pending-comment and block actions` (explicit paths).

### Task 5: Main-file group (read-path wrappers + comment vote/save)

**Files:**
- Modify: `PostDetailLemmyServicing.swift` (+`markAsRead`, `fetchPostInfo`, `fetchModerationCapability`, comment `vote`, comment `setSaved`), `PostDetailViewModel.swift` (+`markAsRead()`, `refreshPostInfo()`, `fetchModerationCapability()`, `refreshComments()` — via `fetchCommentsOperation(commentSortType)`, NOT the protocol — `voteOnComment`, `setSavedOnComment`), `PostDetailViewController.swift` (swap the six sites: `markAsRead`'s catch tag, `refreshModerationCapability`'s `try? … ?? .none` + `Task.isCancelled` guard, `reloadAsync`'s `async let postInfoRefresh` concurrency shape + `endRefreshing`, `refreshPostInfo`'s **empty catch with its comment**, `voteOnComment`'s sign-in gate/haptic/offline toast, `setSavedOnComment`'s haptic/toast — all stay).
- Test: extend double + mutation tests; `refreshComments` spy-through-closure test; `voteOnComment`/`setSavedOnComment` forwarding (exact `CommentID`/action/saved) + rethrow.

**STOP:** `refreshComments()` must not touch the `fetchComments()` cancel-and-replace state machine (`isLoadingComments`, `commentFetchError`, `fetchTask`) — it is the bare closure call, matching today's direct service call from `reloadAsync`. If that reads wrong during implementation, report; don't "improve" it.

- [ ] Steps: RED → move → GREEN → build + SpudTests (ALL existing PostDetailViewModel suites must pass untouched) → swiftformat → commit `refactor: PostDetailViewModel dispatches remaining lemmyService calls` (explicit paths).

### Task 6: Final gates + docs + review + merge

- [ ] `grep -n "lemmyService" Spud/Scenes/PostDetail/Content/PostDetailViewController*.swift` → only the `linkRouterLemmyService` conformance (comment it as the documented exception if not already).
- [ ] Full `make test` green; `mint run swiftformat --lint .` clean. NO snapshot gate (env, see Global Constraints).
- [ ] Docs: add the Phase 3 "Landed" note to `docs/superpowers/specs/2026-07-05-follow-ups.md` §1 (mirroring the Phase 1/2 note style; section 1 is then fully closed — say so). `grep -rn "lemmyService" docs/features/` to confirm no feature doc describes the old wiring (none expected; fix if found). Commit `docs: record PostDetail Phase 3 landing in follow-ups spec`.
- [ ] Whole-branch review by a fresh reviewer (most capable model): risk list = behavior drift at the 16 swapped sites (gates/haptics/toasts/catches/Task shapes), seam isolation correctness, test assertions actually pinning args, accidental snapshot-ref staging.
- [ ] ONE fix agent for the findings list; re-run gates after fixes.
- [ ] Merge protocol (per workspace CLAUDE.md): `git fetch` + re-check `main..worktree-postdetail-phase3` and file overlap RIGHT BEFORE merging (main moved five times during the prior arc); if the shared checkout is on `main` and clean of overlapping dirt, `git annex restage` there FIRST, then `git merge --no-ff worktree-postdetail-phase3`; otherwise the temp-worktree pattern. Push only on the user's explicit word.
