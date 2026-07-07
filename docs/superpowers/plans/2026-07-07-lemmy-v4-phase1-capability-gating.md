# Lemmy 1.0 detection + capability gating (v4 initiative Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an account's home instance runs Lemmy 1.0 (whose always-on v3
compat shim lacks person profiles, inbox, private messages, image upload,
post-hide and `save_user_settings`), Spud detects the version from data it
already persists and gates those six features with explanatory UI instead of
raw failures.

**Architecture:** A pure `LemmyVersion` parser plus a semantic
`InstanceCapabilities` table (derived from software + version, never checked
by version at call sites) feed two enforcement layers: UI entry points read
`scope.capabilities` (a new live accessor on `AccountScope`, resolved from the
persisted `SiteRecord.version` on every read, so an instance upgrading
mid-session self-corrects on the next getSite import), and `LemmyService`
throws a typed `LemmyServiceError.unsupportedByInstance(_:)` backstop before
any network call. Design record:
`docs/superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md` (D6).

**Tech Stack:** Swift 6 (strict concurrency), UIKit, GRDB, Swift Testing
(unit), swift-snapshot-testing (snapshot), SBTUITestTunnel (UITest).

## Global Constraints

- Work on branch `feat/lemmy-v4-capability-gating` in the worktree
  `.claude/worktrees/lemmy-v4` (never touch the main checkout or other
  worktrees).
- Swift 6 language mode + complete strict concurrency in all touched targets.
- Unit tests are Swift Testing (`struct` suites, `@Test`, `#expect`); files
  using `Date`/`URL` need explicit `import Foundation`.
- No emojis anywhere. Conventional commit subjects. Small focused commits.
- New source files require `make project` (XcodeGen) before building.
- Build the TEST targets after touching any VC `Dependencies` (missed test
  doubles surface as linker errors, not compile errors).
- Run `mint run swiftformat <changed paths>` BEFORE the final test verify of
  each task, never after.
- Fail-open philosophy (matches NodeInfo detection): an unknown or
  unparseable version means ALL capabilities available. Gating requires a
  positively parsed Lemmy major version >= 1.
- Copy terminology: features are "not available yet" on this instance and
  "Spud support is coming" — never blame the instance, never say "upgrade".
- Docs discipline: the feature-doc task updates `docs/features/` per the
  template; no `.swift` links in feature docs.
- Verify commands: `make test-only ONLY=SpudDataKitTests`,
  `make test-only ONLY=SpudTests`, `make snapshot` (reference sim only),
  `make test` for the full plan.

---

### Task 1: `LemmyVersion` parser

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/LemmyVersion.swift`
- Test: `SpudDataKitTests/LemmyVersionTests.swift`

**Interfaces:**
- Produces: `public struct LemmyVersion: Sendable, Equatable { public let major: Int; public let minor: Int; public let patch: Int; public init?(parsing: String) }`
- Consumed by Tasks 2, 3, 4.

- [ ] **Step 1: Write the failing tests**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

@testable import SpudDataKit
import Testing

struct LemmyVersionTests {
    @Test(arguments: [
        ("0.19.11", 0, 19, 11),
        ("1.0.0", 1, 0, 0),
        ("1.0.0-alpha.18", 1, 0, 0),
        ("1.2.3-rc.1", 1, 2, 3),
        ("0.19", 0, 19, 0),
        ("1", 1, 0, 0),
    ])
    func parsesVersionStrings(input: String, major: Int, minor: Int, patch: Int) {
        let version = LemmyVersion(parsing: input)
        #expect(version?.major == major)
        #expect(version?.minor == minor)
        #expect(version?.patch == patch)
    }

    @Test(arguments: ["", "unknown", "v1.0.0", "one.two", "-alpha", ".", "-", "-1.0.0"])
    func rejectsUnparseableStrings(input: String) {
        #expect(LemmyVersion(parsing: input) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `make test-only ONLY=SpudDataKitTests` (or the narrower
`xcodebuild ... -only-testing:SpudDataKitTests/LemmyVersionTests` fallback
from CLAUDE.md). Expected: build FAILS with "cannot find 'LemmyVersion' in
scope".

- [ ] **Step 3: Implement**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// A parsed Lemmy server version ("0.19.11", "1.0.0-alpha.18"). Only the
/// numeric major.minor.patch core is modelled; prerelease identifiers are
/// tolerated and discarded (an alpha of 1.0 gates like 1.0). Parsing is
/// strict about the leading component: a string whose first dot-separated
/// component is not a plain integer is unparseable (nil), so arbitrary fork
/// version strings fail open rather than mis-gate.
public struct LemmyVersion: Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(parsing string: String) {
        // Strip a prerelease/build suffix: "1.0.0-alpha.18" -> "1.0.0".
        // omittingEmptySubsequences: false is load-bearing twice over: it
        // guarantees a non-empty array (so [0] can't trap on ""), and it keeps
        // a leading "-" ("-1.0.0") as an empty core that fails the major-int
        // guard below instead of silently parsing the suffix as a version.
        let core = string.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: ".")
        guard let first = parts.first, let major = Int(first) else { return nil }
        self.major = major
        minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`. Expected: the
