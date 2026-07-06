# PostList/Community VM-Owns-Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PostListViewModel` owns the row observation, the lazy-feed gate, the row lookup, and the sync accessors (PostDetail Phase 2 template); `CommunityViewModel` absorbs the six stray favorite/mute sync calls. Zero user-visible behavior change.

**Architecture:** Replicate the Phase 2 idioms verbatim where they apply — `@ObservationIgnored` rows + published `rowsRevision: Int`, atomic lookup rebuild in the same synchronous turn, VC revision-guard reaction, `startObservations()`/`stopObservations()` symmetry, sync-accessor wrappers, DB-backed in-memory tests. Honor the four PostList-specific differences (scout-verified): (1) the VM is MUTATED on feed change, never replaced — restart semantics, no setPost analogue; (2) the lazy-feed gate awaits `loadFirstPage()` INLINE then re-resolves and starts observing in the same task (the feed row is fetch-created); (3) pull-to-refresh needs a `keepingContent` restart flavor (observation restarts while rows/lookup/snapshot stay until the first new emit); (4) `displayedRows` is a hide-read VIEW transform — the VM publishes raw rows, the filter and its session state stay on the VC.

**Scout report anchors** (verified at branch base 8d7062bb; re-verify by content): the per-emit pipeline order at PostListViewController.swift:1080-1112 (isFirstSnapshot latch -> first-snapshot pinnedReadIds -> resolveInitialSnapshot EVERY emit BEFORE apply [load-bearing: Saved-feed stuck-skeleton regression guard] -> apply(rows:) [orderedRows -> hide-read filter -> rowsByServerPostId rebuild :1129 -> diffable apply -> applyLoadState] -> first-snapshot cached-empty loadFirstPage kick); the lazy-feed gate at :1023-1114 (feedRowIdSync nil -> await loadFirstPage -> re-resolve -> observe); 15 dict reads (:629, 1309, 1471, 1492, 1548, 1612, 1634, 1691, 1719, 1885, 1939, 1978, 2002, 2082, 2217 — :1309 is the assertion trap); sync writes muteCommunitySync :1619 / accountInstanceActorIdSync :1629 / recordPostSeen :1697; offline extension reads +OfflineDownload.swift:60,101; the paired reset clearPostItems :1264 <-> rowsByServerPostId.removeAll :1039 (unpairing = "Missing PostListRow"); Community strays at CommunityViewController.swift:346,373,383,409,426-436.

## Global Constraints

- ZERO user-visible behavior change. Pipeline order per emit preserved verbatim; `resolveInitialSnapshot` before apply on EVERY emit; the cached-empty kick and pinnedReadIds first-snapshot gating identical.
- EXCLUDED (scout-verified out of scope): lemmyService actions (already VM-routed), display-preference observation loops (:695-848, PreferencesService not GRDB), hide-read filter + displayedRows + pinned/marked session state, moderationCapability, scroll-undo/NSFW-reveal/seen-dwell timing/offline UI/title/skeleton/error surfaces.
- Worktree hygiene (all documented): pointer sweep before suite runs; stale-app uninstall before first run; `pgrep -x xcodebuild` for contention; sim reboot on timeout cascades; annex ceremony only if refs need re-recording (none expected — this is behavior-preserving).
- `git branch --show-current` == `worktree-postlist-vm` before commits; never cd into the shared main checkout.
- Per-task verify: `make build` + `make test-only ONLY=SpudTests`. Full `make test` + `make snapshot` (258 green baseline) at the final task.
- TDD for every VM behavior: RED-first where the API is new; the template harness is `SpudTests/PostDetailViewModelObservationTests.swift`; the existing `PostListViewModelLoadStateTests` TestDependencies already builds an in-memory AccountService.

---

