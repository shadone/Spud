# DiasporaNodeInfo 2.0 Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spud consumes DiasporaNodeInfo 2.0.0 and surfaces live instance metadata: the `NodeInfoFetching` seam widens from a (softwareName, version) tuple to a full metadata struct (open registrations, user counts, local posts/comments), cached per-host alongside the existing software detection; the InstanceDetail screen shows the software VERSION on its badge and a live Signups value in its details card; Discover's browse-instance header shows software + signups chips. All within the existing privacy boundary: probe only on explicit engagement, never in rails/feeds; fail-open everywhere.

**Design inputs (verified, 2026-07-07 scout):**
- The pin bump 1.4.0 → 2.0.0 is a **source no-op**: the ENTIRE package API surface Spud uses lives in `SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift:13-25` (`NodeInfoManager().fetch(for:)` + `v2_1/v2_0` `.software.name/.version`); typed throws upcasts at the untyped boundary; no type renames touch Spud; platform floors (iOS 18) match Spud's deployment target exactly; the LenientInt encode-shape change is irrelevant (Spud persists its own columns, never encodes package types). Pin: `project.yml:34-36` (`exactVersion: 1.4.0` → `2.0.0`; tag 2.0.0 = 05fa35d, published). Resolve dance per repo CLAUDE.md ("Bumping LemmyKit" — identical mechanism).
- 2.0.0's 11 version-agnostic accessors are the enrichment surface: `softwareName`, `softwareVersion`, `openRegistrations: Bool`, `usersTotal/usersActiveMonth/usersActiveHalfyear: Int64?`, `localPosts/localComments: Int64?` (+homepage/repository/protocols, not surfaced in v1).
- **No new service type**: extending `NodeInfoService` reuses the existing host-keyed TTL cache, fail-open contract, timeout, and probe gating — a separate `InstanceMetadataService` would duplicate all of it. The "InstanceMetadataService" capability from the initiative memory is delivered as `NodeInfoService.metadata(host:)`.
- Existing wiring: `NodeInfoService` actor (detect → `NodeInfoDetection`), `NodeInfoCacheRecord` (`nodeInfoCache` table, v30: host PK / softwareName / softwareVersion / fetchedAt), consumers `PlatformRouter` (login/register gate) + `InstanceDetailViewController:111-118` (badge — fetches version and DISCARDS it). Discover has zero NodeInfo today. Legacy `NodeInfoRecord` + v1 `nodeInfo` table are kept-unused — DO NOT touch or reuse them.

**Architecture (binding):**
1. **Seam widening** (`NodeInfoFetching.swift`): `fetch(host:)` returns a new `FetchedNodeInfo` struct (SpudDataKit, Sendable): `softwareName: String`, `softwareVersion: String?`, `openRegistrations: Bool?`, `usersTotal: Int64?`, `usersActiveMonth: Int64?`, `usersActiveHalfyear: Int64?`, `localPosts: Int64?`, `localComments: Int64?`. `LiveNodeInfoFetcher` builds it from the 2.0 convenience accessors (collapsing the v2_1/v2_0 fallback chains — `info.softwareName` etc.; keep the empty-name throw).
2. **Cache extension**: migration `v31_nodeInfoMetadata` adds the six nullable columns to `nodeInfoCache` (openRegistrations `Bool?` as integer, five `Int64?` counts). `NodeInfoCacheRecord` gains the fields. NEVER edit v30; v31 is additive ALTERs. Existing rows keep nil metadata until re-fetched (TTL handles refresh).
3. **Service accessor**: `NodeInfoService` gains `metadata(host: String, maxAge: TimeInterval? = nil) async -> InstanceMetadata?` — same cache-first + fetch-through-seam + fail-open shape as `detect` (nil on any failure; never throws). `InstanceMetadata` is a small domain struct (software: InstanceSoftware, version: String?, openRegistrations: Bool?, usersTotal/activeMonth/activeHalfyear: Int64?, localPosts/localComments: Int64?). `detect(host:)` keeps its exact signature/behavior (PlatformRouter untouched). One probe serves both (single fetch populates the whole row).
4. **InstanceDetail surfacing**: badge text becomes "DisplayName version" when a version is known (e.g. "Lemmy 0.19.11" — it already fetches this and discards it); the details card's Signups row prefers live `openRegistrations` over the Explorer value when metadata is available (fall back to Explorer's `regMode`; no UI when both unknown). Stat grid stays Explorer-sourced (directory scale; do NOT mix live/directory numbers in one grid).
5. **Discover surfacing**: the browse-instance screen (`InstanceCommunitiesView` header path, reached by tapping an instance — engagement) gains a software+version chip and an open-signups chip fed by `metadata(host:)`, fail-open (chips absent when unknown). NO probing from the rail list itself. `DiscoverViewController`/relevant VC composes `HasNodeInfoService` — WARNING: this triggers the documented Dependencies cascade (SnapshotDependencies/FakeDependencies doubles get linker errors — build the full test plan and stub each failing double with `.unknown`/nil-returning stubs to keep snapshots byte-identical where intended).
6. **Privacy/contract invariants (unchanged):** probe only on login/register/instance-detail/instance-browse engagement; fail-open (`.unknown`/nil never blocks); detection-only (no non-Lemmy API clients); LemmyService untouched.