Swift Testing summary line `✔ Test run with N tests ... passed` and both new
suites green.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/LemmyVersion.swift SpudDataKitTests/LemmyVersionTests.swift
git add SpudDataKit/Services/NodeInfo/LemmyVersion.swift SpudDataKitTests/LemmyVersionTests.swift
git commit -m "feat: add LemmyVersion parser for instance version strings"
```

---

### Task 2: `InstanceCapability` + `InstanceCapabilities` + `PlatformProfile.capabilities`

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/InstanceCapabilities.swift`
- Modify: `SpudDataKit/Services/NodeInfo/PlatformProfile.swift` (add a
  computed property at the end of the struct)
- Test: `SpudDataKitTests/InstanceCapabilitiesTests.swift`

**Interfaces:**
- Consumes: `LemmyVersion` (Task 1), `InstanceSoftware` (existing).
- Produces:
  - `public enum InstanceCapability: String, Sendable, CaseIterable, Codable`
    with cases `personProfiles, inbox, privateMessages, imageUpload,
    serverUserSettings, hidePosts`.
  - `public struct InstanceCapabilities: Sendable, Equatable` with
    `public func can(_ capability: InstanceCapability) -> Bool`,
    `public static let allAvailable: InstanceCapabilities`, and
    `public static func capabilities(software: InstanceSoftware, version: LemmyVersion?) -> InstanceCapabilities`.
  - `PlatformProfile.capabilities: InstanceCapabilities`.

- [ ] **Step 1: Write the failing tests**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

@testable import SpudDataKit
import Testing

struct InstanceCapabilitiesTests {
    @Test func lemmy019HasEverything() {
        let caps = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "0.19.11")
        )
        for capability in InstanceCapability.allCases {
            #expect(caps.can(capability))
        }
    }

    @Test func lemmy1ViaV3ShimLosesEveryGatedCapability() {
        let caps = InstanceCapabilities.capabilities(
            software: .lemmy,
            version: LemmyVersion(parsing: "1.0.0-alpha.18")
        )
        for capability in InstanceCapability.allCases {
            #expect(!caps.can(capability), "expected \(capability) gated on Lemmy 1.0 via the v3 shim")
        }
    }

    @Test func unknownVersionFailsOpen() {
        let caps = InstanceCapabilities.capabilities(software: .lemmy, version: nil)
        for capability in InstanceCapability.allCases {
            #expect(caps.can(capability))
        }
    }

    @Test func nonLemmySoftwareFailsOpen() {
        // Non-Lemmy software can't be a home connection (PlatformRouter blocks
        // it), so capabilities are moot there — but the derivation must not
        // mis-apply the Lemmy shim table to e.g. PieFed version numbers.
        let caps = InstanceCapabilities.capabilities(
            software: .piefed,
            version: LemmyVersion(parsing: "1.2.0")
        )
        #expect(caps.can(.inbox))
    }

    @Test func platformProfileExposesCapabilities() {
        let profile = PlatformProfile.profile(for: .lemmy, version: "1.0.0")
        #expect(!profile.capabilities.can(.inbox))
        let old = PlatformProfile.profile(for: .lemmy, version: "0.19.11")
        #expect(old.capabilities.can(.inbox))
    }
}
```

- [ ] **Step 2: Run to verify failure** — `make test-only ONLY=SpudDataKitTests`, expect "cannot find 'InstanceCapabilities'".

- [ ] **Step 3: Implement**

`SpudDataKit/Services/NodeInfo/InstanceCapabilities.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

/// A feature Spud needs the home instance's API to support. Semantic — UI and
/// services ask "can this instance do X?", never "which Lemmy version is it?",
/// so the version->capability table stays in exactly one place (below).
public enum InstanceCapability: String, Sendable, CaseIterable, Codable {
    case personProfiles
    case inbox
    case privateMessages
    case imageUpload
    case serverUserSettings
    case hidePosts
    /// Server-side read-state sync (`/post/mark_as_read`). Never surfaces UI:
    /// read tracking is locally owned (postInteraction), so the service just
    /// skips the server push when unavailable.
    case markPostsRead
}

/// The set of `InstanceCapability` an instance supports, derived from its
/// software + version. Fail-open: anything not positively known to be
/// unavailable is available (mirrors NodeInfo detection's fail-open rule —
/// a mis-gate is worse than a raw server error).
public struct InstanceCapabilities: Sendable, Equatable {
    private let unavailable: Set<InstanceCapability>

    public func can(_ capability: InstanceCapability) -> Bool {
        !unavailable.contains(capability)
    }

    public static let allAvailable = InstanceCapabilities(unavailable: [])

