# Ephemeral Browse Accounts + Persisted Scheduler Give-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the scheduler from perpetually re-fetching site info for instances the user only browsed (e.g. aussie.zone 403 spam) by tagging internally-created browse accounts as ephemeral, and make the scheduler permanently give up on any site after repeated permanent failures with state that survives relaunch.

**Architecture:** Add an `isEphemeral` provenance flag to `account` and persisted give-up state (`siteInfoConsecutivePermanentFailures`, `siteInfoNextAttemptAt`) to `site` (migration v29 + backfill). Auto-created browse accounts are flagged ephemeral and excluded from the recurring signed-out sweep; they instead get one best-effort on-demand `getSite` when opened. Both site-info sweeps gate on the persisted give-up state; the scheduler records failures and emits a `site.giveUp` diagnostic at the threshold. Successful imports reset the give-up state, so a user visit self-heals an abandoned site.

**Tech Stack:** Swift 6 / SpudDataKit, GRDB (SQLite), Swift Testing, XcodeGen.

## Global Constraints

- Swift 6.0 language mode + complete strict concurrency across SpudDataKit and its test target. Keep new types/params `Sendable`.
- Tests are **Swift Testing** (`import Testing`, `struct` suites, `@Test`, `#expect`/`#require`). `import Testing` does NOT re-export Foundation — add `import Foundation` for `Date`/`URL`. Suites touching a shared fixed-path DB need `@Suite(.serialized)`; per-test `AppDatabase.inMemory()` is already isolated.
- No emojis in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`refactor:`/`test:`/`docs:`).
- Migrations are append-only. Name the new one `v29_ephemeralAccountAndSiteGiveUp` (latest is `v28_postUnavailable`). Never edit an existing migration.
- The give-up threshold constant is **N = 5** consecutive permanent failures. The transient short-retry interval is **5 minutes**.
- Run SpudDataKit tests via the booted sim, by id, to avoid contention:
  `BOOTED=$(xcrun simctl list devices | grep Booted | head -1 | grep -oE '[0-9A-F-]{36}')`
  `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination "platform=iOS Simulator,id=$BOOTED" -skipPackagePluginValidation -skipMacroValidation test`
  (fall back to `-destination 'platform=iOS Simulator,name=iPhone 17'` if none booted). Swift Testing prints `✔ Test run with N tests ... passed` (not the XCTest "Executed N" line).
- Run `mint run swiftformat <changed files>` BEFORE the final test verify of each task, never after. `.swiftformat` has `--enable isEmpty`: don't introduce `x.count == 0` (it rewrites to `.isEmpty`, breaking types without it).
- No source files are added that need XcodeGen unless you create a NEW file; if you add a new `.swift` file, run `make project` before building. All files below already exist except where a step says "Create".
- Work on branch `feat/ephemeral-browse-accounts` in the worktree `/Users/denis/dev/info.ddenis/Spud/Spud-ephemeral`. Verify `git branch --show-current` before each commit. Do NOT touch `.remember/remember.md`.

---

### Task 1: Data model — record fields + migration v29

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Records/Account.swift` (add `isEphemeral`)
- Modify: `SpudDataKit/Services/AppDatabase/Records/Site.swift` (add give-up columns)
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append `v29`)
- Test: `SpudDataKitTests/EphemeralAccountMigrationTests.swift` (Create)

**Interfaces:**
- Produces: `AccountRecord.isEphemeral: Bool`; `SiteRecord.siteInfoConsecutivePermanentFailures: Int`, `SiteRecord.siteInfoNextAttemptAt: Date?`. Migration id `"v29_ephemeralAccountAndSiteGiveUp"`.

- [ ] **Step 1: Add the record fields.**

In `Records/Account.swift`, add a stored property after `isSignedOutAccountType`:
```swift
    public var isEphemeral: Bool
```
Add the matching init parameter (after `isSignedOutAccountType: Bool = false,`):
```swift
        isEphemeral: Bool = false,
```
and the assignment (after `self.isSignedOutAccountType = isSignedOutAccountType`):
```swift
        self.isEphemeral = isEphemeral
```

In `Records/Site.swift`, add after `infoUpdatedDate`:
```swift
    /// Consecutive permanent (4xx) site-info fetch failures. Drives the
    /// scheduler give-up: at `AppDatabase.siteInfoGiveUpThreshold` the site is
    /// dropped from the recurring site-info sweeps. Reset to 0 on any success.
    public var siteInfoConsecutivePermanentFailures: Int
    /// Persisted back-off deadline (the site is not swept before this instant).
    /// Nil means immediately eligible. Survives relaunch (unlike the old
    /// in-memory `SchedulerBackoff`).
    public var siteInfoNextAttemptAt: Date?
```
Add init params (after `infoUpdatedDate: Date? = nil,`):
```swift
        siteInfoConsecutivePermanentFailures: Int = 0,
        siteInfoNextAttemptAt: Date? = nil,
```
and assignments (after `self.infoUpdatedDate = infoUpdatedDate`):
```swift
        self.siteInfoConsecutivePermanentFailures = siteInfoConsecutivePermanentFailures
        self.siteInfoNextAttemptAt = siteInfoNextAttemptAt
