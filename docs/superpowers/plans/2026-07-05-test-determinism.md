# Test-Determinism Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kill the two remaining cross-test contamination channels: (1) `PreferencesService` reading the host app's persisted `UserDefaults.standard` in test fixtures (latent in 9 snapshot files + worked-around in 5 unit suites), and (2) the legacy signed-out UITest suites running against a dirty App Group DB (reverse contamination from signed-in suites).

**Architecture:** `UserDefaultsBacked` already accepts `storage: UserDefaults` — the gap is only that `PreferencesService`'s ~30 `@UserDefaultsBacked` declarations use the `.standard` default. Add `PreferencesService.init(storage:)` constructing the wrappers explicitly (`_prop = .init(wrappedValue:key:storage:)` in init — per-instance DI, zero global state); fixtures use ephemeral `UserDefaults(suiteName:)` suites. Retrofit `SPUDWipeAppDatabase` onto the two legacy UITest suites.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing (unit), XCTest + swift-snapshot-testing (snapshots, git-annex refs), XCTest + SBTUITestTunnel (UITests).

## Global Constraints

- Zero behavior change for the production path: `PreferencesService()` must remain exactly equivalent to today (storage `.standard`, same keys, same defaults, same `*Stream` semantics).
- Verify line anchors by content (they were measured at branch base 8194f960).
- After adding/removing files: `make project`. SwiftFormat changed paths BEFORE final verify. Stage explicit paths. `git branch --show-current` must print `worktree-test-determinism` before each commit.
- Snapshot refs are git-annex; the re-record ceremony in `SpudSnapshotTests/CLAUDE.md` is authoritative (one class at a time; record run then verify run; never restage in between; `git add` only explicit ref paths).
- Single-booted-sim rule; reference iPhone id via `scripts/resolve-test-destination.sh`; iPad = `iPad Pro 11-inch (M5)` on iOS 26.3 (the M4/iOS-18.5 sim is a dud — dyld-crashes this app); restore the reference iPhone after any iPad run.
- Test commands: `make test-only ONLY=<target>`; full snapshot plan `make snapshot`.

---

### Task 1: `PreferencesService.init(storage:)` (TDD)

**Files:**
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (~line 173: `class PreferencesService: PreferencesServiceType`; ~30 `@UserDefaultsBacked(key:)` declarations from ~line 174 onward)
- Test: `SpudTests/PreferencesServiceStorageIsolationTests.swift` (new)