    /// The derivation table. Lemmy >= 1.0 is reached through its partial v3
    /// compat shim until Spud speaks the v4 API (initiative Phase 5/6); the
    /// shim lacks exactly these endpoints: person details, replies/mentions,
    /// all private-message operations, image upload, `/post/hide`, and
    /// `save_user_settings`. Non-Lemmy software fails open — it cannot be a
    /// home connection at all (`PlatformRouter`), and its version numbers
    /// must not be read on the Lemmy scale.
    public static func capabilities(
        software: InstanceSoftware,
        version: LemmyVersion?
    ) -> InstanceCapabilities {
        guard software == .lemmy, let version, version.major >= 1 else {
            return .allAvailable
        }
        return InstanceCapabilities(unavailable: Set(InstanceCapability.allCases))
    }
}
```

Append to `PlatformProfile` (inside the struct, after `canBeHomeConnection`):

```swift
    /// What the instance's API supports, derived from software + version.
    /// See `InstanceCapabilities.capabilities(software:version:)` for the table.
    public var capabilities: InstanceCapabilities {
        InstanceCapabilities.capabilities(
            software: software,
            version: version.flatMap(LemmyVersion.init(parsing:))
        )
    }
```

- [ ] **Step 4: Run to verify pass** — `make project && make test-only ONLY=SpudDataKitTests`.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/ SpudDataKitTests/InstanceCapabilitiesTests.swift
git add SpudDataKit/Services/NodeInfo/InstanceCapabilities.swift SpudDataKit/Services/NodeInfo/PlatformProfile.swift SpudDataKitTests/InstanceCapabilitiesTests.swift
git commit -m "feat: add InstanceCapabilities derivation on PlatformProfile"
```

---

### Task 3: capabilities reachable from the app — `AppDatabase` version lookup, `AccountServiceType.instanceCapabilities`, `AccountScope.capabilities`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift`
  (add two lookups next to `accountInstanceActorIdSync`, line ~102)
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (protocol
  `AccountServiceType` at line 17 + implementation; `appDatabase` is a
  private field at line 222)
- Modify: `SpudDataKit/Services/Account/AccountScope.swift` (new accessor
  after `instanceActorId`, line ~56)
- Test: `SpudDataKitTests/AccountCapabilitiesTests.swift`

**Interfaces:**
- Consumes: `InstanceCapabilities.capabilities(software:version:)`,
  `LemmyVersion` (Tasks 1-2).
- Produces:
  - `AppDatabase.accountSiteVersionSync(forKeychainId:) -> String?` and
    async twin `accountSiteVersion(forKeychainId:) async -> String?`.
  - `AccountServiceType.instanceCapabilities(forAccountKeychainId: String) -> InstanceCapabilities`.
  - `AccountScope.capabilities: InstanceCapabilities` — the accessor every
    UI task (7-9) reads. Resolves live on each read like the scope's other
    accessors, so a version flip imported by getSite is picked up without
    invalidation plumbing.
- Note: any `AccountServiceType` test doubles/mocks in SpudTests /
  SpudDataKitTests / SpudSnapshotTests must gain the new protocol method
  (default-returning `.allAvailable`); a missed double is a LINKER error in
  the test targets, so build the full test plan.

- [ ] **Step 1: Write the failing test**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

@testable import SpudDataKit
import Testing

