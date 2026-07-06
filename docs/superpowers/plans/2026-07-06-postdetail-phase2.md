# PostDetail VC-to-VM Migration Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PostDetailViewModel` owns the data layer — the three GRDB observation loops (header, comments, outbound), the visit recording, and the sync-read accessors — making them unit-testable against an in-memory DB; the VC becomes a renderer reacting to published VM state. Plus a PostDetail header-vote e2e.

**Architecture (binding):** **VM publishes; VC reacts.** Each loop moves as: VM owns the `Task` consuming the AsyncStream and publishes plain `@Observable` state; the VC runs its own `ObservationStream.values(of:)` reaction loop doing the VIEW work (snapshot building, prewarming, scrolling, menu rebuilds). View code NEVER moves into the `@Observable`. Because `orderedComments` is deliberately `@ObservationIgnored` (collapse recompute must not invalidate views), the comments pipeline gets a published `commentsRevision: Int` bumped once per emit — the VC's reaction key. Template: the existing `startLoadingObservation` pattern (VC reacting to `viewModel.commentsLoadingState`) and `PersonViewModel`'s loop ownership.

**Tech Stack:** Swift 6 strict concurrency, @Observable VMs, GRDB AsyncStream observations (`.async(onQueue: .global(qos: .userInitiated))` inside the observation helpers — already handled there), Swift Testing with `AppDatabase.inMemory()`.

## Global Constraints

- ZERO user-visible behavior change. The per-emit view pipeline (order of: rebuild lookup dicts -> updateOrderedComments -> prewarm -> applySnapshot -> attemptPermalinkScroll -> one-shot didPrepareObservation) must execute in the SAME order with the SAME gating as today, just driven by the VC reaction loop instead of inline in the observation loop.
- `PostDetailViewModel` gains `HasAppDatabase`-style access via init injection (match how PersonViewModel takes `appDatabase` — read it), NOT via a dependencies accessor on the VM.
- `setPost` (VC ~line 84) swaps the VM for iPad detail reuse: the OLD VM's observation tasks must die with it (VM owns them -> cancel in a `stopObservations()`/deinit-safe way), the NEW VM starts fresh, and the VC's REACTION loops restart against the new VM (they currently restart via `startObservations()` — preserve that call shape). The stale-outbound-splice reset comment at the setPost site is a live constraint: state that moved to the VM resets naturally with the new VM; state remaining on the VC (pending dicts, reveal sets) keeps its existing reset lines.
- The preference/reachability observation tasks (viewDidLoad-scoped, read the CURRENT viewModel live at fire time) stay on the VC untouched.
- Line anchors: verified at branch base 4fa85564 — `startObservations` VC:607, header loop VC:638, `startCommentObservation` VC:662(called)/~710(def), `recordVisit` VC:671, `startOutboundObservation`/`startLoadingObservation` defs below; verify by content.
- After adding files: `make project`. SwiftFormat changed paths BEFORE final verify. Stage explicit paths. Branch check (`worktree-postdetail-vm-phase2`) before commits. Never cd into the shared main checkout.
- Per-task verify: `make build` + `make test-only ONLY=SpudTests` (391 baseline — check the actual count on the first run and use it). Full `make test` + `make snapshot` (258) at the final task. Mass snapshot failures => stale-app guard first.
- TDD for every VM behavior move: the DB-backed VM test lands RED-first where feasible (new VM API), or as a characterization test written BEFORE the move (assert against the OLD behavior through the NEW seam immediately after).

## DB-backed VM test harness (Task 1 establishes it; later tasks extend)

