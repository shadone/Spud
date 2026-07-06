# Optimistic Subscribe (Outbox-Backed) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping Subscribe/Unsubscribe gives instant visual feedback everywhere: `LemmyService.setSubscribed` routes through the durable `OutboxService` like vote/save/hide — optimistic local write (community `subscribedState` + the `accountFollowedCommunity` junction) inside `enqueue`, background send with retry, rollback on permanent failure. The community header flips to "Pending" the moment the user taps; the Subscriptions sidebar/Communities tab and Discover react instantly via the junction.

**Root cause (verified, 2026-07-06 scout):** `LemmyService.setSubscribed` (LemmyService.swift:1426) is confirm-then-mirror — the ONLY local write happens after `api.followCommunity` returns; the header button is purely DB-observation-driven (`CommunityViewModel` :76-103 → `CommunityHeaderView.configureSubscribeButton` :356), so it cannot change until the mirror lands (1-2s+ on slow networks). Documented as deliberate in `docs/features/subscribe-unsubscribe.md:13/18/64`. Search/Discover/InstanceExplore each bolt on non-durable cell/VM-local optimism; the header has none. The house pattern (vote/save/hide via `OutboxService`, memory `spud-optimistic-mutation-outbox`) was never extended to subscribe. Rejected lighter alternatives: a header-only in-flight spinner (still waits; header stays behind the other surfaces; Subscriptions list still lags) and a non-durable optimistic mirror in `setSubscribed` (no retry; the getSite race below can wipe it mid-flight).

**Architecture (binding):** subscribe becomes a first-class outbox kind. All shapes mirror the existing vote/save machinery — read those implementations first and copy their idioms.

1. **Kind model** (`SpudDataKit/Services/Outbox/OutboxOperation.swift`): `OutboxEntityType` gains `case community`; `OutboxKind` gains `case subscribe`; `OutboxDesiredState` gains `case subscribe(Bool)` (encoded `1`/`0`). NO GRDB migration — `pendingOperation` (v17) stores `entityType`/`kind` as unconstrained `.text` and `desiredState`/`baseline` as `.integer`. Baseline for the subscribe kind encodes the PRIOR 3-valued `CommunitySubscribedState`: `0 = notSubscribed, 1 = subscribed, 2 = pending` (a subscribe-kind-specific codec next to the existing encode/decode; document the mapping).
2. **Optimistic projection** (`SpudDataKit/Services/AppDatabase/OptimisticWrites.swift` + `PendingOperationWrites.applyAbsolute` :144 dispatch): new `setCommunitySubscribed(...)` writing BOTH the `community.subscribedState` column AND the `accountFollowedCommunity` junction in the same transaction: subscribe → `subscribedState = "Pending"` + junction INSERT (Pending counts as followed — existing `syncFollowedCommunityJunction` semantics, CommunityImporter.swift:146); unsubscribe → `"NotSubscribed"` + junction DELETE. Rollback re-applies the baseline state AND the baseline's junction membership (baseline != notSubscribed → row present). "Pending" is the honest optimistic state: the server may answer Subscribed or Pending; the header already renders Pending distinctly (clock icon), and the authoritative mirror upgrades it.
3. **Reconcile guard for community** (the missing piece — posts/comments have `respectsPendingOutbox`, community does NOT): `CommunityImporter.apply(view:)`/`upsertCommunity(from:)` gain a `respectsPendingOutbox` parameter (default true) that skips writing `subscribedState`/junction for communities with a pending `subscribe` op (extend `pendingOutboxKinds` / the guard queries in `PendingOperationWrites.swift:362` to the community entity). CRITICALLY: `setFollowedCommunities` (CommunityImporter.swift:31, called from every `getSite`, LemmyService.swift:993) deletes+rewrites the WHOLE junction — it must preserve the junction membership and skip the `subscribedState` write for pending-subscribe communities in BOTH directions (an optimistic subscribe not yet in `my_user.follows` must survive; an optimistic unsubscribe still in `my_user.follows` must not be resurrected). The outbox performer's authoritative post-send mirror passes `respectsPendingOutbox: false` (mirroring `OutboxNetworkPerforming.swift:40/49`).
4. **Performer** (`SpudDataKit/Services/Outbox/OutboxNetworkPerforming.swift`): `.subscribe` × `.community` → `api.followCommunity(communityID:follow:)`, then authoritative `upsertCommunity(from: response.community_view, respectsPendingOutbox: false)` (which also syncs the junction). Failure classification reuses `OutboxFailureClass`; permanent failure → existing rollback path (`op.permanentRollback` diagnostic + the shared MainWindow permanent-failure toast — `MainWindow.swift` switches exhaustively over `OutboxKind`, so the new case REQUIRES a toast string there; discovered in Task 1, "Couldn't update subscription"). (Amended after Task 1: the original text claimed the revert was silent — wrong; the shared toast mechanism already existed for vote/save/hide.)
5. **Routing** (`LemmyService.setSubscribed` :1426): keep the signed-out `requiresAuthentication` throw, then `outbox.enqueue(OutboxOperation(entityType: .community, entityServerId: serverCommunityId, desiredState: .subscribe(subscribed)))` — mirroring `setSaved` (:1750-1772). The method stops throwing network errors (enqueue succeeds offline); callers' catch blocks remain valid for the auth throw. All four surfaces (community header, Search row, Discover, InstanceExplore) get durable optimism through their existing calls; their local optimism layers stay UNTOUCHED (gracefully redundant — simplification is a named follow-up, not this plan).
6. **UI:** no header code changes required — the observation-driven button flips to Pending instantly from the optimistic write. Sign-in gate and haptics stay VC-side (already are). Toggle-back-to-baseline coalescing comes free from `enqueueOutboxOperation`'s existing baseline-revert logic (unique key account+entity+kind).