```

- [ ] **Step 2: Append migration v29.**

At the end of the migration registrations in `AppDatabase+Migrations.swift` (after `v28_postUnavailable`), add:
```swift
        migrator.registerMigration("v29_ephemeralAccountAndSiteGiveUp") { db in
            // Provenance flag: accounts auto-created solely to browse a remote
            // instance are ephemeral and excluded from the recurring site-info
            // sweep (see SchedulerQueries / AccountImporter.bestAccountKeychainId).
            try db.alter(table: "account") { t in
                t.add(column: "isEphemeral", .boolean).notNull().defaults(to: false)
            }
            // Persisted scheduler give-up state (replaces the in-memory back-off
            // for the two site-info sweeps).
            try db.alter(table: "site") { t in
                t.add(column: "siteInfoConsecutivePermanentFailures", .integer).notNull().defaults(to: 0)
                t.add(column: "siteInfoNextAttemptAt", .double)
            }
            // Backfill: existing non-default, non-service, signed-out accounts are
            // browse accounts (the only path that creates them is
            // bestAccountKeychainId's auto-create; the bootstrap/default account is
            // isDefault=1). Flag them so the fix applies to current data.
            try db.execute(sql: """
                UPDATE account
                SET isEphemeral = 1
                WHERE isSignedOutAccountType = 1
                  AND isDefault = 0
                  AND isServiceAccount = 0
            """)
        }
```

- [ ] **Step 3: Write the failing tests.**

Create `SpudDataKitTests/EphemeralAccountMigrationTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct EphemeralAccountMigrationTests {
    /// After all migrations, the new columns exist and round-trip with defaults.
    @Test
    func newColumnsRoundTrip() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: "https://example.com", createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!)
            try site.insert(db)
            var account = AccountRecord(
                siteId: site.id!,
                accountKeychainId: "k1",
                isSignedOutAccountType: true,
                isEphemeral: true
            )
            try account.insert(db)
        }
        let reread = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == "k1").fetchOne(db)
        }
        #expect(reread?.isEphemeral == true)
    }

    /// The v29 backfill flags a legacy (pre-v29) non-default signed-out account
    /// ephemeral, and leaves the default account untouched.
    @Test
    func backfillFlagsLegacyBrowseAccounts() async throws {
        // Build a raw queue and migrate only up to v28, insert legacy rows, then
        // migrate to v29 and assert the backfill result.
        let dbQueue = try DatabaseQueue()
        let migrator = AppDatabase.makeMigrator()   // see Step 4 note on the seam
        try migrator.migrate(dbQueue, upTo: "v28_postUnavailable")
        try dbQueue.write { db in
            try db.execute(sql: "INSERT INTO instance (actorId, createdAt, updatedAt) VALUES ('https://a.example', 0, 0)")
            let instanceId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO site (instanceId, createdAt, updatedAt) VALUES (?, 0, 0)", arguments: [instanceId])
            let siteId = db.lastInsertedRowID
            // legacy browse account (non-default signed-out) -> should become ephemeral
            try db.execute(sql: "INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt) VALUES (?, 'browse', 0, 0, 1, 0, 0)", arguments: [siteId])
            // default signed-out account -> should stay non-ephemeral
            try db.execute(sql: "INSERT INTO account (siteId, accountKeychainId, isDefault, isServiceAccount, isSignedOutAccountType, createdAt, updatedAt) VALUES (?, 'default', 1, 0, 1, 0, 0)", arguments: [siteId])
        }
        try migrator.migrate(dbQueue)   // apply v29
        try dbQueue.read { db in
            let browse = try Int.fetchOne(db, sql: "SELECT isEphemeral FROM account WHERE accountKeychainId = 'browse'")
            let def = try Int.fetchOne(db, sql: "SELECT isEphemeral FROM account WHERE accountKeychainId = 'default'")
            #expect(browse == 1)
            #expect(def == 0)
        }
    }
}
```

- [ ] **Step 4: Expose the migrator to tests if not already accessible.**

The backfill test needs to migrate up to a specific version. Check how `AppDatabase` builds its `DatabaseMigrator` (a private `migrator` computed property or a `migrate(_:)` call inside `init`). If there is no test-accessible way to get the `DatabaseMigrator`, refactor the registration into a `static func makeMigrator() -> DatabaseMigrator` (or `internal var migrator`) that both `init` and the test use — a pure refactor, no behavior change. Name it `AppDatabase.makeMigrator()` to match the test above (adjust the test if you pick a different accessible seam). If a seam already exists, use it and update the test call site.

- [ ] **Step 5: Run tests to verify they fail, then pass.**

Run the SpudDataKitTests command from Global Constraints with `-only-testing:SpudDataKitTests/EphemeralAccountMigrationTests`. Expect FAIL first (missing columns / seam), then implement Steps 1–4 and re-run: expect `✔ Test run ... passed`.

- [ ] **Step 6: SwiftFormat + commit.**

```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/Records/Account.swift SpudDataKit/Services/AppDatabase/Records/Site.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/EphemeralAccountMigrationTests.swift
git add SpudDataKit/Services/AppDatabase/Records/Account.swift SpudDataKit/Services/AppDatabase/Records/Site.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/EphemeralAccountMigrationTests.swift
git commit -m "feat: add isEphemeral + persisted site give-up columns (v29 migration)"
```

---

### Task 2: Tag auto-created browse accounts ephemeral

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift` (`bestAccountKeychainId`)
- Test: `SpudDataKitTests/BestAccountKeychainIdEphemeralTests.swift` (Create)

**Interfaces:**
- Consumes: `AccountRecord.isEphemeral` (Task 1).
- Produces: `bestAccountKeychainId(forInstance:)` now inserts auto-created accounts with `isEphemeral = true`.

- [ ] **Step 1: Write the failing test.**