`SpudTests/PostDetailViewModelObservationTests.swift`: `@MainActor` Swift Testing suite; per-test `AppDatabase.inMemory()`; seed via the same record APIs the importers/tests use (find precedents: `AppDatabaseTests` seeding, snapshot fixtures' seeding helpers); construct the VM with the in-memory DB + an `AccountScope` from a locally-built AccountService (precedent: `PostDetailViewModelFetchTests` builds AccountService with in-memory DB); `viewModel.startObservations()`; then await the published state with a bounded poll: `for _ in 0..<200 { if predicate() { break }; await Task.yield() }` + `#expect(predicate())` (no wall-clock sleeps; if yield-polling proves insufficient for the queue-hop, a short `Task.sleep` bounded loop is acceptable — note it).

---

### Task 1: Header observation + recordVisit move (+ harness)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewModel.swift` — add `appDatabase` init param; add published `headerRow: PostDetailHeaderRow?`; add `startObservations()` / `stopObservations()`; move the header loop (consume `appDatabase.observePostDetailHeader(postRowId:)`, publish each emit); move the bring-up: `postRowIdSync` gate, `recordVisit` (the `lastOpenedAtSync`/`accountPersonServerIdSync`/`postInteractionSnapshotSync` reads that today populate `previousVisitAt`/`currentAccountPersonId` + the fire-and-forget `recordPostOpened`).
- Modify: `PostDetailViewController.swift` — delete the moved code; `startObservations()` (VC) now calls `viewModel.startObservations()` then starts a VC REACTION loop: `ObservationStream.values(of: { viewModel.headerRow })` driving the EXACT current per-emit view work (reevaluate unavailability, header privacy, overflow-menu rebuild, prewarm, applySnapshot) in the current order. `setPost` keeps working (old VM's tasks die; new VM + new reaction loops).
- Re-point `headerRow` readers: the VC field `headerRow` is deleted; ~20 read sites across the main file + sibling files become `viewModel.headerRow`. The `// internal: shared with ... +Content` marker for `headerRow` goes away with the field.
- Modify: VM init call sites (VC init + `setPost`) to pass `appDatabase`.
- Test: `SpudTests/PostDetailViewModelObservationTests.swift` (new — the harness): (a) seeded post -> after `startObservations()`, `headerRow` publishes non-nil with the seeded title; (b) `recordVisit` behavior: `previousVisitAt` reflects a pre-seeded `lastOpenedAt`, and a `postInteraction` row exists/updates after start (assert via the same sync read).

**STOP conditions:** if the header loop's per-emit view work can't be reproduced order-faithfully from a reaction loop (e.g. something depends on running BEFORE the VM publishes), report DONE_WITH_CONCERNS with the specific ordering hazard instead of restructuring.

- [ ] Steps: read current code paths (VC 607-700 region + VM + PersonViewModel template) -> write the harness + RED tests -> move -> re-point -> GREEN (new tests + full SpudTests) -> `make build` -> SwiftFormat -> commit `refactor: PostDetailViewModel owns the header observation and visit recording`.

---

### Task 2: Comments observation move + revision signal

**Files:**
- Modify: `PostDetailViewModel.swift` — move the comments loop (`observePostDetailComments(postRowId:sortType:)`): per emit, VM calls its own `updateOrderedComments(rows)` then bumps published `commentsRevision: Int` (starts 0; document WHY the revision exists — `orderedComments` is `@ObservationIgnored` by design). Sort-type changes: find how the current loop restarts on sort change (the VC restarts `startCommentObservation` — mirror: VM restarts its comments task; the VC's sort-change call site becomes `viewModel.restartComments(sortType:)` or equivalent matching current semantics).
- Modify: `PostDetailViewController.swift` — delete the loop; the VC reaction loop keys on `commentsRevision` and performs the CURRENT per-emit pipeline in order: rebuild `commentRowsByElementId` (from `viewModel.orderedComments` — verify the dict is built from rows the VM now holds; the rows array must be readable by the VC: expose `orderedComments` read-only as today), prewarm, `applySnapshot`, `attemptPermalinkScroll`, one-shot `didPrepareObservation`/`hasReceivedFirstCommentSnapshot` gating (that flag's home follows its users — if only the VC pipeline reads it, it stays on the VC).
- Test: extend the harness: seed post + comments -> start -> revision increments and `orderedComments` contains the seeded tree in order; seed an additional comment row mid-test (DB write) -> revision bumps again and the new comment appears. Also: collapse toggling does NOT bump the revision (guards the @ObservationIgnored intent).

**STOP:** the collapse/jump/permalink machine reads live tableView geometry — it stays VC-side; if any of it turns out to write into the VM's comment state in a way that would recurse the revision, report before hacking around it.

- [ ] Steps: RED tests -> move -> GREEN (incl. `PostDetailViewModelExpandAncestorsTests`/`NewCommentTests`/`CommentsSectionItemsTests` untouched and green) -> build -> SwiftFormat -> commit `refactor: PostDetailViewModel owns the comments observation with a revision signal`.

---

### Task 3: Outbound observation + remaining accessors

**Files:**
- Modify: `PostDetailViewModel.swift` — move the outbound loop (`observeOutboundComments(postServerId:accountKeychainId:)`), publishing `pendingOutboundComments: [OutboundContentRecord]` (today a VC field — delete there; `mergedCommentItems`/`applySnapshot` read `viewModel.pendingOutboundComments`). Add VM methods for the remaining direct appDatabase uses: `muteCommunity(communityActorId:until:)` (wraps `muteCommunitySync`; +OverflowMenu's `muteCommunity` calls it), `instanceActorId` (wraps `accountInstanceActorIdSync`; user-activity + share-URL sites), `isOwnContent(creatorPersonId:)` (wraps `accountOwnPersonIdsSync`; +Content's `isOwnContent` delegates or moves wholesale — keep the public VC-facing shape working for the sibling files), and the explorer lookup used by link handling (`explorerInstanceSync` — wrap as `isKnownInstance(host:)`-style or leave for the link seam; decide by reading the call sites and report).
- Modify: VC + sibling files re-points. After this task: `grep -n "appDatabase\." PostDetailViewController*.swift` should show ZERO hits outside the dependencies accessor declaration — if any legitimately must remain (e.g. InternalLinkRouting's `linkRouterAppDatabase` conformance), list them in the report with why.
- Test: harness extension: seed an outbound row -> published; write another -> updates. Unit tests for `isOwnContent` truth table + `muteCommunity` writes the row (assert via sync read).

- [ ] Steps: RED -> move -> GREEN -> build -> SwiftFormat -> commit `refactor: PostDetailViewModel owns outbound observation and data accessors`.

---

### Task 4: PostDetail header-vote e2e

**Files:**
- Create: `SpudUITests/PostDetailVoteUITests.swift` — mirror `SignedInVoteUITests` (launch args: staticImageService + wipeAppDatabase + seedSignedInDefaultAccount; catch-all 500 first; feed + post-detail + comments stubs reusing the existing fixtures from `SpudUITests.swift`): open the first post into PostDetail, tap the HEADER upvote, assert the optimistic score/state change via the header's accessibility contract (read `PostDetailHeaderCell`'s vote-accessibility surface first) and that no sign-in gate appears.
- Run on the booted reference iPhone; evidence: executed 1, 0 failures (0-executed = fixture crash).

- [ ] Steps: read prior art + header accessibility -> write -> run green -> SwiftFormat -> commit `test: PostDetail header-vote e2e via the signed-in seed`.

---

### Task 5: Final verify + docs + merge

- [ ] `wc -l` VC + VM (report the shift; expect VC ~<2,000 and VM growing accordingly).
- [ ] Full `make test` green; full `make snapshot` 258 green (stale-app guard on mass failure); `mint run swiftformat --lint .` clean.
- [ ] Docs: follow-ups spec section 1 — extend the Landed note: Phase 2 landed (loops + accessors + e2e); remaining: lemmyService mutation moves (Phase 3, optional) and the PostList/Community equivalents.
- [ ] Whole-branch review (fresh reviewer, most capable model): reaction-loop order fidelity vs the old inline pipelines (the #1 risk), setPost swap semantics, revision-signal invalidation scope, appDatabase-zero grep, harness quality; ledger triage.
- [ ] Fix findings -> merge --no-ff into main (re-check main advance + main-checkout state; temp-worktree pattern if main is free) -> byte-identical check -> cleanup -> report (push is user-gated).