**Tech Stack:** DiasporaNodeInfo 2.0.0 (remote SPM pin), GRDB (v31 migration), Swift Testing, swift-snapshot-testing.

## Global Constraints

- Zero behavior change to `detect(host:)`, `PlatformRouter`, and the login/register gate — their tests stay untouched and green.
- Verify per task: `make build` + `make test-only ONLY=SpudDataKitTests` (+ `ONLY=SpudTests` when app-target files change; the Dependencies-cascade gotcha makes the full-plan build mandatory after any `Has*` composition change). Snapshot tasks additionally gate on `make snapshot` (see sequencing).
- **Sequencing with the in-flight test-hardening branch:** Tasks 1-2 are SpudDataKit-only (no snapshot surface) and run now. BEFORE starting Task 3 (UI + snapshots): `git fetch`/check whether `worktree-test-hardening` has merged to main; if yes, merge main into this branch first (its status-bar + Dynamic Type pins make new snapshot work stable); if not, coordinate with the controller. New snapshot tests for the badge/chips use `SnapshotDeterminism` pins per current house rules.
- Migration discipline: v31 is the next number — verify with `grep registerMigration AppDatabase+Migrations.swift | tail -1` before writing; test the backfill shape via the `AppDatabase.migrator` seam if the task adds column defaults.
- `mint run swiftformat <changed files>` before commits; explicit-path staging (442 cosmetic-M annex refs — never `git add -A`); conventional commits; push user-gated; no emojis. New files need `make project`.
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/nodeinfo-metadata`, branch `worktree-nodeinfo-metadata` off main 5b759634. Never touch root CLAUDE.md / SpudSnapshotTests/CLAUDE.md if the other branch's landing hasn't cleared their state (re-check dirt before merge).
- Sim courtesy: `pgrep -x xcodebuild` before test runs; sleep-60 loop (a release archive and another branch's gates share this machine).

---

### Task 1: Pin bump + accessor adoption (source no-op proof)

**Files:**
- Modify: `project.yml` (:34-36, `exactVersion: 2.0.0`), `SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift` (adopt `info.softwareName`/`info.softwareVersion` accessors, keep the empty-name throw and the tuple return FOR NOW — the seam widens in Task 2).
- Resolve: `make project && xcodebuild -resolvePackageDependencies -project Spud.xcodeproj` (transitive-refresh dance from CLAUDE.md only if resolution fails).
- Test: existing `SpudDataKitTests/NodeInfo/` suites must pass UNTOUCHED (they inject the seam, never the package — that's the proof the bump is behavior-neutral). `make build` + `make test-only ONLY=SpudDataKitTests`.

- [ ] Steps: bump + resolve → adopt accessors → build + gate → swiftformat → commit `chore: bump DiasporaNodeInfo to 2.0.0` (explicit paths: project.yml + the fetcher).

### Task 2: Seam widening + v31 cache + metadata accessor

**Files:**
- Modify: `SpudDataKit/Services/NodeInfo/NodeInfoFetching.swift` (`FetchedNodeInfo` struct + protocol return type; keep `withNodeInfoTimeout`), `LiveNodeInfoFetcher.swift` (populate all fields from 2.0 accessors), `SpudDataKit/Services/NodeInfo/NodeInfoCacheRecord.swift` (+6 fields), `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append `v31_nodeInfoMetadata`), `NodeInfoService.swift` (`metadata(host:maxAge:)` + `InstanceMetadata` domain struct in its own file `SpudDataKit/Services/NodeInfo/InstanceMetadata.swift`; single fetch populates the full cache row for both accessors).
- Test: extend `NodeInfoServiceTests` (FakeFetcher returns full struct): metadata cache-hit/stale/fail-open-nil/timeout-nil; `detect` still works from a row written by a `metadata` fetch and vice versa (one probe, one row); `NodeInfoCacheRecordTests` round-trip with the new columns; a v31 backfill test via the `AppDatabase.migrator` seam (v30 row survives with nil metadata). ALL existing NodeInfo suites (PlatformRouter/PlatformProfile/AccountServicePreflight) untouched and green.
- Every `FakeFetcher`/`NodeInfoFetching` conformance in tests updates to the struct return — grep them all.