Create `SpudDataKitTests/BestAccountKeychainIdEphemeralTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct BestAccountKeychainIdEphemeralTests {
    @Test
    func autoCreatedBrowseAccountIsEphemeral() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let instance = try #require(InstanceActorId(from: "https://aussie.zone"))
        let keychainId = try appDatabase.bestAccountKeychainId(forInstance: instance)
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == keychainId).fetchOne(db)
        }
        #expect(account?.isEphemeral == true)
        #expect(account?.isSignedOutAccountType == true)
    }

    @Test
    func existingDefaultAccountIsReusedAndNotFlagged() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let instance = try #require(InstanceActorId(from: "https://lemmy.world"))
        // Seed a default signed-out account for the site.
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: instance.actorId, createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!)
            try site.insert(db)
            var acct = AccountRecord(siteId: site.id!, accountKeychainId: "default", isDefault: true, isSignedOutAccountType: true)
            try acct.insert(db)
        }
        let keychainId = try appDatabase.bestAccountKeychainId(forInstance: instance)
        #expect(keychainId == "default")
        let account = try await appDatabase.writer.read { db in
            try AccountRecord.filter(Column("accountKeychainId") == "default").fetchOne(db)
        }
        #expect(account?.isEphemeral == false)
    }
}
```

- [ ] **Step 2: Run to verify failure.** `-only-testing:SpudDataKitTests/BestAccountKeychainIdEphemeralTests` → `autoCreatedBrowseAccountIsEphemeral` FAILS (`isEphemeral` is false).

- [ ] **Step 3: Implement.** In `bestAccountKeychainId`, set `isEphemeral: true` on the auto-created record (the reuse branches are untouched):
```swift
            var record = AccountRecord(
                siteId: siteId,
                accountKeychainId: UUID().uuidString,
                isServiceAccount: false,
                isSignedOutAccountType: true,
                isEphemeral: true,
                createdAt: now,
                updatedAt: now
            )
```

- [ ] **Step 4: Run to verify pass.** Both tests pass.

- [ ] **Step 5: SwiftFormat + commit.**
```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift SpudDataKitTests/BestAccountKeychainIdEphemeralTests.swift
git add SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift SpudDataKitTests/BestAccountKeychainIdEphemeralTests.swift
git commit -m "feat: flag auto-created browse accounts isEphemeral"
```

---

### Task 3: Persisted give-up — record helpers + success reset

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/SiteInfoGiveUpQueries.swift`
- Modify: `SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift` (reset on success)
- Test: `SpudDataKitTests/SiteInfoGiveUpTests.swift` (Create)

**Interfaces:**
- Consumes: `SiteRecord` give-up columns (Task 1); `SchedulerBackoff.backoffDelay(failureCount:)`.
- Produces:
  - `AppDatabase.siteInfoGiveUpThreshold: Int` (== 5)
  - `AppDatabase.siteInfoTransientRetryInterval: TimeInterval` (== 300)
  - `func recordSiteInfoPermanentFailure(siteId: Int64, now: Date) throws -> Int` (returns new consecutive-permanent-failure count)
  - `func recordSiteInfoTransientFailure(siteId: Int64, now: Date) throws`
  - `func resetSiteInfoGiveUpSync(siteId: Int64, db: Database) throws` (used by SiteImporter success path)

- [ ] **Step 1: Write the failing tests.**

Create `SpudDataKitTests/SiteInfoGiveUpTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct SiteInfoGiveUpTests {
    private func seedSite(_ appDatabase: AppDatabase) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://x.example", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!)
            try site.insert(db)
            return site.id!
        }
    }

    private func site(_ appDatabase: AppDatabase, _ id: Int64) async throws -> SiteRecord {
        try await appDatabase.writer.read { db in try #require(SiteRecord.fetchOne(db, key: id)) }
    }

    @Test
    func permanentFailureIncrementsAndSchedulesBackoff() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        let now = Date(timeIntervalSince1970: 1000)
        let count = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: now)
        #expect(count == 1)
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 1)
        let expected = now.addingTimeInterval(SchedulerBackoff.backoffDelay(failureCount: 1))
        #expect(s.siteInfoNextAttemptAt == expected)
    }

    @Test
    func transientFailureLeavesCountAndSchedulesShortRetry() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        _ = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 5000)
        try appDatabase.recordSiteInfoTransientFailure(siteId: siteId, now: now)
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 1, "transient must not increment the permanent count")
        #expect(s.siteInfoNextAttemptAt == now.addingTimeInterval(300))
    }

    @Test
    func successResetsGiveUpState() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let siteId = try await seedSite(appDatabase)
        _ = try appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: Date(timeIntervalSince1970: 0))
        try await appDatabase.writer.write { db in
            try appDatabase.resetSiteInfoGiveUpSync(siteId: siteId, db: db)
        }
        let s = try await site(appDatabase, siteId)
        #expect(s.siteInfoConsecutivePermanentFailures == 0)
        #expect(s.siteInfoNextAttemptAt == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure.** Compilation fails (methods missing).

- [ ] **Step 3: Implement the helpers.**