**Tech Stack:** GRDB, actor `OutboxService`, Swift Testing (SpudDataKitTests).

## Global Constraints

- NO GRDB migration (verify: kinds/entity types are text; baseline/desiredState fit Int64).
- Zero behavior change to vote/save/hide/delete outbox paths; existing outbox tests untouched and green.
- Existing `LemmyServiceSubscribeTests` encode the OLD confirm-then-mirror contract — they are REWRITTEN (not deleted) to the new contract in Task 3; every other suite stays untouched.
- Verify per task: `make build` + `make test-only ONLY=SpudDataKitTests` (+ `ONLY=SpudTests` where app-target files change). Final gates: full `make test-only` for both + `make snapshot` 261/261 (no refs change — no rendering touched).
- `mint run swiftformat <changed files>` before each commit; explicit-path staging (442 cosmetic-M annex refs — never `git add -A`). Conventional commits; push user-gated. No emojis. New files need `make project`.
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/optimistic-subscribe`, branch `worktree-optimistic-subscribe` off main c0276307.
- The shared main checkout carries another agent's uncommitted edits to root `CLAUDE.md` and `SpudSnapshotTests/CLAUDE.md` — this branch must NOT touch either file.

---

### Task 1: Outbox kind + optimistic projection + performer

**Files:**
- Modify: `SpudDataKit/Services/Outbox/OutboxOperation.swift` (entity/kind/desired-state + subscribe baseline codec), `SpudDataKit/Services/AppDatabase/OptimisticWrites.swift` (+`setCommunitySubscribed` incl. junction both directions), `SpudDataKit/Services/AppDatabase/PendingOperationWrites.swift` (`applyAbsolute` dispatch + baseline capture for community reads current `subscribedState`), `SpudDataKit/Services/Outbox/OutboxNetworkPerforming.swift` (follow case + authoritative mirror).
- Test: extend the existing per-file suites in `SpudDataKitTests/Outbox/` following their own shapes: `OutboxOperationTests` (codec round-trips incl. all three baselines), `OptimisticWritesTests` (subscribedState + junction writes/reverts, both directions), `PendingOperationWritesTests` (enqueue captures 3-valued baseline; toggle-to-baseline deletes the row and restores state+junction), `OutboxNetworkPerformingTests` (follow call + authoritative mirror), rollback path (permanent failure restores baseline state AND junction).

**STOP:** if the Int64 `baseline`/`desiredState` columns genuinely cannot carry the subscribe encodings without schema change, stop and report (a migration is a scope change the human must approve).

- [ ] Steps: RED tests per suite → implement → GREEN → `make build` + `make test-only ONLY=SpudDataKitTests` → swiftformat → commit `feat: subscribe as a durable outbox kind with optimistic projection` (explicit paths).

### Task 2: Community reconcile guard

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/PendingOperationWrites.swift` (pending-kinds lookup extended to community), `SpudDataKit/Services/AppDatabase/Importers/CommunityImporter.swift` (`apply(view:)`/`upsertCommunity` gain `respectsPendingOutbox` defaulting true; `setFollowedCommunities` preserves pending-subscribe communities' junction membership and `subscribedState` in BOTH directions), callers threading the flag (performer passes false; grep every `upsertCommunity(from:` caller and keep their current semantics — feed/getPost/getSite imports respect the guard).
- Test: `ReconciliationGuardTests`-style additions: (a) a `CommunityView` import does NOT clobber a pending optimistic subscribe; (b) `setFollowedCommunities` with the community ABSENT from follows keeps the optimistic junction row + Pending state; (c) with an optimistic UNSUBSCRIBE and the community still IN follows, neither the junction row nor subscribedState is resurrected; (d) `respectsPendingOutbox: false` (the performer's mirror) DOES write through.

**STOP:** if threading `respectsPendingOutbox` through `setFollowedCommunities` forces restructuring its delete+rewrite into per-row logic with visible perf implications for large follow lists, report the shape before building it.

- [ ] Steps: RED → implement → GREEN (incl. existing importer tests untouched) → `make build` + `make test-only ONLY=SpudDataKitTests` → swiftformat → commit `feat: community imports respect pending optimistic subscribes` (explicit paths).

### Task 3: Route setSubscribed through the outbox + contract tests

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (:1426 — keep the signed-out throw; enqueue instead of direct call+mirror; delete `mirrorCommunityInfoToAppDatabase` if now unused, keep if shared).
- Test: REWRITE `SpudDataKitTests/LemmyServiceSubscribeTests.swift` to the new contract, mirroring `LemmyServiceOutboxDelegationTests` (:44)'s shape: (a) `setSubscribed(true)` applies Pending + junction row synchronously even when the network transport fails (the optimistic guarantee); (b) after the drain's successful send, the server's returned state (Subscribed) replaces Pending (authoritative mirror); (c) unsubscribe removes junction/state optimistically; (d) signed-out still throws and skips the API + writes nothing.

- [ ] Steps: RED (rewritten contract fails on old code — verify by test order or on a scratch revert) → implement → GREEN → `make build` + `make test-only ONLY=SpudDataKitTests` + `make test-only ONLY=SpudTests` (app-target unaffected but the plan's cascade gotcha says verify) → swiftformat → commit `feat: optimistic durable subscribe via the outbox` (explicit paths).

### Task 4: Docs + gates + review + merge

- [ ] Docs (the current docs explicitly document confirm-then-mirror as the design — rewrite, don't append): `docs/features/subscribe-unsubscribe.md` (:13/:18/:19/:20/:21/:64 — new model: optimistic Pending everywhere via the durable outbox, retry/rollback semantics, the getSite guard; the Search/Discover local-optimism notes become "additionally keep cell-local feedback"); `docs/features/community-screen.md` (:20, :48-49 scenario — button flips to Pending instantly); `docs/features/subscriptions-sidebar.md` (:57-59 scenario now genuinely instant); `docs/features/drafts-and-outbox.md` (the mutation outbox's kind list gains subscribe); `docs/features/discover.md` if it contrasts with the header's old behavior. README capability table/by-area map only if wording became inaccurate. Commit `docs: subscribe is optimistic and durable everywhere`.
- [ ] Gates: full `make test-only ONLY=SpudDataKitTests` + `ONLY=SpudTests` green; `make snapshot` 261/261; `mint run swiftformat --lint .` clean.
- [ ] Whole-branch review (fresh reviewer, most capable model): risk list = junction/state consistency under every path (optimistic, rollback, authoritative mirror, getSite reconcile both directions), baseline codec round-trip, no vote/save/hide regression, the rewritten subscribe tests actually pin the OPTIMISTIC guarantee (would fail on confirm-then-mirror), toggle-coalescing behavior, docs accuracy (no overclaim about failure UX — rollback is silent + diagnostic).
- [ ] ONE fix agent for findings; re-run gates.
- [ ] Merge protocol (workspace CLAUDE.md): re-check `main..worktree-optimistic-subscribe` + shared-checkout dirt overlap RIGHT BEFORE merging; `git annex restage` first; `--no-ff`. Push only on the user's explicit word.

## Named follow-ups (not this plan)

- Simplify Search/Discover/InstanceExplore's now-redundant local optimism layers onto pure DB observation.
- Discover's `CommunitySubscriptionState` has no Pending case (collapses to subscribed) — cosmetic alignment.
(follow-up removed after Task 1: the shared MainWindow toast already surfaces permanent-failure rollbacks for all kinds, now incl. subscribe)