- [ ] Steps: RED → implement → GREEN → `make build` + `make test-only ONLY=SpudDataKitTests` (+ SpudTests build for cascade safety) → swiftformat → commit `feat: NodeInfoService serves live instance metadata (v31 cache)` (explicit paths).

### Task 3: InstanceDetail surfacing (badge version + live Signups)

**PRECONDITION:** check test-hardening merge state (Global Constraints); merge main into the branch if landed.

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` — badge task (:111-118) uses `metadata(host:)`; badge text "DisplayName version" when version known (keep bare display name otherwise; hidden when unknown — current behavior); the details card Signups row (:442-448 region) prefers live `openRegistrations` (label values consistent with existing copy, e.g. "Open"/"Closed"), Explorer fallback unchanged.
- Test: snapshot — extend the existing `InstanceDetailSnapshotTests` (already uses `StubNodeInfoService`) with a stub returning known metadata → badge-with-version + live-signups variant (record light/dark refs per snapshot ceremony: one class, explicit ref staging, record+verify rerun); existing refs must stay byte-identical (stubs default `.unknown`/nil).
- STOP: if the badge/live-signups copy raises product-wording questions the existing screen doesn't answer, report options rather than inventing copy.

- [ ] Steps: RED-ish (snapshot record flow) → implement → snapshot gate (class green + suite unchanged elsewhere) → `make build` + `make test-only ONLY=SpudTests` → swiftformat → commit `feat: instance detail shows live software version and signups` (explicit paths incl. named refs).

### Task 4: Discover browse-instance chips

**Files:**
- Modify: the Discover browse-instance header path (`DiscoverViewController.swift:194` / `InstanceCommunitiesView` — locate the header composition) + `DiscoverViewModel` (metadata fetch on browse-open, engagement-gated, fail-open, `@Observable` state) + the `HasNodeInfoService` composition (CASCADE: update every affected SnapshotDependencies/FakeDependencies double; full-plan build to flush linker errors).
- Test: snapshot for the chips (stubbed metadata) in the Discover snapshot suite; VM unit test for the fetch-on-open gating (no fetch for rail rendering; one fetch per browse-open; nil metadata → no chip state).
- STOP: if `InstanceCommunitiesView` is SwiftUI and chip placement fights the existing layout, report a screenshot/description before restructuring.

- [ ] Steps: RED → implement → gates (SpudTests + SpudDataKitTests + snapshot class + suite) → swiftformat → commit `feat: Discover instance browse shows live software and signups chips` (explicit paths incl. named refs).

### Task 5: Docs + gates + review + merge

- [ ] Docs (three-tier): `docs/features/instance-software-detection.md` — extend to cover metadata (probe surface unchanged, new data points, fail-open; Status update); `docs/features/discover.md` + the instance-detail-covering page — chips/badge/signups rules + Scenarios; README capability table/by-area map if wording changed. Commit `docs: live instance metadata surfacing`.
- [ ] Final gates: `make test-only` both targets green; full `make snapshot` green (env permitting — the test-hardening branch's pins should be merged by now; otherwise the documented targeted-gate protocol); `mint run swiftformat --lint .` clean.
- [ ] Whole-branch review (fresh reviewer, most capable model): risk list = detect/metadata single-row coherence (no double-probe, no TTL fight), v31 backfill safety, fail-open preserved at every new surface, the Dependencies cascade fully propagated (no linker-breaking double missed), privacy boundary (no rail/feed probing), snapshot hygiene (only named new refs).
- [ ] ONE fix agent for findings; re-run gates.
- [ ] Merge protocol (workspace CLAUDE.md): re-check main advance + shared-checkout dirt RIGHT BEFORE merging (a release flow and another branch are active on this machine); `git annex restage` first; `--no-ff`. Push only on the user's explicit word.