Create `SpudDataKit/Services/AppDatabase/SiteInfoGiveUpQueries.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// Consecutive permanent (4xx) site-info failures after which the scheduler
    /// permanently stops sweeping a site. A user-initiated on-demand fetch can
    /// still succeed and reset the state (see AccountService).
    static let siteInfoGiveUpThreshold = 5

    /// Back-off applied after a transient (5xx / timeout / offline) site-info
    /// failure. Kept short because transient failures should retry soon.
    static let siteInfoTransientRetryInterval: TimeInterval = 5 * 60

    /// Record a permanent site-info failure: increment the consecutive-permanent
    /// counter and push the back-off deadline out. Returns the new count so the
    /// caller can emit `site.giveUp` when it first reaches the threshold.
    func recordSiteInfoPermanentFailure(siteId: Int64, now: Date) throws -> Int {
        try writer.write { db in
            guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return 0 }
            site.siteInfoConsecutivePermanentFailures += 1
            let delay = SchedulerBackoff.backoffDelay(failureCount: site.siteInfoConsecutivePermanentFailures)
            site.siteInfoNextAttemptAt = now.addingTimeInterval(delay)
            site.updatedAt = now
            try site.update(db)
            return site.siteInfoConsecutivePermanentFailures
        }
    }

    /// Record a transient site-info failure: leave the permanent counter (so a
    /// flaky instance is never abandoned) and schedule a short retry.
    func recordSiteInfoTransientFailure(siteId: Int64, now: Date) throws {
        try writer.write { db in
            guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return }
            site.siteInfoNextAttemptAt = now.addingTimeInterval(Self.siteInfoTransientRetryInterval)
            site.updatedAt = now
            try site.update(db)
        }
    }

    /// Clear all give-up state for a site (called on any successful site-info
    /// import, so a user visit self-heals an abandoned site).
    func resetSiteInfoGiveUpSync(siteId: Int64, db: Database) throws {
        guard var site = try SiteRecord.fetchOne(db, key: siteId) else { return }
        guard site.siteInfoConsecutivePermanentFailures != 0 || site.siteInfoNextAttemptAt != nil else { return }
        site.siteInfoConsecutivePermanentFailures = 0
        site.siteInfoNextAttemptAt = nil
        try site.update(db)
    }
}
```

- [ ] **Step 4: Reset on successful import.**

In `SiteImporter.swift`, in the static field-mapping `apply(_ view:to:record:now:)` (the method that sets `record.name = view.site.name` around line 152), after the mapping resets give-up in-memory on the record being written:
```swift
        // A successful site-info import clears any scheduler give-up state, so a
        // previously-abandoned instance resumes background refresh and a user
        // visit that succeeds self-heals it.
        record.siteInfoConsecutivePermanentFailures = 0
        record.siteInfoNextAttemptAt = nil
```
(The record is `update`d by the caller, so setting the fields on the in-memory record suffices — do NOT also call `resetSiteInfoGiveUpSync` here to avoid a double write. `resetSiteInfoGiveUpSync` exists for any success path that does not go through this mapping; verify whether both `apply` and `upsertSite` funnel through this static mapper and, if `upsertSite` builds its record separately, apply the same two lines there.)

- [ ] **Step 5: Run to verify pass.** All three tests pass.

- [ ] **Step 6: SwiftFormat + commit.**
```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/SiteInfoGiveUpQueries.swift SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift SpudDataKitTests/SiteInfoGiveUpTests.swift
make project   # a new source file was added
git add SpudDataKit/Services/AppDatabase/SiteInfoGiveUpQueries.swift SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift SpudDataKitTests/SiteInfoGiveUpTests.swift
git commit -m "feat: persisted site-info give-up record helpers + reset on import"
```

---