struct AccountCapabilitiesTests {
    @Test func siteVersionResolvesThroughAccountJoin() async throws {
        let db = try AppDatabase.inMemory()
        // Seed instance -> site(version) -> account rows the same way the
        // existing AccountImporter tests do (reuse their fixture helper if one
        // exists; otherwise insert minimal rows directly).
        let keychainId = try await seedAccount(db: db, siteVersion: "1.0.0-alpha.18")
        #expect(db.accountSiteVersionSync(forKeychainId: keychainId) == "1.0.0-alpha.18")
        let missing = db.accountSiteVersionSync(forKeychainId: "no-such-account")
        #expect(missing == nil)
    }
}
```

(Adapt the seeding to the codebase's existing test fixture idiom — look at how
`SpudDataKitTests` seeds account/site/instance rows for importer tests, and
reuse that helper. The assertion surface must stay exactly as above.)

- [ ] **Step 2: Run to verify failure** — expect "no member 'accountSiteVersionSync'".

- [ ] **Step 3: Implement the lookups** (in `AccountImporter.swift`, mirroring
`accountInstanceActorIdSync` exactly — same extension, same error-logging
shape):

```swift
    /// Synchronous lookup of the home-instance Lemmy version string (as last
    /// mirrored from getSite into `site.version`) for the account matching
    /// `keychainId`. Nil when the account/site rows haven't been imported yet
    /// or the site has no version — callers must fail open on nil.
    func accountSiteVersionSync(forKeychainId keychainId: String) -> String? {
        do {
            return try writer.read { db in
                try Row.fetchOne(db, sql: """
                        SELECT site.version AS version
                        FROM account
                        JOIN site ON site.id = account.siteId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])?["version"]
            }
        } catch {
            logger.error("Failed to resolve account site version: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Async equivalent of ``accountSiteVersionSync(forKeychainId:)`` for
    /// actor callers (LemmyService's capability backstop).
    func accountSiteVersion(forKeychainId keychainId: String) async -> String? {
        do {
            return try await writer.read { db in
                try Row.fetchOne(db, sql: """
                        SELECT site.version AS version
                        FROM account
                        JOIN site ON site.id = account.siteId
                        WHERE account.accountKeychainId = ?
                    """, arguments: [keychainId])?["version"]
            }
        } catch {
            logger.error("Failed to resolve account site version: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
```

- [ ] **Step 4: Protocol + implementation.** Add to `AccountServiceType`
(next to the `isSignedOut(forAccountKeychainId:)` requirement):

```swift
    /// What the account's home instance supports, derived from the persisted
    /// site version (fail-open when unknown). Re-resolved on every call so a
    /// version change imported by getSite takes effect without invalidation.
    func instanceCapabilities(forAccountKeychainId accountKeychainId: String) -> InstanceCapabilities
```

Implementation in `AccountService` (the home instance is by definition
Lemmy-API-speaking — non-Lemmy software is blocked at login by
`PlatformRouter` — so derive with `.lemmy`):

```swift
    public func instanceCapabilities(forAccountKeychainId accountKeychainId: String) -> InstanceCapabilities {
        let version = appDatabase.accountSiteVersionSync(forKeychainId: accountKeychainId)
        return InstanceCapabilities.capabilities(
            software: .lemmy,
            version: version.flatMap(LemmyVersion.init(parsing:))
        )
    }
```

And on `AccountScope` (after `instanceActorId`):

```swift
    /// What this account's home instance supports (fail-open when unknown).
    /// Read live on every access — after the instance upgrades and a getSite
    /// import records the new version, existing scopes see the new value.
    public var capabilities: InstanceCapabilities {
        accountService.instanceCapabilities(forAccountKeychainId: accountKeychainId)
    }
```

- [ ] **Step 5: Fix every `AccountServiceType` double.** Grep the three test
targets and any preview/fixture code for conformances
(`grep -rn "AccountServiceType" Spud SpudDataKitTests SpudTests SpudSnapshotTests --include='*.swift'`);
add to each double:

```swift
    func instanceCapabilities(forAccountKeychainId accountKeychainId: String) -> InstanceCapabilities {
        .allAvailable
    }
```

- [ ] **Step 6: Run the full unit-test plan** — `make project && make test`
(the plan builds all test targets; this catches missed doubles as linker
errors). Expected: green.

- [ ] **Step 7: Format + commit**

```bash
mint run swiftformat SpudDataKit SpudDataKitTests
git add -- SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift SpudDataKit/Services/Account/AccountService.swift SpudDataKit/Services/Account/AccountScope.swift SpudDataKitTests/AccountCapabilitiesTests.swift <every touched test double>
git commit -m "feat: expose per-account InstanceCapabilities via AccountScope"
```

---

### Task 4: `LemmyServiceError.unsupportedByInstance` + service backstop guards

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (error enum line
  15; guards in `fetchPersonInfo` line ~1199, `fetchPersonContent` ~1236,
  `uploadImage` ~1718, `saveProfile` ~1117, `hidePost` — find the
  outbox-enqueue entry; new private helper near `resolveInstanceHost()` ~685)
- Modify: `SpudDataKit/Services/Lemmy/LemmyService+Inbox.swift`
  (`fetchReplies` 17, `fetchMentions` 46, `fetchPrivateMessages` 75,
  `markAllInboxAsRead` 199, `sendPrivateMessage` 240, plus any
  `markInboxItemRead`-style single-item method in that file)
- Modify: `SpudDataKit/Services/Lemmy/LemmyService+Composer.swift`
  (`sendDirectMessage` line 96 — guard BEFORE enqueueing so gated content is
  never parked in the composer outbox)
- Modify: `SpudDataKit/Services/Outbox/OutboxFailureClass.swift` (line ~42:
  the exhaustive switch gains the new case)
- Test: `SpudDataKitTests/LemmyServiceCapabilityGatingTests.swift`, plus one
  case appended to the existing `OutboxFailureClass` test suite (find it via
  `grep -rln OutboxFailureClass SpudDataKitTests`).

**Interfaces:**
- Consumes: `AppDatabase.accountSiteVersion(forKeychainId:)` (Task 3),
  `InstanceCapabilities` (Task 2).
- Produces: `LemmyServiceError.unsupportedByInstance(InstanceCapability)`;
  internal `LemmyService.instanceCapabilities() async -> InstanceCapabilities`
  and `requireCapability(_:) async throws`. UI tasks 7-9 catch the new error
  case; Task 5 reuses `instanceCapabilities()`.

- [ ] **Step 1: Write the failing tests.** Follow the existing
`LemmyService` test idiom (in-memory `AppDatabase`, stub `ClientTransport` —
see `LemmyServiceContentNotFoundTests` for the pattern). The transport double
must RECORD whether any request was sent, to prove the guard fires before the
network:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

@testable import SpudDataKit
import Testing

struct LemmyServiceCapabilityGatingTests {
    @Test func inboxFetchThrowsUnsupportedOnLemmy1WithoutNetwork() async throws {
        let fixture = try await makeService(siteVersion: "1.0.0-alpha.18") // reuse/extend the suite's service fixture helper
        await #expect(throws: LemmyServiceError.self) {
            try await fixture.service.fetchReplies(unreadOnly: false) // match the real signature
        }
        #expect(fixture.transport.requestCount == 0)
    }

    @Test func inboxFetchProceedsOn019() async throws {
        let fixture = try await makeService(siteVersion: "0.19.11")
        _ = try? await fixture.service.fetchReplies(unreadOnly: false)
        #expect(fixture.transport.requestCount > 0)
    }

    @Test func unknownVersionFailsOpen() async throws {
        let fixture = try await makeService(siteVersion: nil)
        _ = try? await fixture.service.fetchReplies(unreadOnly: false)
        #expect(fixture.transport.requestCount > 0)
    }
}
```

Add analogous throw-assertions (one `@Test(arguments:)` over closures is
fine) for `fetchPersonInfo`, `fetchPersonContent`, `fetchPrivateMessages`,
`sendPrivateMessage`, `uploadImage`, `saveProfile`, `hidePost`, and
`sendDirectMessage` (the last must also assert nothing was enqueued in the
composer outbox table). And in the OutboxFailureClass suite:

```swift
    @Test func unsupportedByInstanceIsPermanent() {
        let failureClass = OutboxFailureClass.classify(
            LemmyServiceError.unsupportedByInstance(.hidePosts),
            isOnline: true
        )
        #expect(failureClass == .permanent)
    }
```

- [ ] **Step 2: Run to verify failure** — compile error on the missing enum case.

- [ ] **Step 3: Implement.** Error case (after `.invalidContent`):

```swift
    /// The account's home instance does not support this operation (e.g. it
    /// runs Lemmy 1.0, whose v3 compat shim lacks the endpoint — see
    /// `InstanceCapabilities`). Thrown BEFORE any network call as the
    /// service-level backstop behind the UI capability gates; classified
    /// permanent by `OutboxFailureClass` (retrying cannot help until Spud
    /// itself speaks the instance's newer API).
    case unsupportedByInstance(InstanceCapability)
```

Helpers on `LemmyService` (next to `resolveInstanceHost()`):

```swift
    /// The home instance's capability set, derived per call from the persisted
    /// site version (fail-open on nil — see `InstanceCapabilities`).
    // internal: shared with LemmyService+Inbox, LemmyService+Composer
    func instanceCapabilities() async -> InstanceCapabilities {
        let version = await appDatabase.accountSiteVersion(forKeychainId: accountIdentifierForLogging)
        return InstanceCapabilities.capabilities(
            software: .lemmy,
            version: version.flatMap(LemmyVersion.init(parsing:))
        )
    }

    /// Backstop gate: throws `LemmyServiceError.unsupportedByInstance` (and
    /// records a diagnostic event) when the home instance can't serve
    /// `capability`. Call at the top of every gated operation, before any
    /// network or outbox work.
    // internal: shared with LemmyService+Inbox, LemmyService+Composer
    func requireCapability(_ capability: InstanceCapability) async throws {
        guard await instanceCapabilities().can(capability) else {
            diagnostics.record(...) // follow the existing DiagnosticLog event idiom in this file (e.g. site.fetchFailed): event name "capability.blocked", level info, attach capability.rawValue + instance host
            throw LemmyServiceError.unsupportedByInstance(capability)
        }
    }
```

(Look at how `diagnostics` events are recorded elsewhere in `LemmyService.swift`
and match that API exactly — the call above is schematic in its argument list
only; the event name, level, and attached fields are normative.)

Insert `try await requireCapability(...)` as the FIRST statement of:
`fetchPersonInfo` + `fetchPersonContent` (`.personProfiles`); `fetchReplies` +
`fetchMentions` + `markAllInboxAsRead` + single-item mark-read (`.inbox`);
`fetchPrivateMessages` + `sendPrivateMessage` + `sendDirectMessage`
(`.privateMessages`); `uploadImage` (`.imageUpload`); `saveProfile`
(`.serverUserSettings`); `hidePost` (`.hidePosts`).

`OutboxFailureClass.classify` (the exhaustive `LemmyServiceError` switch —
the compiler forces this):

```swift
            case .unsupportedByInstance:
                // The instance can't serve this endpoint at all (e.g. Lemmy
                // 1.0's partial v3 shim); no retry can succeed until Spud
                // speaks the newer API, so roll back rather than spin.
                return .permanent
```

- [ ] **Step 4: Run to verify pass** — `make test-only ONLY=SpudDataKitTests`.

- [ ] **Step 5: Format + commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy SpudDataKit/Services/Outbox SpudDataKitTests
git add -- SpudDataKit/Services/Lemmy/LemmyService.swift SpudDataKit/Services/Lemmy/LemmyService+Inbox.swift SpudDataKit/Services/Lemmy/LemmyService+Composer.swift SpudDataKit/Services/Outbox/OutboxFailureClass.swift SpudDataKitTests/LemmyServiceCapabilityGatingTests.swift <outbox test file>
git commit -m "feat: gate unsupported operations in LemmyService with typed error"
```

---

### Task 5: soft-degrade paths — unread counts and settings mirrors

Some gated calls must NOT throw, because they are background mirrors with a
local source of truth, or scheduler-driven polls that would spam the log:

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService+Inbox.swift`
  (`unreadCount()` line ~103: when `.inbox` is unavailable, return the
  all-zeros `UnreadCounts` value — the type at `LemmyService.swift:615` —
  without a network call)
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` (`setShowNsfw`
  ~1031, `setBlurNsfw` ~1068, `setDefaultSortType` ~1090: when
  `.serverUserSettings` is unavailable, SKIP the `saveUserSettings` server
  push but keep the local mirror write, exactly like their existing
  signed-out no-op semantics; record one diagnostic event)
- Modify: `SpudDataKit/Services/Lemmy/LemmyService+Composer.swift`
  (`markAsRead` line ~154, which calls `api.markPostAsRead` at ~164: when
  `.markPostsRead` is unavailable, skip the server push silently — read
  tracking is locally owned by `postInteraction`, so nothing user-visible
  changes)
- Test: extend `SpudDataKitTests/LemmyServiceCapabilityGatingTests.swift`.

**Interfaces:** consumes `instanceCapabilities()` from Task 4. No new public API.

- [ ] **Step 1: Failing tests** — `unreadCount()` on a 1.0-version fixture
returns `UnreadCounts(replies: 0, mentions: 0, privateMessages: 0)` with
`transport.requestCount == 0`; `setShowNsfw(true)` on the same fixture does
not throw, sends no request, and the account row's `showNsfw` mirror is
updated (read it back via the same query the existing setShowNsfw tests use).
- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement** — early-return branches at the top of the four
methods, each with a one-line why-comment referencing the local source of
truth ("local pref still governs filtering via the request param; the server
push resumes once Spud speaks this instance's API").
- [ ] **Step 4: Verify pass** — `make test-only ONLY=SpudDataKitTests`.
- [ ] **Step 5: Format + commit** — `git commit -m "feat: soft-degrade unread counts and settings mirrors on gated instances"`.

---

### Task 6: capability-gate presentation — copy + sheet

**Files:**
- Create: `Spud/Scenes/CapabilityGate/CapabilityGateCopy.swift`
- Create: `Spud/Scenes/CapabilityGate/UIViewController+CapabilityGate.swift`
- Test: `SpudTests/CapabilityGateCopyTests.swift`
- Run `make project` after creating the files (XcodeGen).

**Interfaces:**
- Consumes: `InstanceCapability` (Task 2), `AccountScope.instanceActorId`
  (existing) for the host name.
- Produces (for Tasks 7-9):
  - `struct CapabilityGateCopy { let title: String; let message: String; static func copy(for: InstanceCapability, host: String?) -> CapabilityGateCopy }`
  - `UIViewController.presentCapabilityGate(for capability: InstanceCapability, host: String?, sourceView: UIView?)`
    — action-sheet presentation modeled line-for-line on
    `Spud/Scenes/Account/PlatformBlockedSheet.swift:14` (warning haptic like
    `presentSignInGate`, popover anchoring for iPad, single "OK"/"Cancel"
    dismiss action).

- [ ] **Step 1: Failing copy tests** (copy is behavior — pin it):

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

@testable import Spud
import SpudDataKit
import Testing

struct CapabilityGateCopyTests {
    @Test func inboxCopyNamesHostAndPromisesSupport() {
        let copy = CapabilityGateCopy.copy(for: .inbox, host: "lemmy.world")
        #expect(copy.title == "Inbox isn't available yet")
        #expect(copy.message.contains("lemmy.world"))
        #expect(copy.message.contains("newer version of Lemmy"))
        #expect(copy.message.contains("coming in an update"))
    }

    @Test func nilHostFallsBackToGenericNoun() {
        let copy = CapabilityGateCopy.copy(for: .hidePosts, host: nil)
        #expect(copy.message.contains("This instance"))
    }
}
```

- [ ] **Step 2: Verify failure.**
- [ ] **Step 3: Implement.** Exact copy table (title / feature noun used in
the shared message template "\(host ?? "This instance") runs a newer version
of Lemmy. Spud can't \(verbPhrase) there yet — support is coming in an
update."):

| Capability | Title | verbPhrase |
|---|---|---|
| personProfiles | "Profiles aren't available yet" | "open profiles" |
| inbox | "Inbox isn't available yet" | "load your inbox" |
| privateMessages | "Messages aren't available yet" | "send or receive messages" |
| imageUpload | "Image upload isn't available yet" | "upload images" |
| serverUserSettings | "Profile editing isn't available yet" | "save profile changes" |
| hidePosts | "Hiding posts isn't available yet" | "hide posts" |
| markPostsRead | "Read syncing isn't available yet" | "sync read posts" (never presented — service-only soft-degrade; the entry exists only so the copy table is total over the enum) |

- [ ] **Step 4: Verify pass** — `make project && make test-only ONLY=SpudTests`.
- [ ] **Step 5: Format + commit** — `git commit -m "feat: add capability-gate sheet and copy"`.

---

### Task 7: Inbox gating UI

**Files:**
- Modify: `Spud/Scenes/Inbox/InboxViewModel.swift` (`loadAll()` line ~120:
  skip all three loads when `!accountScope.capabilities.can(.inbox)`; expose
  `var isInboxGated: Bool` and `var gatedHost: String?` — host via
  `accountScope.instanceActorId?.hostWithPort`)
- Modify: `Spud/Scenes/Inbox/InboxViewController.swift`
  (`updateContentUnavailable` line ~273 and the config builder ~321: when
  gated, show a `UIContentUnavailableConfiguration` built from
  `CapabilityGateCopy.copy(for: .inbox, host:)` with an SF Symbol like
  `tray.slash`, for ALL scopes; `composeButton` (line 110) hidden when
  `!capabilities.can(.privateMessages)`; pull-to-refresh on a gated inbox
  ends refreshing immediately without fetching)
- Snapshot test: gated inbox state. Check for an existing Inbox snapshot
  suite (`ls SpudSnapshotTests | grep -i inbox`); extend it if present,
  otherwise create `SpudSnapshotTests/InboxGatedSnapshotTests.swift`
  following the conventions in `SpudSnapshotTests/CLAUDE.md` (read it first:
  `deterministicPhone` config, ephemeral preferences, async-GRDB seeding,
  record-then-verify flow, annex staging rules).

**Interfaces:** consumes `scope.capabilities` (Task 3) and
`CapabilityGateCopy` (Task 6). The explain-don't-hide rule (design D6): the
tab stays, the state explains.

- [ ] **Step 1:** Write the gated-state snapshot test (and a
`SpudTests`-level unit test that `InboxViewModel.loadAll()` performs no
service calls when gated, using the existing VM test double idiom if
InboxViewModel already has tests — check `grep -rln InboxViewModel SpudTests`).
- [ ] **Step 2:** Verify the snapshot test records (first run records + fails, rerun verifies) and the VM test fails against current code.
- [ ] **Step 3:** Implement VC + VM changes.
- [ ] **Step 4:** `make test-only ONLY=SpudTests && make snapshot` — green; re-run `make snapshot` a second time to prove byte-stability.
- [ ] **Step 5:** Format + commit — `git commit -m "feat: explain gated inbox on Lemmy 1.0 instances"` (stage the new snapshot refs explicitly, one class at a time, per annex rules).

---

### Task 8: person-profile gating

**Files:**
- Modify: `Spud/Scenes/Person/Loading/PersonLoadingViewController.swift`
  (fetch trigger at ~139: when `!scope.capabilities.can(.personProfiles)`,
  render a terminal `UIContentUnavailableConfiguration` from
  `CapabilityGateCopy.copy(for: .personProfiles, host:)` instead of starting
  the fetch — the loading VC stays on the nav stack; do NOT attempt the
  wrapper's stack swap in the gated path)
- Modify: `Spud/Scenes/Activity/ActivityViewController.swift` (~268-274:
  pass a nil authored source when `!scope.capabilities.can(.personProfiles)`
  so Activity degrades to its local-only footprint — the degradation path
  that already exists)
- Test: extend whatever unit coverage `PersonLoadingViewController` /
  Activity wiring already has; at minimum a `SpudTests` test that the gated
  Activity wiring passes `authoredSource: nil` (follow the existing
  ActivityViewController test/double pattern if present, else assert via the
  view model seam).

**Interfaces:** consumes Tasks 3 + 6. The service backstop (Task 4) already
covers every un-gated route to `getPersonDetails` (six push sites + DM
header) — the loading-VC state is the user-facing explanation for all of
them, so the push sites themselves need no changes.

- [ ] **Step 1:** Failing test(s) as above.
- [ ] **Step 2:** Verify failure.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `make test-only ONLY=SpudTests` green; also `make build`.
- [ ] **Step 5:** Format + commit — `git commit -m "feat: gate person profiles on Lemmy 1.0 instances"`.

---

### Task 9: action gates — hide, image attach, edit profile, DM thread

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`
  (`hidePost(serverPostId:)` line ~1651: after the existing sign-in gate,
  add `guard viewModel.accountScope.capabilities.can(.hidePosts) else { presentCapabilityGate(...); return }`;
  ALSO check whether PostDetail exposes hide — `grep -rn "hidePost" Spud/Scenes/PostDetail/` — and gate any hit the same way)
- Modify: `Spud/Scenes/Composer/NewPostViewController.swift`
  (`attachImageTapped()` line ~471: capability check first → present the
  gate sheet anchored on `attachImageButton`; the button stays visible and
  enabled — explain, don't hide)
- Modify: `Spud/Scenes/Account/AccountViewController.swift`
  (`openEditProfile(keychainId:)` line ~288: gate `.serverUserSettings`
  with the sheet before presenting the editor)
- Modify: `Spud/Scenes/Inbox/DMThreadViewController.swift` /
  `DMThreadViewModel.swift`: when `!capabilities.can(.privateMessages)`,
  show the gated `UIContentUnavailableConfiguration` (reuse the
  `emptyConfiguration()` seam at ~243/289) and disable the input bar;
  `DMThreadViewModel.send` additionally guards (backstop for a thread opened
  pre-flip)
- Test: `SpudTests` unit tests where a VM seam exists (DMThread send guard);
  the sheet-presenting VC paths are covered by the Task 10 UITest and code
  review — do not build ad-hoc VC harnesses for them.

**Interfaces:** consumes Tasks 3 + 6. Every gate reads
`scope.capabilities` at action time (no caching in the VC).

- [ ] **Step 1:** Failing DMThread send-guard test.
- [ ] **Step 2:** Verify failure.
- [ ] **Step 3:** Implement all four gates.
- [ ] **Step 4:** `make test` (full plan — Dependencies-cascade check) green.
- [ ] **Step 5:** Format + commit — `git commit -m "feat: gate hide, image attach, profile editing and DMs on Lemmy 1.0 instances"`.

---

### Task 10: end-to-end UITest — gated inbox on a 1.0 instance

**Files:**
- Create: `SpudUITests/CapabilityGateUITests.swift`
- Possibly create a fixture: a getSite stub JSON with `"version": "1.0.0"`.
  First locate the getSite stub the existing signed-in suites use
  (`grep -rn "site" SpudUITests --include='*.swift' -l` and the fixture
  JSONs in the UITest target); copy it and change only the version field.
  Remember: SBT fixtures must include EVERY required field of the generated
  response type, and `SBTStubResponse(fileNamed:)` NSAsserts (whole-class
  failure) if the file isn't in the target — add it via `make project`.

**Interfaces:** consumes the shipped launch-argument seams
(`SPUDWipeAppDatabase` + `SPUDSeedSignedInDefaultAccount`, both required for
order-independence) and the Task 7 UI.

- [ ] **Step 1:** Write the test: launch with wipe + signed-in seed, stub
`GET /api/v3/site` with the 1.0 fixture, trigger the site refresh (the app
fetches site info on launch), open the Inbox tab (tab index 3), assert the
gated title ("Inbox isn't available yet") exists within a generous timeout,
and assert the compose button does not exist. Model the structure on
`NodeInfoBlockUITests` (the closest precedent: seeded launch + stubbed
network + asserting a block surface).
- [ ] **Step 2:** Run it on the booted reference sim
(`make test-only ONLY=SpudUITests` narrowed with `-only-testing` if the make
target allows, else the raw xcodebuild fallback). Single-simulator rule:
verify only one sim is booted first. Expected: FAIL before Task 7's UI, PASS
after (if executing in order, just expect PASS — the value is regression
coverage).
- [ ] **Step 3:** Commit — `git commit -m "test: cover gated inbox against a Lemmy 1.0 instance"`.

---

### Task 11: feature docs

**Files:**
- Create: `docs/features/instance-capability-gating.md` (follow
  `docs/features/_TEMPLATE.md` and mirror the structure of
  `docs/features/instance-software-detection.md`: Surfaces / Status /
  Related front-matter; What it does; Behavior and rules; Scenarios as
  Given/When/Then; Not supported / out of scope. Status: honest — shipped
  gating for six capabilities, v4 API support itself is
  initiative-Phase-5/6 future work. No `.swift` links.)
- Modify: `docs/features/README.md` — BOTH the capability table AND the
  "Feature coverage by area" map (they drift independently).
- Modify (one "Related"/caveat line each): `docs/features/inbox.md`,
  `private-messages.md`, `person-profile.md`, `image-upload.md`,
  `mark-read-and-hiding.md`, `profile-editing.md`,
  `instance-software-detection.md`, `diagnostics-logging.md` (the new
  `capability.blocked` event).

- [ ] **Step 1:** Write the new doc + all cross-link edits.
- [ ] **Step 2:** Re-read each touched doc end-to-end for staleness the
change introduces (docs discipline: reconcile adjacent docs).
- [ ] **Step 3:** Commit — `git commit -m "docs: document instance capability gating"`.

---

### Task 12: final verify + merge prep

- [ ] **Step 1:** `mint run swiftformat .` then `git status -u` — confirm
only intended files are dirty (annex cosmetic `M` noise excluded; run
`git annex restage` if snapshot refs show modified).
- [ ] **Step 2:** Full gates: `make test` AND `make snapshot` (twice for
byte-stability) on the reference sim.
- [ ] **Step 3:** Broad final review (subagent-driven-development's
end-of-plan review): whole-branch diff review against this plan + the
design doc, checking especially: every gate fails open on unknown version;
no version checks outside `InstanceCapabilities`; copy consistency;
diagnostic events recorded.
- [ ] **Step 4:** Merge to local `main` per workspace CLAUDE.md rules:
re-check `git diff --name-only $(git merge-base main HEAD) main` overlap
RIGHT BEFORE merging, `git annex restage` in the shared checkout first if
merging there, prefer the throwaway-worktree merge if `main` is not checked
out anywhere. Do NOT push (push gate).
