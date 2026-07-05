# Signed-In UITest Seam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `seedSignedInDefaultAccount` launch argument so XCUITests can drive auth-gated flows — proven by un-skipping the iPad Activity split test and adding one signed-in vote e2e.

**Architecture:** Mirror the existing signed-out seed exactly: a synchronous, DEBUG-gated `AccountService` method invoked from `MainWindow.init` before the account-presence gate. Seed the account's Person row directly (never stub the giant `GetSiteResponse`/`my_user` — one missing required field decode-fails silently). Write a fake JWT through the private credential store under a FIXED keychainId so repeated runs overwrite instead of accumulating keychain entries on the shared sim.

**Tech Stack:** Swift 6 strict concurrency (Spud + SpudDataKit), GRDB sync writes, Swift Testing (unit), XCTest + SBTUITestTunnel (UITests, Swift 5).

## Global Constraints

- Zero release-build surface: the new AccountService method and the MainWindow hook are `#if DEBUG`-gated (consistent with `SBTUITestTunnelServer.takeOff()`).
- The seed must be SYNCHRONOUS — it runs in `MainWindow.init` before the gate at `accountService.currentDefaultAccountKeychainId()` (`MainWindow.swift` ~line 120); an async seed falls into onboarding. Use the existing sync importer helpers (`ensureSignedOutAccountKeychainId` precedent, `setDefaultAccountSync`).
- Instance: `https://discuss.tchncs.de` (reuses every existing feed/detail stub).
- SBT conventions: catch-all `SBTRequestMatch(url: ".*")` → 500 registered FIRST; first query param matcher has NO leading `&`; `SBTStubResponse(fileNamed:)` NSAsserts on a missing fixture → the class reports "Executed 0 tests" (that is a fixture crash, not a pass).
- Line anchors below were verified on this branch's base; re-verify by content.
- After adding files: `make project`. SwiftFormat changed paths BEFORE final verify. Stage explicit paths. Verify `git branch --show-current` == `worktree-signed-in-seam` before each commit.
- Unit tests: `make test-only ONLY=SpudDataKitTests`. iPhone UITests: booted-sim destination via `scripts/resolve-test-destination.sh`. iPad UITests: see Task 3's device protocol.

---

### Task 1: `AccountService.seedSignedInDefaultAccount` (+ unit tests, TDD)

**Files:**
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (new method near `signInAsSignedOut`, ~line 369; protocol `AccountServiceType` gets the requirement `#if DEBUG`-gated or the method stays concrete-only — match how `signInAsSignedOut` is exposed and pick the minimal surface; if the protocol is the only way MainWindow reaches it, add it to the protocol behind `#if DEBUG`)
- Maybe modify: `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` (only if a sync helper for "ensure signed-IN account + person" is needed; mirror `ensureSignedOutAccountKeychainId`, ~line 445)
- Test: `SpudDataKitTests/AccountServiceSeedSignedInTests.swift` (new)