### Task 4: Give-up gating + ephemeral exclusion in the sweeps

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/SchedulerQueries.swift`
- Test: `SpudDataKitTests/SiteInfoSweepGatingTests.swift` (Create)

**Interfaces:**
- Consumes: give-up columns + `AppDatabase.siteInfoGiveUpThreshold` (Tasks 1, 3); `AccountRecord.isEphemeral` (Task 1).
- Produces (replacing the old signatures):
  - `func signedOutAccountsAwaitingSiteInfo(now: Date) async throws -> [(keychainId: String, siteId: Int64)]`
  - `func ownerlessSitesAwaitingInfo(now: Date) async throws -> [(actorId: InstanceActorId, siteId: Int64)]`

- [ ] **Step 1: Write the failing tests.**

Create `SpudDataKitTests/SiteInfoSweepGatingTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct SiteInfoSweepGatingTests {
    private func makeSite(_ appDatabase: AppDatabase, host: String, failures: Int = 0, nextAttemptAt: Date? = nil) async throws -> Int64 {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://\(host)", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(
                instanceId: inst.id!,
                siteInfoConsecutivePermanentFailures: failures,
                siteInfoNextAttemptAt: nextAttemptAt
            )
            try site.insert(db)
            return site.id!
        }
    }

    private func addSignedOut(_ appDatabase: AppDatabase, siteId: Int64, keychainId: String, isEphemeral: Bool) async throws {
        try await appDatabase.writer.write { db in
            var acct = AccountRecord(siteId: siteId, accountKeychainId: keychainId, isSignedOutAccountType: true, isEphemeral: isEphemeral)
            try acct.insert(db)
        }
    }

    @Test
    func ephemeralAccountsAreExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s1 = try await makeSite(appDatabase, host: "wanted.example")
        try await addSignedOut(appDatabase, siteId: s1, keychainId: "wanted", isEphemeral: false)
        let s2 = try await makeSite(appDatabase, host: "browse.example")
        try await addSignedOut(appDatabase, siteId: s2, keychainId: "browse", isEphemeral: true)
        let rows = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10_000))
        #expect(rows.map(\.keychainId) == ["wanted"])
        #expect(rows.first?.siteId == s1)
    }

    @Test
    func abandonedSitesAreExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s = try await makeSite(appDatabase, host: "waf.example", failures: AppDatabase.siteInfoGiveUpThreshold)
        try await addSignedOut(appDatabase, siteId: s, keychainId: "waf", isEphemeral: false)
        let rows = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10_000))
        #expect(rows.isEmpty)
    }

    @Test
    func backoffNotYetElapsedIsExcluded() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let future = Date(timeIntervalSince1970: 20_000)
        let s = try await makeSite(appDatabase, host: "slow.example", failures: 1, nextAttemptAt: future)
        try await addSignedOut(appDatabase, siteId: s, keychainId: "slow", isEphemeral: false)
        let early = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 10_000))
        #expect(early.isEmpty)
        let late = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: Date(timeIntervalSince1970: 30_000))
        #expect(late.map(\.keychainId) == ["slow"])
    }

    @Test
    func ownerlessSiteGatingAndSiteId() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let s = try await makeSite(appDatabase, host: "ownerless.example")
        let rows = try await appDatabase.ownerlessSitesAwaitingInfo(now: Date(timeIntervalSince1970: 10_000))
        #expect(rows.count == 1)
        #expect(rows.first?.siteId == s)
        #expect(rows.first?.actorId.actorId == "https://ownerless.example")
    }
}
```

- [ ] **Step 2: Run to verify failure** (signature mismatch / new args).

- [ ] **Step 3: Implement the gated queries.** Replace the two methods in `SchedulerQueries.swift`. The give-up predicate is shared; `now` is passed as a Unix timestamp for the `siteInfoNextAttemptAt` comparison (GRDB stores `Date` as epoch double).
```swift
    func signedOutAccountsAwaitingSiteInfo(now: Date) async throws -> [(keychainId: String, siteId: Int64)] {
        let nowTs = now.timeIntervalSince1970
        return try await writer.read { db in
            try Row.fetchAll(db, sql: """
                    SELECT account.accountKeychainId AS keychainId, site.id AS siteId
                    FROM account
                    JOIN site ON site.id = account.siteId
                    WHERE account.isSignedOutAccountType = 1
                      AND account.isEphemeral = 0
                      AND site.name IS NULL
                      AND site.siteInfoConsecutivePermanentFailures < \(AppDatabase.siteInfoGiveUpThreshold)
                      AND (site.siteInfoNextAttemptAt IS NULL OR site.siteInfoNextAttemptAt <= ?)
                """, arguments: [nowTs])
                .map { (keychainId: $0["keychainId"], siteId: $0["siteId"]) }
        }
    }

    func ownerlessSitesAwaitingInfo(now: Date) async throws -> [(actorId: InstanceActorId, siteId: Int64)] {
        let nowTs = now.timeIntervalSince1970
        let rows = try await writer.read { db in
            try Row.fetchAll(db, sql: """
                    SELECT instance.actorId AS actorId, site.id AS siteId
                    FROM site
                    JOIN instance ON instance.id = site.instanceId
                    WHERE site.name IS NULL
                      AND NOT EXISTS (SELECT 1 FROM account WHERE account.siteId = site.id)
                      AND site.siteInfoConsecutivePermanentFailures < \(AppDatabase.siteInfoGiveUpThreshold)
                      AND (site.siteInfoNextAttemptAt IS NULL OR site.siteInfoNextAttemptAt <= ?)
                """, arguments: [nowTs])
        }
        return rows.compactMap { row in
            let raw: String = row["actorId"]
            guard let actorId = InstanceActorId(from: raw) else {
                logger.error("Skipping unparseable instance actor id: \(raw, privacy: .public)")
                return nil
            }
            return (actorId: actorId, siteId: row["siteId"])
        }
    }
```
Interpolating `AppDatabase.siteInfoGiveUpThreshold` (an Int constant) into the SQL is safe (not user input). Verify `Date` is persisted as `timeIntervalSince1970` in this codebase (GRDB's default) so the `<= ?` comparison is correct; the Task 3 tests already assume this.

- [ ] **Step 4: Run to verify pass.** All four tests pass.

- [ ] **Step 5: SwiftFormat + commit.**
```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/SchedulerQueries.swift SpudDataKitTests/SiteInfoSweepGatingTests.swift
git add SpudDataKit/Services/AppDatabase/SchedulerQueries.swift SpudDataKitTests/SiteInfoSweepGatingTests.swift
git commit -m "feat: gate site-info sweeps on ephemeral flag + persisted give-up"
```

---

### Task 5: Scheduler wiring — persisted recording + site.giveUp diagnostic

**Files:**
- Modify: `SpudDataKit/Services/Scheduler/SchedulerService.swift`
- Test: `SpudDataKitTests/SchedulerServiceGiveUpTests.swift` (Create)

**Interfaces:**
- Consumes: `signedOutAccountsAwaitingSiteInfo(now:)`, `ownerlessSitesAwaitingInfo(now:)` (Task 4); `recordSiteInfoPermanentFailure(siteId:now:) -> Int`, `recordSiteInfoTransientFailure(siteId:now:)`, `AppDatabase.siteInfoGiveUpThreshold` (Task 3); the existing `OutboxFailureClass` classifier (see `RequestRetry.swift` for its use).
- Produces: signed-out + ownerless sweeps record persisted give-up state and emit a `site.giveUp` diagnostic (category `.site`, level `.notice`) at the threshold. Signed-in sweeps keep the in-memory `SchedulerBackoff` unchanged.

- [ ] **Step 1: Study the existing scheduler test harness.** Read `SpudDataKitTests/SchedulerServiceBackoffTests.swift` to reuse its fakes (fake `AccountServiceType`, `AlertServiceType`, `ReachabilityMonitoring`, injected `now`, and a `LemmyService`/`fetchSiteInfo` stub that can throw a chosen error) and the way it drives `service.tick()`. Reuse `DiagnosticLogSpy` from `SpudDataKitTests/Helpers/DiagnosticLogSpy.swift`.

- [ ] **Step 2: Write the failing tests.**

Create `SpudDataKitTests/SchedulerServiceGiveUpTests.swift`. Mirror `SchedulerServiceBackoffTests`'s setup; the assertions to add:
```swift
    // A signed-out account whose getSite throws a permanent 403 on every tick is
    // abandoned after siteInfoGiveUpThreshold ticks: it stops being attempted and
    // a site.giveUp diagnostic is recorded exactly once.
    @Test
    func permanentFailuresAbandonSiteAndRecordGiveUp() async throws {
        // Arrange: seed a non-ephemeral signed-out account whose instance always
        // returns a permanent (403) error via the fake lemmy service. Inject a
        // stepping clock so back-off windows elapse between ticks.
        // Act: drive `tick()` siteInfoGiveUpThreshold + 2 times, stepping `now`
        // past each back-off window.
        // Assert:
        #expect(diagnostics.events(matching: "site.giveUp").count == 1)
        // After abandonment the sweep no longer returns the account, so the fake
        // service records no further fetch attempts.
        #expect(fakeLemmy.fetchSiteInfoCallCount <= AppDatabase.siteInfoGiveUpThreshold)
    }

    // Transient (503) failures never abandon: the account keeps being attempted.
    @Test
    func transientFailuresNeverAbandon() async throws {
        // Same shape, but the fake throws a transient (503) error; drive many
        // ticks stepping past the 5-minute transient window each time.
        #expect(diagnostics.events(matching: "site.giveUp").isEmpty)
        let s = try await appDatabase.writer.read { db in try SiteRecord.fetchOne(db, key: siteId) }
        #expect(s?.siteInfoConsecutivePermanentFailures == 0)
    }