### Task 1: Inject appDatabase + VM sync-accessors

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewModel.swift` — add `@ObservationIgnored private let appDatabase: AppDatabase` via init param (single construction site PostListViewController.swift:~300; update the LoadState tests' harness). Add accessors, template-verbatim from `PostDetailViewModel`: `var instanceActorId: String?` (wraps accountInstanceActorIdSync), `func muteCommunity(communityActorId:until:)`, `func recordSeen(_ snapshot: PostInteractionSnapshot ...)` (match the exact recordPostSeen call shape at :1688-1701 — read it; the VC keeps SeenDwellTracker/timer, only the write moves), `func accountAndSiteRowIds() -> ...` (the +OfflineDownload shape at :60,101).
- Modify: `PostListViewController.swift` (:1619, :1629, :1697) + `PostListViewController+OfflineDownload.swift` (:60, :101, and check :112's accountService.instanceActorId — leave unless it duplicates the VM accessor trivially) — re-point to the VM accessors.
- Test: extend/new `SpudTests/PostListViewModelObservationTests.swift` (start the file now with the accessor tests; observation tests land in Task 2): muteCommunity writes the row (assert via isCommunityMutedSync), instanceActorId resolves the seeded account, recordSeen persists the interaction.

- [ ] TDD RED (new APIs) -> implement -> re-point -> GREEN (new tests + full SpudTests + LoadState suite untouched) -> `make build` -> SwiftFormat -> commit `refactor: PostListViewModel gains appDatabase + sync accessors`.

---

### Task 2: Move the row observation + lazy-feed gate into the VM

**Files:**
- Modify: `PostListViewModel.swift` — `startObservations()` owning the FULL bring-up as one task: feedRowIdSync gate -> if nil `await loadFirstPage()` (+ Task.isCancelled check) -> re-resolve (defensive failInitialLoad path preserved verbatim) -> `for await rows in appDatabase.observePostListRows(feedId:)`; per emit IN ORDER: isFirstSnapshot latch, first-snapshot `pinnedReadIdsSeed` publication (the VC's HideReadPostsFilter.readIds call needs the FIRST rows — decide: VM publishes `firstSnapshotReadIds` or the VC computes it in its reaction gated on its own first-reaction latch; pick whichever preserves :1088's semantics exactly and justify), `resolveInitialSnapshot(rowCount:)` (self-call), store `orderedRows` + rebuild `rowsByServerPostId` ATOMICALLY (same turn), bump published `rowsRevision`, then the first-snapshot cached-empty `loadFirstPage()` kick (:1108-1111 semantics). `stopObservations()`; restart flavors: `restartObservations(keepingContent: Bool)` — non-keeping resets rows+lookup (paired with the VC clearing its snapshot — see the :1257-1263 comment), keeping leaves them until the first new emit.
- Modify: `PostListViewController.swift` — `feedChanged(keepingContent:)` becomes: VM restart + a VC reaction loop keyed on `rowsRevision` (revision-guard idiom, PostDetailViewController :694-700) running: hide-read filter -> displayedRows -> diffable snapshot apply -> applyLoadState (the apply(rows:) tail minus the dict rebuild). Re-point the 15 dict reads to `viewModel.row(forServerPostId:)` / `viewModel.rowsByServerPostId`. Delete the VC's `orderedRows`/`rowsByServerPostId`/observation task; preserve the paired-reset ordering.
- Test: DB-backed observation tests (template harness): seeded feed+pages+posts -> start -> revision bumps + orderedRows/lookup atomic; the LAZY-FEED path: no feed row seeded + a fetchFeedOperation that persists one -> start -> gate awaits fetch -> observation lands rows (the zero-coverage scenario); keepingContent restart keeps rows until new emit; non-keeping resets.

- [ ] TDD RED -> move -> GREEN (new tests + LoadState suite + full SpudTests) -> `make build` -> SwiftFormat -> commit `refactor: PostListViewModel owns the row observation and lazy-feed gate`.
- [ ] STOP conditions: if the pinnedReadIds seeding can't preserve :1088's first-snapshot semantics cleanly, or the keepingContent interplay with applyLoadState/refresh-control forces VC state into the VM — report DONE_WITH_CONCERNS with specifics instead of forcing.

---

### Task 3: CommunityViewModel absorbs favorite/mute

**Files:**
- Modify: `Spud/Scenes/Community/Content/CommunityViewModel.swift` — pass `accountKeychainId` in (init; single construction site — find it); six sync-accessors verbatim-shape: `isMuted`, `mute(until:)`, `unmute`, `isFavorited`, `toggleFavorite` (wrapping MutedCommunityQueries/FavoritedCommunityQueries per the VC's current calls at :346-436).
- Modify: `CommunityViewController.swift` — menu builders + actions re-point; `grep "appDatabase\." CommunityViewController.swift` afterward: zero beyond DI declaration (list justified leftovers if any).
- Test: `SpudTests/CommunityViewModelTests.swift` (new) — accessor truth table + writes assert via the paired sync reads (in-memory DB).

- [ ] TDD RED -> implement -> GREEN -> SwiftFormat -> commit `refactor: CommunityViewModel owns favorite/mute accessors`.

---

### Task 4: Dedupe the local ObservationStream shim

**Files:** `PostListViewController.swift` :862-877 + :2245-2266 — the local `Self.values(of:)` + `ObservationScheduler` is a byte-duplicate of `Spud/Utils/Extensions/Observation+AsyncStream.swift` (scout-verified). Replace uses with the shared `ObservationStream.values(of:)`; delete the shim. Pure dedupe; behavior identical.

- [ ] Implement -> `make test-only ONLY=SpudTests` -> SwiftFormat -> commit `refactor: use shared ObservationStream in PostList`.

---

### Task 5: Final verify + docs + merge (controller)

- [ ] `wc -l` all four files (report the shift). Full `make test` green; full `make snapshot` 258 green (behavior-preserving — zero ref changes expected; ANY snapshot failure = investigate before touching refs).
- [ ] Docs: follow-ups spec section 1 — Landed note for the PostList/Community replication; whatever remains of section 1 (PostDetail Phase 3 mutations) stays open.
- [ ] Whole-branch review (fresh reviewer, most capable model): pipeline-order fidelity (the resolveInitialSnapshot-before-apply and paired-reset invariants), lazy-feed gate parity, keepingContent semantics, dict re-point census, ledger triage.
- [ ] Fixes -> merge --no-ff (advance/cleanliness checks; integrate main first if moved) -> byte-identical check -> push -> cleanup -> memory.