**Interfaces:**
- Produces: `func seedSignedInDefaultAccount(atInstance instance: InstanceActorId)` (DEBUG-only). Behavior contract:
  1. No-ops if a default account already exists (same guard shape as the signed-out seed's caller).
  2. In ONE synchronous transaction: ensure instance+site rows; insert a `PersonRecord` for the seeded user (`name: "uitester"`, local to the instance — copy the field shape from `SpudSnapshotTests/AccountScreenSnapshotTests.seedSignedInAccount`, ~lines 95-127, the prior art); insert the account with `isSignedOutAccountType: false`, `isServiceAccount: false`, `personId` = the person's id, under the FIXED `keychainId: "uitest-signed-in-default"`; set it default (`setDefaultAccountSync`).
  3. Writes `LemmyCredential(jwt: "fake-jwt")` via the private `credentialStore` (`writeCredential`, ~line 691) — AccountService owns it, keep it encapsulated.
- Consumed by: Task 2's MainWindow hook.

- [ ] **Step 1: Write the failing tests** (`AccountServiceSeedSignedInTests.swift`, Swift Testing, in-memory `AppDatabase`, injected in-memory `CredentialStore` — the store protocol is injectable per `AccountService.swift` ~lines 706-714):

```swift
// Suite: @MainActor struct AccountServiceSeedSignedInTests (fresh in-memory DB per test)
// Test 1: seed_createsSignedInDefaultAccount
//   seedSignedInDefaultAccount(atInstance:) then assert:
//   - accountService.currentDefaultAccountKeychainId() == "uitest-signed-in-default"
//   - accountService.isSignedOut(forAccountKeychainId: that id) == false
//   - the account row's personId is non-nil and resolves to a person row
// Test 2: seed_writesFakeJwtCredential
//   assert the injected credential store holds jwt == "fake-jwt" under the fixed keychainId
// Test 3: seed_isIdempotent_whenDefaultAccountExists
//   call signInAsSignedOut(atInstance:) first (existing API), then seedSignedInDefaultAccount;
//   assert the default account is STILL the signed-out one (seed no-ops; guard contract)
//   NOTE: if the no-op guard ends up living in the MainWindow caller instead of the service,
//   move this assertion accordingly and document the placement in the report.
```

Write real Swift (the sketch above is the behavior contract — build assertions on the actual query APIs, e.g. `accountRowSync`/GRDB reads used by neighboring tests). RED = compile failure or assertion failure before implementation.

- [ ] **Step 2: Run to verify RED** — `make project && make test-only ONLY=SpudDataKitTests/AccountServiceSeedSignedInTests`, capture the failure.
- [ ] **Step 3: Implement** the method per the Interfaces contract. Sync DB writes only (mirror `ensureSignedOutAccountKeychainId`'s transaction style). `#if DEBUG` around the whole method (and its protocol requirement if added).
- [ ] **Step 4: GREEN** — the new suite passes; then full `make test-only ONLY=SpudDataKitTests` (baseline from this branch's base must hold; report the count).
- [ ] **Step 5: SwiftFormat + commit** — `feat: DEBUG seed for a signed-in default account (fixed keychainId, fake JWT)`.

---

### Task 2: Launch argument + MainWindow hook

**Files:**
- Modify: `Spud/App/AppLaunchArgument.swift` (~line 9: add `case seedSignedInDefaultAccount = "SPUDSeedSignedInDefaultAccount"`)
- Modify: `Spud/Scenes/MainWindow/MainWindow.swift` (~lines 98, 162-170: alongside `seedDefaultAccountForUITestsIfRequested`)

**Interfaces:**
- Consumes: Task 1's `seedSignedInDefaultAccount(atInstance:)`.
- Produces: launching the app with `SPUDSeedSignedInDefaultAccount` yields a signed-in default account on `discuss.tchncs.de` before tab construction.

- [ ] **Step 1:** Add the enum case; add a `#if DEBUG` `seedSignedInDefaultAccountForUITestsIfRequested()` next to the existing seed method, same guards (`ProcessInfo` argument present + `currentDefaultAccountKeychainId() == nil`), calling the Task 1 API; call it in `MainWindow.init` immediately after the signed-out seed call. Mutually exclusive by the shared `currentDefaultAccountKeychainId() == nil` guard — if BOTH args are passed, signed-out (first) wins; add a one-line comment saying so.
- [ ] **Step 2: Build + quick behavioral smoke** — `make build` succeeds. No unit test target covers MainWindow; the behavioral proof is Task 3/4's UITests.
- [ ] **Step 3: SwiftFormat + commit** — `feat: SPUDSeedSignedInDefaultAccount launch argument + MainWindow hook`.

---

### Task 3: Un-skip the iPad Activity split test

**Files:**
- Modify: `SpudUITests/IPadSplitUITests.swift` (~lines 263-283: remove the `XCTSkip` and wire the seam)

**Device protocol (single-sim rule):** `xcrun simctl list devices | grep Booted` → if the iPhone is booted, `xcrun simctl shutdown <iphone-id>`; boot nothing manually — pass `-destination 'platform=iOS Simulator,id=7CB112F6-AF00-4784-A3CD-AD203B9CF70F'` (iPad Pro 11-inch (M4)) and let xcodebuild boot it. AFTER the task: `xcrun simctl shutdown 7CB112F6-AF00-4784-A3CD-AD203B9CF70F && xcrun simctl boot A4302525-034D-4A95-AB2B-F8D5DA9C54EF` (restore the reference iPhone — other agents rely on it being the booted sim).

- [ ] **Step 1:** Read the skipped test + its docstring and the class's existing launch/setUp pattern. Add `AppLaunchArgument.seedSignedInDefaultAccount.rawValue` to that TEST's launch arguments (check how the class passes per-test vs class-wide args — the signed-out arg is class-wide; the signed-in test needs the signed-in arg INSTEAD, so per-test launch configuration may be required; follow whatever mechanism the class already uses for per-test variation, or relaunch the app inside the test with different arguments — `app.launchArguments` then `app.launch()` inside the test is acceptable in XCUITest).
- [ ] **Step 2:** Replace the `throw XCTSkip(...)` with the real flow per its docstring: navigate Account tab → Activity row → assert the two-column split geometry (mirror the geometry assertions of the sibling `test_communityFromDiscover...` tests). The Activity timeline may be empty (local data) — assert structure, not content.
- [ ] **Step 3:** Run ONLY this test on the iPad sim per the device protocol. Evidence required: "Executed 1 test, with 0 failures" (0-executed = fixture/arg crash — fix, don't shrug). If the assertion reveals the split needs content to lay out (empty-state collapses the split), report DONE_WITH_CONCERNS with the actual rendered hierarchy rather than forcing assertions.
- [ ] **Step 4:** Restore the reference iPhone sim per the device protocol. Then SwiftFormat + commit — `test: un-skip iPad Activity split test via signed-in seed`.

---

### Task 4: Signed-in vote e2e (iPhone)

**Files:**
- Create: `SpudUITests/SignedInVoteUITests.swift`

**Why vote:** simplest signed-in flow; exercises the seam + the optimistic outbox UI end-to-end (the vote applies locally and instantly; the network send is background-retried, so the catch-all 500 stub cannot destabilize the UI).

- [ ] **Step 1:** New XCTest class following `SpudUITests.swift`'s setUp shape, but launch with `seedSignedInDefaultAccount` (NOT the signed-out arg) + `staticImageService`; register the catch-all 500 stub FIRST, then the existing `post-list-all-hot.json` feed stub (reuse the fixture; check the exact match pattern from `SpudUITests.swift` and copy it).
- [ ] **Step 2:** The test: wait for the first post cell; perform the upvote interaction — read `PostListPostContentView`/cell accessibility to find the tappable vote affordance (vote buttons render because clean defaults show them; the snapshot-fixture work confirmed `showVoteButtons` default = true). Assert the optimistic state change (score increment or upvote-selected accessibility value — read the cell's accessibility contract first and assert what it actually exposes). No sign-in gate must appear (that's the seam proof: the same tap while signed out presents the gate).
- [ ] **Step 3:** Run on the booted reference iPhone (`scripts/resolve-test-destination.sh`). Evidence: executed 1, 0 failures.
- [ ] **Step 4:** SwiftFormat + commit — `test: signed-in vote e2e via the new seed (optimistic UI, no gate)`.

---

### Task 5: Docs + final verify

- [ ] **Step 1:** `docs/superpowers/specs/2026-07-05-follow-ups.md` section 2: add a short "Landed (2026-07-05):" note — the seam + the two tests; remaining scope (login/compose/inbox e2e, verification-debt burn-down) stays open.
- [ ] **Step 2:** Root `CLAUDE.md`: in the UITest-related Tooling quirks area, ONE line documenting both seeds (`SPUDSeedSignedOutDefaultAccount` / `SPUDSeedSignedInDefaultAccount` — signed-in seeds person+fake-JWT, fixed keychainId, DEBUG-only).
- [ ] **Step 3:** Full unit plan (`make test`) green; the two new/changed UITests already proven in Tasks 3-4 (do NOT re-run the full UITest suite on iPad).
- [ ] **Step 4:** Commit docs — `docs: signed-in UITest seam notes`; then whole-branch review (fresh reviewer, most capable model), fix findings, merge `--no-ff` to main via a temp worktree on main (main checkout is on another agent's branch — do not touch it).