```
Fill in the arrange/act bodies using the harness from `SchedulerServiceBackoffTests`. Use a fake `fetchSiteInfo` that throws `LemmyServiceError.apiError(.unknownServerError(403, ...))` for the permanent case and `503` for the transient case (match how `SchedulerServiceBackoffTests` / `GetSiteDiagnosticsTests` build errors — reuse the exact error-construction they use so `OutboxFailureClass.classify` sees the right status).

- [ ] **Step 3: Run to verify failure.**

- [ ] **Step 4: Implement the scheduler wiring.**

Change `fetchSiteInfo(forAccountKeychainId:)` to surface the outcome instead of a bare Bool, so callers can classify permanence. Add a private result type:
```swift
    private enum SiteInfoOutcome {
        case success
        case permanentFailure
        case transientFailure
    }
```
Rework the per-account fetch to return it (keep the existing `alertService.handle` + `site.fetchFailed` behavior — that diagnostic is emitted inside `LemmyService.fetchSiteInfo`, unchanged):
```swift
    private func fetchSiteInfoOutcome(forAccountKeychainId keychainId: String) async -> SiteInfoOutcome {
        let instance = accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort
        await diagnostics.record(category: .scheduler, level: .debug, event: "account.fetch",
                                 message: "Fetching site info for account", instance: instance, metadata: nil)
        do {
            try await accountService.lemmyService(forAccountKeychainId: keychainId).fetchSiteInfo()
            return .success
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
            // Classify with the shared OutboxFailureClass (as RequestRetry does):
            // a 4xx is permanent (drives give-up); 5xx / timeout / offline is transient.
            return OutboxFailureClass.classify(error, isOnline: true) == .permanent
                ? .permanentFailure : .transientFailure
        }
    }
```
Verify the exact `OutboxFailureClass` case name (`.permanent` vs another) against `OutboxFailureClass.swift`; adjust the comparison to match.

Add a helper that records the persisted result for a site and emits `site.giveUp` at the threshold:
```swift
    private func recordSiteInfoResult(_ outcome: SiteInfoOutcome, siteId: Int64, instance: String?) async {
        switch outcome {
        case .success:
            // Give-up reset happens in SiteImporter on the successful import; nothing to do here.
            break
        case .transientFailure:
            try? appDatabase.recordSiteInfoTransientFailure(siteId: siteId, now: now())
        case .permanentFailure:
            let count = (try? appDatabase.recordSiteInfoPermanentFailure(siteId: siteId, now: now())) ?? 0
            if count == AppDatabase.siteInfoGiveUpThreshold {
                await diagnostics.record(
                    category: .site, level: .notice, event: "site.giveUp",
                    message: "Stopped fetching site info after repeated permanent failures",
                    instance: instance,
                    metadata: ["failureCount": String(count)]
                )
            }
        }
    }
```
Rewrite `fetchSiteInfoForSignedOutIfNeeded()` to use the gated query (which now returns `siteId`) and record persisted results (no in-memory `gatedFetchSiteInfo` for these — the query gate replaces it):
```swift
    private func fetchSiteInfoForSignedOutIfNeeded() async {
        let signedOut: [(keychainId: String, siteId: Int64)]
        do { signedOut = try await appDatabase.signedOutAccountsAwaitingSiteInfo(now: now()) }
        catch { logger.error("Failed to query signed-out accounts awaiting site info: \(String(describing: error), privacy: .public)"); signedOut = [] }
        for row in signedOut {
            let instance = accountService.instanceActorId(forAccountKeychainId: row.keychainId)?.hostWithPort
            let outcome = await fetchSiteInfoOutcome(forAccountKeychainId: row.keychainId)
            await recordSiteInfoResult(outcome, siteId: row.siteId, instance: instance)
        }

        let ownerless: [(actorId: InstanceActorId, siteId: Int64)]
        do { ownerless = try await appDatabase.ownerlessSitesAwaitingInfo(now: now()) }
        catch { logger.error("Failed to query ownerless sites: \(String(describing: error), privacy: .public)"); ownerless = [] }
        for row in ownerless {
            let keychainId = accountService.accountForSignedOut(forInstance: row.actorId, isServiceAccount: true)
            let outcome = await fetchSiteInfoOutcome(forAccountKeychainId: keychainId)
            await recordSiteInfoResult(outcome, siteId: row.siteId, instance: row.actorId.hostWithPort)
        }
    }