**Interfaces:**
- Produces: `init(storage: UserDefaults)` + `convenience init()` delegating with `.standard`. Every `@UserDefaultsBacked` property keeps its EXACT key string and default value; the attribute arguments move into explicit `_prop = UserDefaultsBacked(wrappedValue: <same default>, key: "<same key>", storage: storage)` assignments in `init(storage:)` (declarations become bare `@UserDefaultsBacked var prop: T`). Optional-typed properties use the `ExpressibleByNilLiteral` init (`UserDefaultsBacked(key:storage:)` — check the wrapper's two inits at `SpudUtilKit/UserDefaultsBacked.swift:41,101`).
- CRITICAL FIDELITY RULE: build a key/default inventory table (report it): for each of the ~30 properties record (property, key string, default value) BEFORE the change and assert the AFTER state matches item-for-item. A silently changed key or default is a user-data regression.

- [ ] **Step 1: Write the failing tests** (`PreferencesServiceStorageIsolationTests.swift`, Swift Testing, `@MainActor`):

```swift
// Test 1: injectedStores_areIsolated
//   let a = PreferencesService(storage: UserDefaults(suiteName: "test-\(UUID())")!)
//   let b = PreferencesService(storage: UserDefaults(suiteName: "test-\(UUID())")!)
//   a.showVoteButtons = false
//   #expect(b.showVoteButtons == true)          // default, not a's write
//   #expect(a.thumbnailPosition == .left)        // untouched props read defaults
// Test 2: injectedStore_neverTouchesStandard
//   snapshot UserDefaults.standard.dictionaryRepresentation() key count for the app's pref keys
//   (or register a sentinel: assert standard has no "showVoteButtons" delta after mutating the injected service)
//   mutate several props on an injected-store service; assert .standard unchanged for those keys
// Test 3: defaultInit_readsStandard (equivalence guard)
//   PreferencesService() must still read/write .standard — write via one instance, read via another
//   default-init instance; RESTORE the touched key in a defer (this test deliberately touches
//   .standard — keep it to ONE key and defer-restore it, following the QuickSwitchViewModelTests pattern)
```

RED: compile failure (`init(storage:)` doesn't exist).

- [ ] **Step 2:** `make project && make test-only ONLY=SpudTests/PreferencesServiceStorageIsolationTests` — capture RED.
- [ ] **Step 3: Implement** `init(storage:)` per the Interfaces contract. Inventory table first, then mechanical conversion. Keep property ORDER and doc comments on the declarations.
- [ ] **Step 4: GREEN** — the new suite; then FULL `make test-only ONLY=SpudTests` (373 baseline) and `make test-only ONLY=SpudDataKitTests` (663 baseline — AppearanceService/PostListAppearance consumers must be unaffected). Any existing test breaking = fidelity violation; fix the inventory, not the test.
- [ ] **Step 5:** SwiftFormat + commit `feat: injectable UserDefaults store for PreferencesService`.

---

### Task 2: Migrate test fixtures to ephemeral stores

**Files:**
- Modify (snapshot fixtures — the 9 leaky files; enumerate with `grep -ln "PreferencesService()" SpudSnapshotTests/*.swift`, expect ~10 incl. the already-pinned `PostListPostCellSnapshotTests`):
  every bare `PreferencesService()` in `SpudSnapshotTests/` becomes `PreferencesService(storage: UserDefaults(suiteName: "snapshot-\(UUID().uuidString)")!)` (or a tiny shared helper `SnapshotPreferences.ephemeral()` in an existing snapshot-support file — one helper, not per-file copies).
- Modify (unit suites currently using the defer-restore + `.serialized` workaround): `SpudTests/QuickSwitchViewModelTests.swift`, `SpudTests/OfflineDownloadOptionsViewModelTests.swift`, `SpudTests/PostDetailConfigViewModelTests.swift`, `SpudTests/PostDetailAppearanceTextScaleTests.swift`, and `SpudTests/LinkInstancePreferenceTests.swift` (check each actually mutates prefs first) — switch to injected ephemeral stores and REMOVE the now-redundant defer-restores (keep `.serialized` only if the suite has another reason; say which in the report).
- Keep in `PostListPostCellSnapshotTests`: replace the two explicit pins with the ephemeral store + a one-line comment pointing at this plan (the pins were the interim fix; ephemeral defaults render identically because `.left`/`true` ARE the defaults).

**Verification:**
- [ ] **Step 1:** Migrate; `make project`; run `make test-only ONLY=SpudTests` (must stay green with the defer-restores GONE — that proves the isolation works where the old workaround was load-bearing).
- [ ] **Step 2:** FULL snapshot plan on the reference iPhone: `make snapshot`. Expected 250/250. If ANY test fails: diagnose per the taxonomy — a ref recorded under dirty defaults will now mismatch a clean-default render. For each such ref: confirm the visual delta is preference-gated (thumbnail/vote-buttons/density class of difference), then re-record THAT class's failing refs via the annex ceremony and list them in the report. Do NOT re-record anything that fails for a different-looking reason — STOP and report instead.
- [ ] **Step 3:** SwiftFormat + commit(s): `test: ephemeral UserDefaults stores in snapshot + unit fixtures` (+ a separate `test: re-record <refs> under clean-default prefs` commit if Step 2 required re-records, exact ref paths only).

---

### Task 3: Wipe-arg retrofit on the legacy signed-out UITest suites

**Files:**
- Modify: `SpudUITests/SpudUITests.swift` (~line 24: launch options) and `SpudUITests/IPadSplitUITests.swift` (~line 30) — add `AppLaunchArgument.wipeAppDatabase.rawValue` alongside the signed-out seed.
- Modify: root `CLAUDE.md` (the "Three test-only UITest launch arguments" bullet ~line 248: replace the reverse-contamination hazard sentence with "all suites now pass the wipe arg — seeds are order-independent in both directions") and `docs/superpowers/specs/2026-07-05-follow-ups.md` section 2 (mark the reverse-contamination open item landed).

**Why safe:** the wipe erases the App Group DB at launch; the signed-out seed then always runs. These suites already tolerate any DB state; after the wipe they get a deterministic empty one. The one behavior to watch: any test in these suites that relied on state persisted by an EARLIER test in the SAME suite across relaunches (read the suites — each test launches once in setUp, no cross-test persistence expectations found in prior reviews, but verify).

**Verification (device protocol):**
- [ ] **Step 1:** Add the arg to both suites; read both files for cross-test persistence assumptions (report findings).
- [ ] **Step 2:** iPhone: run the FULL `SpudUITests` class + `SignedInVoteUITests` + `WrapperNavbarUITests`-equivalents in one plan run on the booted reference iPhone: `xcodebuild ... -only-testing:SpudUITests -destination "$(scripts/resolve-test-destination.sh)" ...` (the whole UITest target on iPhone; iPad-only classes self-skip). Evidence: all executed, 0 failures.
- [ ] **Step 3:** iPad: shutdown iPhone → run `-only-testing:SpudUITests/IPadSplitUITests -only-testing:SpudUITests/IPadActivitySplitUITests` on the M5 iPad by id → BOTH classes green (this also re-proves order-independence in both directions on iPad) → shutdown iPad, boot reference iPhone. Restore even on failure.
- [ ] **Step 4:** SwiftFormat (if Swift changed) + commit `test: wipe App Group DB in legacy signed-out UITest suites` + docs commit or same commit (docs are two small edits — one commit `test: ...` including docs is fine here).

---

### Task 4: Final verify + merge

- [ ] **Step 1:** `mint run swiftformat --lint .` clean; full `make test` green (report per-target counts vs baselines 373/663/133/7/116 + UITests).
- [ ] **Step 2:** Whole-branch review (fresh reviewer, most capable model): fidelity table spot-check (keys/defaults), fixture-migration completeness (zero bare `PreferencesService()` left in test targets — grep), wipe-arg wiring, docs accuracy, ledger Minor triage.
- [ ] **Step 3:** Fix findings (one fixer), re-verify affected, then merge --no-ff into main (re-check main advance + main-checkout cleanliness first — other agents are active; merge main INTO the branch first if it moved), verify byte-identical, push is user-gated (report the count).