```
Keep `fetchSiteInfoAndMyUserInfoForSignedInIfNeeded()` and its `gatedFetchSiteInfo`/in-memory `backoff` exactly as-is (signed-in is out of scope). If `gatedFetchSiteInfo` / the old `fetchSiteInfo(forInstance:)` / the Bool `fetchSiteInfo(forAccountKeychainId:)` become unused after this, delete them; if signed-in still uses `gatedFetchSiteInfo` + `fetchSiteInfo(forAccountKeychainId:) -> Bool`, keep a thin Bool wrapper for it (`outcome == .success`).

- [ ] **Step 5: Run to verify pass.** Both new tests pass; existing `SchedulerServiceBackoffTests` and `GetSiteDiagnosticsTests` still pass (run `-only-testing:SpudDataKitTests` for the whole target).

- [ ] **Step 6: SwiftFormat + commit.**
```bash
mint run swiftformat SpudDataKit/Services/Scheduler/SchedulerService.swift SpudDataKitTests/SchedulerServiceGiveUpTests.swift
git add SpudDataKit/Services/Scheduler/SchedulerService.swift SpudDataKitTests/SchedulerServiceGiveUpTests.swift
git commit -m "feat: scheduler records persisted site give-up + emits site.giveUp"
```

---

### Task 6: On-demand best-effort site fetch for ephemeral instances

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/OnDemandSiteInfoQueries.swift` (the sync decision query)
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (add `refreshSiteInfoOnDemandIfNeeded`)
- Modify: `Spud/App/AppCoordinator.swift` (invoke on browse navigation)
- Test: `SpudDataKitTests/OnDemandSiteInfoTests.swift` (Create)

**Interfaces:**
- Consumes: `AccountRecord.isEphemeral`, `SiteRecord.name` (Task 1).
- Produces:
  - `func shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: String) -> Bool` (ephemeral account whose site.name is nil)
  - `AccountService.refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId:)` (fire-and-forget, best-effort, no retry)

- [ ] **Step 1: Write the failing test (the decision query — the fire-and-forget wiring is build-verified).**

Create `SpudDataKitTests/OnDemandSiteInfoTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import Testing
@testable import SpudDataKit

@Suite
struct OnDemandSiteInfoTests {
    private func seed(_ appDatabase: AppDatabase, keychainId: String, isEphemeral: Bool, siteName: String?) async throws {
        try await appDatabase.writer.write { db in
            var inst = InstanceRecord(actorId: "https://\(keychainId).example", createdAt: Date(), updatedAt: Date())
            try inst.insert(db)
            var site = SiteRecord(instanceId: inst.id!, name: siteName)
            try site.insert(db)
            var acct = AccountRecord(siteId: site.id!, accountKeychainId: keychainId, isSignedOutAccountType: true, isEphemeral: isEphemeral)
            try acct.insert(db)
        }
    }

    @Test
    func ephemeralWithMissingSiteInfoShouldFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "browse", isEphemeral: true, siteName: nil)
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "browse") == true)
    }

    @Test
    func ephemeralWithSiteInfoDoesNotFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "browse", isEphemeral: true, siteName: "Aussie Zone")
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "browse") == false)
    }

    @Test
    func nonEphemeralDoesNotFetch() async throws {
        let appDatabase = try AppDatabase.inMemory()
        try await seed(appDatabase, keychainId: "real", isEphemeral: false, siteName: nil)
        #expect(appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: "real") == false)
    }
}
```

- [ ] **Step 2: Run to verify failure** (method missing).

- [ ] **Step 3: Implement the decision query.**

Create `SpudDataKit/Services/AppDatabase/OnDemandSiteInfoQueries.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

public extension AppDatabase {
    /// True when an account is ephemeral (a browse account, excluded from the
    /// recurring scheduler sweep) AND its site info has not been imported yet
    /// (`site.name IS NULL`). Drives the one best-effort on-demand `getSite`
    /// fired when the user opens a browse instance. Returns false once site info
    /// lands, so it fires at most once per open of a still-unfetched instance.
    func shouldFetchSiteInfoOnDemandSync(forAccountKeychainId keychainId: String) -> Bool {
        (try? reader.read { db in
            try Bool.fetchOne(db, sql: """
                    SELECT 1 FROM account
                    JOIN site ON site.id = account.siteId
                    WHERE account.accountKeychainId = ?
                      AND account.isEphemeral = 1
                      AND site.name IS NULL
                """, arguments: [keychainId]) ?? false
        }) ?? false
    }
}
```
Note: use the same read accessor the other `*Sync` importers use (`reader` or `writer`); match the existing pattern in `AccountImporter`/`Observations`.

- [ ] **Step 4: Add the AccountService entry point.**

In `AccountService.swift`, add a `@MainActor` best-effort method (it must NOT retry and must NOT touch give-up state on failure):
```swift
    /// Fire one best-effort `getSite` for an ephemeral browse instance whose
    /// site info is missing, so a browse screen can show the instance's name/icon.
    /// No retry, no recurrence, errors swallowed — an unreachable instance fails
    /// silently. A success flows through `SiteImporter`, which also clears any
    /// give-up state (self-healing). No-op for non-ephemeral accounts or ones
    /// whose site info is already present.
    public func refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId keychainId: String) {
        guard appDatabase.shouldFetchSiteInfoOnDemandSync(forAccountKeychainId: keychainId) else { return }
        let service = lemmyService(forAccountKeychainId: keychainId)
        Task { try? await service.fetchSiteInfo() }
    }
```
Add the method to the `AccountServiceType` protocol so `AccountScope`/callers can reach it. Verify `fetchSiteInfo()` is the correct `LemmyServiceType` method name (it is the one `SchedulerService` calls).

- [ ] **Step 5: Invoke from browse navigation.**

In `AppCoordinator.swift`, at each browse-target case that resolves a keychainId via `accountService.accountKeychainId(forInstance:)` (the `.community`, `.post`, `.person` cases in `open`/`navigate`), call the refresh right after resolving:
```swift
            let accountKeychainId = dependencies.accountService.accountKeychainId(forInstance: instance)
            dependencies.accountService.refreshSiteInfoOnDemandIfNeeded(forAccountKeychainId: accountKeychainId)
```
(Only where an instance-scoped browse account is resolved — do not add it to paths that use the default account.)

- [ ] **Step 6: Run to verify pass** (the 3 decision-query tests) **and build the app target** so the AccountService/AppCoordinator wiring compiles:
```bash
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17"
```

- [ ] **Step 7: SwiftFormat + commit.**
```bash
mint run swiftformat SpudDataKit/Services/AppDatabase/OnDemandSiteInfoQueries.swift SpudDataKit/Services/Account/AccountService.swift Spud/App/AppCoordinator.swift SpudDataKitTests/OnDemandSiteInfoTests.swift
make project   # a new source file was added
git add SpudDataKit/Services/AppDatabase/OnDemandSiteInfoQueries.swift SpudDataKit/Services/Account/AccountService.swift Spud/App/AppCoordinator.swift SpudDataKitTests/OnDemandSiteInfoTests.swift
git commit -m "feat: one best-effort on-demand site fetch for ephemeral browse instances"
```

---

### Task 7: Documentation

**Files:**
- Create: `docs/features/account-provenance-and-site-refresh.md` (or extend an existing scheduler/account capability doc if one already covers site-info refresh — check `docs/features/` first, e.g. `background-unread-refresh.md`)
- Modify: `docs/features/diagnostics-logging.md` (new `site.giveUp` event; bound on `site.fetchFailed`)
- Modify: `docs/features/README.md` (capability table + "Feature coverage by area" map)

- [ ] **Step 1: Write the capability doc** with `Surfaces:` / `Status:` per the `docs/features/_TEMPLATE.md` convention, covering: ephemeral vs user-created accounts, that browsing a remote instance no longer causes recurring polling, the one on-demand fetch, and the persisted give-up (N=5, survives relaunch, self-heals on visit). Include the Given/When/Then scenarios from the spec (`docs/superpowers/specs/2026-07-05-ephemeral-browse-accounts-scheduler-giveup-design.md`). No `.swift` links; no emojis.

- [ ] **Step 2: Update `diagnostics-logging.md`** — add `site.giveUp` (`.site`, notice, metadata `failureCount`) to the event enumeration, and note that `site.fetchFailed` is now bounded by the give-up (no longer recurs forever).

- [ ] **Step 3: Reconcile adjacent docs** — the `background-unread-refresh.md` note about scheduler back-off should mention the back-off is now persisted per-site and terminates after N permanent failures.

- [ ] **Step 4: Update `README.md` maps** — add the capability row + place it in the by-area map.

- [ ] **Step 5: Commit.**
```bash
git add docs/features/
git commit -m "docs: ephemeral browse accounts + persisted scheduler give-up"
```

---

## Final verification (after all tasks)

- [ ] Full SpudDataKit test target green: `-only-testing:SpudDataKitTests` (see Global Constraints command). Confirm `✔ Test run ... passed` and no regressions in `SchedulerServiceBackoffTests`, `GetSiteDiagnosticsTests`, `AccountService*Tests`.
- [ ] App target builds: `build_and_test.py --scheme Spud --simulator "iPhone 17"`.
- [ ] `make project` has been run (new source files added in Tasks 3 and 6).
- [ ] Manual (optional, high-value): on a booted sim with a browse account for a blocked instance, confirm About → Logs no longer shows recurring `site.fetchFailed` for it after upgrade, and (if reproducible) shows a single `site.giveUp`.

## Self-review notes (spec coverage)

- Spec §1 data model → Task 1. §2 tagging → Task 2; sweep exclusion → Task 4; on-demand fetch → Task 6. §3 persisted give-up (record/gate/abandon/un-abandon) → Tasks 3, 4, 5. §4 diagnostics `site.giveUp` → Task 5. Testing plan → per-task tests. Docs plan → Task 7.
- Non-goals honored: no GC/deletion anywhere; signed-in path explicitly left on in-memory back-off (Task 5); no ephemeral-scope refactor.
- Open risks carried from spec: exact `OutboxFailureClass` case name (Task 5 Step 4 verifies), the migrator test seam (Task 1 Step 4), and whether `Date` persists as epoch double for the SQL comparison (Task 4 Step 3 verifies).
