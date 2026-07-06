# NodeInfo Platform Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect an instance's software (Lemmy / PieFed / Mbin / Mastodon / …) via NodeInfo and block non-Lemmy home connections honestly, behind a capability-descriptor + router seam, with LemmyService untouched.

**Architecture:** A `NodeInfoService` actor (SpudDataKit) probes `/.well-known/nodeinfo` via the `DiasporaNodeInfo` SPM package, maps `software.name` to an `InstanceSoftware` enum, and caches the result in a host-keyed GRDB table. A pure `PlatformProfile` capability lookup + a `PlatformRouter` decide allow/block at the account login/register pre-flight. Instance detail shows the detected software name. Probes happen only on explicit engagement; failures fail open.

**Tech Stack:** Swift 6 / strict concurrency, actors, GRDB, Swift Testing, XcodeGen, UIKit. Design spec: `docs/superpowers/specs/2026-07-05-nodeinfo-platform-detection-design.md`.

## Global Constraints

- Swift 6.0 language mode + `SWIFT_STRICT_CONCURRENCY = complete`; every new type is `Sendable`.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `test:`, `docs:`, `chore:`); small focused commits.
- New/removed source files require `make project` (XcodeGen) before build/test.
- Run tests via `make test-only ONLY=SpudDataKitTests` (or the raw `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test`). Swift Testing prints `✔ Test run with N tests ... passed` (not the XCTest "Executed N" line).
- Run `mint run swiftformat <changed paths>` BEFORE the final verify of each task, never after.
- Stage explicit paths only — never `git add -A` (`.remember/` is an untracked handoff buffer).
- Work stays on branch `feat/nodeinfo-platform-detection` (already created off `main`).
- `.known`/`.unknown` invariant: `.unknown` means "couldn't determine," NEVER "not Lemmy." Every caller treats `.unknown` as fail-open (proceed with today's behavior).
- Date columns declared `.datetime` store as ISO-8601 text; the cache compares `fetchedAt` in Swift (not SQL) to avoid the double-vs-text comparison footgun.

---

### Task 1: `InstanceSoftware` enum

Replaces the currently-unused `SpudDataKit/Utils/NodeInfoSoftware.swift` (grep confirmed: no references anywhere except its own definition) with a public, Sendable enum that maps a raw NodeInfo `software.name` to a known case or `.other`.

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/InstanceSoftware.swift`
- Delete: `SpudDataKit/Utils/NodeInfoSoftware.swift`
- Test: `SpudDataKitTests/NodeInfo/InstanceSoftwareTests.swift`

**Interfaces:**
- Produces: `public enum InstanceSoftware: Sendable, Equatable` with `init(softwareName: String)`; cases `.lemmy`, `.piefed`, `.mbin`, `.kbin`, `.mastodon`, `.misskey`, `.pleroma`, `.peertube`, `.friendica`, `.gotosocial`, `.other(String)`.

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/NodeInfo/InstanceSoftwareTests.swift
import Testing
@testable import SpudDataKit

struct InstanceSoftwareTests {
    @Test func mapsKnownNamesCaseInsensitively() {
        #expect(InstanceSoftware(softwareName: "lemmy") == .lemmy)
        #expect(InstanceSoftware(softwareName: "PieFed") == .piefed)
        #expect(InstanceSoftware(softwareName: "MBIN") == .mbin)
        #expect(InstanceSoftware(softwareName: "mastodon") == .mastodon)
    }

    @Test func preservesUnknownNameVerbatim() {
        #expect(InstanceSoftware(softwareName: "sublinks") == .other("sublinks"))
        #expect(InstanceSoftware(softwareName: "") == .other(""))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `Cannot find 'InstanceSoftware' in scope`.

- [ ] **Step 3: Delete the dead enum and write the implementation**

Delete `SpudDataKit/Utils/NodeInfoSoftware.swift`, then create:

```swift
// SpudDataKit/Services/NodeInfo/InstanceSoftware.swift
import Foundation

/// The federated-social software a host runs, as reported by its NodeInfo
/// `software.name`. Recognition is a strong hint, not gospel: forks report
/// their own name and surface as `.other(name)`, which is a first-class,
/// handled outcome — not an error.
public enum InstanceSoftware: Sendable, Equatable {
    case lemmy, piefed, mbin, kbin, mastodon, misskey, pleroma, peertube, friendica, gotosocial
    /// Recognized NodeInfo but an unmodelled software name, preserved verbatim.
    case other(String)

    /// Maps a raw NodeInfo `software.name` (case-insensitive) to a known case,
    /// falling through to `.other` with the original string.
    public init(softwareName: String) {
        switch softwareName.lowercased() {
        case "lemmy": self = .lemmy
        case "piefed": self = .piefed
        case "mbin": self = .mbin
        case "kbin": self = .kbin
        case "mastodon": self = .mastodon
        case "misskey": self = .misskey
        case "pleroma": self = .pleroma
        case "peertube": self = .peertube
        case "friendica": self = .friendica
        case "gotosocial": self = .gotosocial
        default: self = .other(softwareName)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS — `✔ Test run with ... tests ... passed`.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/InstanceSoftware.swift SpudDataKitTests/NodeInfo/InstanceSoftwareTests.swift
git add SpudDataKit/Services/NodeInfo/InstanceSoftware.swift SpudDataKitTests/NodeInfo/InstanceSoftwareTests.swift
git rm SpudDataKit/Utils/NodeInfoSoftware.swift
git commit -m "feat: InstanceSoftware enum mapping NodeInfo software.name"
```

---

### Task 2: `NodeInfoCacheRecord` + `v30_nodeInfoCache` migration

A dedicated host-keyed cache table (the legacy `NodeInfoRecord` is instance-scoped and stays untouched).

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/NodeInfoCacheRecord.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append a new migration after `v29_ephemeralAccountAndSiteGiveUp`)
- Test: `SpudDataKitTests/NodeInfo/NodeInfoCacheRecordTests.swift`

**Interfaces:**
- Produces: `struct NodeInfoCacheRecord` with `host: String`, `softwareName: String`, `softwareVersion: String?`, `fetchedAt: Date`; `databaseTableName = "nodeInfoCache"`; conforms `Codable, Sendable, Equatable, FetchableRecord, PersistableRecord`. `host` is the primary key (upsert by host).

- [ ] **Step 1: Confirm the latest migration id**

Run: `grep -n registerMigration SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift | tail -1`
Expected: the last line is `v29_ephemeralAccountAndSiteGiveUp`. If a higher `vNN` now exists, use the next integer instead of `v30` throughout this task.

- [ ] **Step 2: Write the failing test**

```swift
// SpudDataKitTests/NodeInfo/NodeInfoCacheRecordTests.swift
import Foundation
import Testing
import GRDB
@testable import SpudDataKit

struct NodeInfoCacheRecordTests {
    @Test func upsertsAndFetchesByHost() async throws {
        let appDatabase = AppDatabase.inMemory()
        try await appDatabase.writer.write { db in
            var record = NodeInfoCacheRecord(
                host: "lemmy.world", softwareName: "lemmy",
                softwareVersion: "0.19.5", fetchedAt: Date(timeIntervalSince1970: 1_000)
            )
            try record.upsert(db)
            // Upsert on the same host replaces, not duplicates.
            var updated = record
            updated.softwareVersion = "0.19.6"
            try updated.upsert(db)
        }
        let rows = try await appDatabase.writer.read { db in
            try NodeInfoCacheRecord.fetchAll(db)
        }
        #expect(rows.count == 1)
        #expect(rows.first?.softwareVersion == "0.19.6")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `Cannot find 'NodeInfoCacheRecord' in scope`.

- [ ] **Step 4: Write the record**

```swift
// SpudDataKit/Services/NodeInfo/NodeInfoCacheRecord.swift
import Foundation
import GRDB

/// Host-keyed cache of a NodeInfo probe result. Distinct from the legacy
/// instance-scoped `NodeInfoRecord`: this row exists before any `instance`
/// row does, so a pre-flight can probe a host the user has not committed to.
/// `fetchedAt` drives the TTL; a stale row is refreshed on the next probe.
struct NodeInfoCacheRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nodeInfoCache"

    /// Normalized host (lowercased, no scheme/path). Primary key.
    var host: String
    /// Raw NodeInfo `software.name` (mapped to `InstanceSoftware` at read time).
    var softwareName: String
    /// Raw NodeInfo `software.version`, if advertised.
    var softwareVersion: String?
    var fetchedAt: Date
}
```

- [ ] **Step 5: Append the migration**

In `AppDatabase+Migrations.swift`, immediately after the `v29_ephemeralAccountAndSiteGiveUp` registration block, add:

```swift
migrator.registerMigration("v30_nodeInfoCache") { db in
    try db.create(table: "nodeInfoCache") { t in
        t.primaryKey("host", .text)
        t.column("softwareName", .text).notNull()
        t.column("softwareVersion", .text)
        t.column("fetchedAt", .datetime).notNull()
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 7: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/NodeInfoCacheRecord.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/NodeInfo/NodeInfoCacheRecordTests.swift
git add SpudDataKit/Services/NodeInfo/NodeInfoCacheRecord.swift SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift SpudDataKitTests/NodeInfo/NodeInfoCacheRecordTests.swift
git commit -m "feat: v30_nodeInfoCache host-keyed NodeInfo cache table"
```

---

### Task 3: `NodeInfoService` actor (fetch seam, timeout, cache, TTL)

The detection engine, tested end-to-end with a fake fetcher (no network).

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/NodeInfoDetection.swift`
- Create: `SpudDataKit/Services/NodeInfo/NodeInfoFetching.swift`
- Create: `SpudDataKit/Services/NodeInfo/NodeInfoService.swift`
- Test: `SpudDataKitTests/NodeInfo/NodeInfoServiceTests.swift`

**Interfaces:**
- Consumes: `InstanceSoftware` (Task 1), `NodeInfoCacheRecord` + `AppDatabase.inMemory()` (Task 2).
- Produces:
  - `public enum NodeInfoDetection: Sendable, Equatable { case known(InstanceSoftware, version: String?); case unknown }`
  - `public protocol NodeInfoFetching: Sendable { func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) }`
  - `public protocol NodeInfoServiceType: Sendable { func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection }` with a default-`maxAge` convenience overload.
  - `public actor NodeInfoService: NodeInfoServiceType` with `public init(fetcher: NodeInfoFetching, appDatabase: AppDatabase, timeout: TimeInterval = 4)`.
  - `public protocol HasNodeInfoService { var nodeInfoService: NodeInfoServiceType { get } }`.

- [ ] **Step 1: Write the failing tests**

```swift
// SpudDataKitTests/NodeInfo/NodeInfoServiceTests.swift
import Foundation
import Testing
@testable import SpudDataKit

private actor CallCounter { var count = 0; func bump() { count += 1 } }

private struct FakeFetcher: NodeInfoFetching {
    let result: Result<(softwareName: String, softwareVersion: String?), Error>
    let counter: CallCounter?
    let sleepSeconds: Double?
    init(_ result: Result<(softwareName: String, softwareVersion: String?), Error>,
         counter: CallCounter? = nil, sleepSeconds: Double? = nil) {
        self.result = result; self.counter = counter; self.sleepSeconds = sleepSeconds
    }
    func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) {
        await counter?.bump()
        if let sleepSeconds { try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000)) }
        return try result.get()
    }
}

private struct FetchBoom: Error {}

struct NodeInfoServiceTests {
    @Test func detectsAndCachesOnSuccess() async {
        let service = NodeInfoService(
            fetcher: FakeFetcher(.success(("lemmy", "0.19.5"))),
            appDatabase: .inMemory()
        )
        let result = await service.detect(host: "Lemmy.World")
        #expect(result == .known(.lemmy, version: "0.19.5"))
    }

    @Test func freshCacheHitDoesNotRefetch() async {
        let counter = CallCounter()
        let service = NodeInfoService(
            fetcher: FakeFetcher(.success(("piefed", "1.0")), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.detect(host: "piefed.social")
        _ = await service.detect(host: "piefed.social")
        #expect(await counter.count == 1)
    }

    @Test func staleCacheRefetches() async {
        let counter = CallCounter()
        let service = NodeInfoService(
            fetcher: FakeFetcher(.success(("lemmy", "0.19.5")), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.detect(host: "a.example", maxAge: 3600)
        // maxAge 0 forces the existing row to count as stale.
        _ = await service.detect(host: "a.example", maxAge: 0)
        #expect(await counter.count == 2)
    }

    @Test func fetchErrorYieldsUnknown() async {
        let service = NodeInfoService(
            fetcher: FakeFetcher(.failure(FetchBoom())),
            appDatabase: .inMemory()
        )
        #expect(await service.detect(host: "blocked.example") == .unknown)
    }

    @Test func timeoutYieldsUnknown() async {
        let service = NodeInfoService(
            fetcher: FakeFetcher(.success(("lemmy", nil)), sleepSeconds: 10),
            appDatabase: .inMemory(),
            timeout: 0.05
        )
        #expect(await service.detect(host: "slow.example") == .unknown)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `Cannot find 'NodeInfoService' in scope`.

- [ ] **Step 3: Write the detection type and fetch seam**

```swift
// SpudDataKit/Services/NodeInfo/NodeInfoDetection.swift
import Foundation

/// Outcome of a NodeInfo probe. `.unknown` means "could not determine" —
/// NEVER "not Lemmy". Callers treat `.unknown` as fail-open.
public enum NodeInfoDetection: Sendable, Equatable {
    case known(InstanceSoftware, version: String?)
    case unknown
}
```

```swift
// SpudDataKit/Services/NodeInfo/NodeInfoFetching.swift
import Foundation

/// Seam over the NodeInfo network fetch so `NodeInfoService` can be tested
/// without a live host. The production conformer (`LiveNodeInfoFetcher`)
/// wraps the DiasporaNodeInfo package.
public protocol NodeInfoFetching: Sendable {
    /// Fetches `software.name` / `software.version` for `host`, or throws on
    /// any transport / discovery / decode failure.
    func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?)
}

private struct NodeInfoTimeoutError: Error {}

/// Runs `operation`, throwing `NodeInfoTimeoutError` if it exceeds `seconds`.
func withNodeInfoTimeout<T: Sendable>(
    seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NodeInfoTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 4: Write the service**

```swift
// SpudDataKit/Services/NodeInfo/NodeInfoService.swift
import Foundation
import GRDB
import os

/// Probes and caches an instance's software via NodeInfo. Probe only on
/// explicit engagement; results are cached with a multi-day TTL; every
/// failure (transport, WAF 403, decode, timeout) resolves to `.unknown`
/// and `detect` never throws.
public protocol NodeInfoServiceType: Sendable {
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection
}

public extension NodeInfoServiceType {
    /// Detects with the default 7-day TTL.
    func detect(host: String) async -> NodeInfoDetection {
        await detect(host: host, maxAge: 7 * 24 * 3600)
    }
}

public protocol HasNodeInfoService {
    var nodeInfoService: NodeInfoServiceType { get }
}

public actor NodeInfoService: NodeInfoServiceType {
    private let fetcher: NodeInfoFetching
    private let appDatabase: AppDatabase
    private let timeout: TimeInterval
    private let logger = Logger(subsystem: "info.ddenis.Spud", category: "NodeInfoService")

    public init(fetcher: NodeInfoFetching, appDatabase: AppDatabase, timeout: TimeInterval = 4) {
        self.fetcher = fetcher
        self.appDatabase = appDatabase
        self.timeout = timeout
    }

    public func detect(host rawHost: String, maxAge: TimeInterval) async -> NodeInfoDetection {
        let host = Self.normalize(rawHost)
        guard !host.isEmpty else { return .unknown }

        if let row = try? await appDatabase.writer.read({ db in
            try NodeInfoCacheRecord.filter(key: host).fetchOne(db)
        }), Date().timeIntervalSince(row.fetchedAt) < maxAge {
            return .known(InstanceSoftware(softwareName: row.softwareName), version: row.softwareVersion)
        }

        do {
            let (name, version) = try await withNodeInfoTimeout(seconds: timeout) { [fetcher] in
                try await fetcher.fetch(host: host)
            }
            try? await appDatabase.writer.write { db in
                var record = NodeInfoCacheRecord(
                    host: host, softwareName: name, softwareVersion: version, fetchedAt: Date()
                )
                try record.upsert(db)
            }
            return .known(InstanceSoftware(softwareName: name), version: version)
        } catch {
            logger.debug("NodeInfo probe failed for \(host, privacy: .public): \(error, privacy: .public)")
            return .unknown
        }
    }

    /// Lowercases and strips any scheme/path so a bare host is the cache key.
    static func normalize(_ raw: String) -> String {
        var value = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = value.range(of: "://") { value = String(value[range.upperBound...]) }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        return value
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS (all five NodeInfoServiceTests green).

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/ SpudDataKitTests/NodeInfo/NodeInfoServiceTests.swift
git add SpudDataKit/Services/NodeInfo/NodeInfoDetection.swift SpudDataKit/Services/NodeInfo/NodeInfoFetching.swift SpudDataKit/Services/NodeInfo/NodeInfoService.swift SpudDataKitTests/NodeInfo/NodeInfoServiceTests.swift
git commit -m "feat: NodeInfoService actor with fetch seam, timeout, and TTL cache"
```

---

### Task 4: `PlatformProfile` capability descriptor

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/PlatformProfile.swift`
- Test: `SpudDataKitTests/NodeInfo/PlatformProfileTests.swift`

**Interfaces:**
- Consumes: `InstanceSoftware` (Task 1).
- Produces: `public struct PlatformProfile: Sendable, Equatable` with `software`, `version`, `displayName`, `speaksLemmyAPI`, computed `canBeHomeConnection`, and `static func profile(for:version:) -> PlatformProfile`.

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/NodeInfo/PlatformProfileTests.swift
import Testing
@testable import SpudDataKit

struct PlatformProfileTests {
    @Test func lemmyIsAHomeConnection() {
        let p = PlatformProfile.profile(for: .lemmy, version: "0.19.5")
        #expect(p.speaksLemmyAPI)
        #expect(p.canBeHomeConnection)
        #expect(p.displayName == "Lemmy")
    }

    @Test func nonLemmyIsNotAHomeConnection() {
        #expect(!PlatformProfile.profile(for: .piefed).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .mastodon).canBeHomeConnection)
        #expect(!PlatformProfile.profile(for: .other("sublinks")).canBeHomeConnection)
    }

    @Test func displayNameForUnknownIsRawName() {
        #expect(PlatformProfile.profile(for: .other("sublinks")).displayName == "sublinks")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `Cannot find 'PlatformProfile' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// SpudDataKit/Services/NodeInfo/PlatformProfile.swift
import Foundation

/// What Spud can do with an instance running a given `InstanceSoftware`.
/// Pure lookup, no I/O. In v1 only Lemmy speaks the API Spud uses.
public struct PlatformProfile: Sendable, Equatable {
    public let software: InstanceSoftware
    public let version: String?
    /// Human-facing name for messages and badges.
    public let displayName: String
    /// Whether Spud's LemmyService can talk to this software. v1: only `.lemmy`.
    public let speaksLemmyAPI: Bool

    /// Whether this instance can be a Spud home connection (login / signed-out browse).
    public var canBeHomeConnection: Bool { speaksLemmyAPI }

    public static func profile(for software: InstanceSoftware, version: String? = nil) -> PlatformProfile {
        PlatformProfile(
            software: software,
            version: version,
            displayName: Self.displayName(for: software),
            speaksLemmyAPI: software == .lemmy
        )
    }

    private static func displayName(for software: InstanceSoftware) -> String {
        switch software {
        case .lemmy: "Lemmy"
        case .piefed: "PieFed"
        case .mbin: "Mbin"
        case .kbin: "/kbin"
        case .mastodon: "Mastodon"
        case .misskey: "Misskey"
        case .pleroma: "Pleroma"
        case .peertube: "PeerTube"
        case .friendica: "Friendica"
        case .gotosocial: "GoToSocial"
        case let .other(name): name
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/PlatformProfile.swift SpudDataKitTests/NodeInfo/PlatformProfileTests.swift
git add SpudDataKit/Services/NodeInfo/PlatformProfile.swift SpudDataKitTests/NodeInfo/PlatformProfileTests.swift
git commit -m "feat: PlatformProfile capability descriptor"
```

---

### Task 5: `PlatformRouter` + `PlatformUnsupportedError`

**Files:**
- Create: `SpudDataKit/Services/NodeInfo/PlatformRouter.swift`
- Test: `SpudDataKitTests/NodeInfo/PlatformRouterTests.swift`

**Interfaces:**
- Consumes: `NodeInfoServiceType` + `NodeInfoDetection` (Task 3), `PlatformProfile` (Task 4).
- Produces:
  - `public struct PlatformRouter: Sendable` with `init(nodeInfoService:)` and `func evaluateHomeConnection(host:) async -> HomeConnectionDecision`.
  - `public enum HomeConnectionDecision: Sendable, Equatable { case allow; case block(software: InstanceSoftware, displayName: String, version: String?) }`
  - `public struct PlatformUnsupportedError: Error, Equatable, Sendable` with `software`, `displayName`, `version`, `host`.

- [ ] **Step 1: Write the failing test**

```swift
// SpudDataKitTests/NodeInfo/PlatformRouterTests.swift
import Foundation
import Testing
@testable import SpudDataKit

private struct StubNodeInfoService: NodeInfoServiceType {
    let detection: NodeInfoDetection
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection { detection }
}

struct PlatformRouterTests {
    @Test func lemmyAllows() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.lemmy, version: "0.19.5")))
        #expect(await router.evaluateHomeConnection(host: "lemmy.world") == .allow)
    }

    @Test func nonLemmyBlocks() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .known(.piefed, version: "1.0")))
        #expect(await router.evaluateHomeConnection(host: "piefed.social")
            == .block(software: .piefed, displayName: "PieFed", version: "1.0"))
    }

    @Test func unknownAllowsFailOpen() async {
        let router = PlatformRouter(nodeInfoService: StubNodeInfoService(detection: .unknown))
        #expect(await router.evaluateHomeConnection(host: "waf.example") == .allow)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `Cannot find 'PlatformRouter' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// SpudDataKit/Services/NodeInfo/PlatformRouter.swift
import Foundation

/// Decides whether a host may become a Spud home connection, based on its
/// detected software. Detected-non-Lemmy blocks; could-not-detect never blocks.
public struct PlatformRouter: Sendable {
    public enum HomeConnectionDecision: Sendable, Equatable {
        case allow
        case block(software: InstanceSoftware, displayName: String, version: String?)
    }

    private let nodeInfoService: NodeInfoServiceType

    public init(nodeInfoService: NodeInfoServiceType) {
        self.nodeInfoService = nodeInfoService
    }

    public func evaluateHomeConnection(host: String) async -> HomeConnectionDecision {
        switch await nodeInfoService.detect(host: host) {
        case let .known(software, version):
            let profile = PlatformProfile.profile(for: software, version: version)
            return profile.canBeHomeConnection
                ? .allow
                : .block(software: software, displayName: profile.displayName, version: version)
        case .unknown:
            // Fail-open: a WAF-403'd healthy Lemmy instance must still work.
            return .allow
        }
    }
}

/// Thrown by `AccountService` when a home connection targets non-Lemmy software.
public struct PlatformUnsupportedError: Error, Equatable, Sendable {
    public let software: InstanceSoftware
    public let displayName: String
    public let version: String?
    public let host: String

    public init(software: InstanceSoftware, displayName: String, version: String?, host: String) {
        self.software = software
        self.displayName = displayName
        self.version = version
        self.host = host
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/PlatformRouter.swift SpudDataKitTests/NodeInfo/PlatformRouterTests.swift
git add SpudDataKit/Services/NodeInfo/PlatformRouter.swift SpudDataKitTests/NodeInfo/PlatformRouterTests.swift
git commit -m "feat: PlatformRouter home-connection decision + PlatformUnsupportedError"
```

---

### Task 6: DiasporaNodeInfo SPM pin + `LiveNodeInfoFetcher`

**PREREQUISITE (denis):** a git tag for DiasporaNodeInfo must exist to pin. Confirm/cut it before this task.

**Files:**
- Modify: `project.yml` (add the `DiasporaNodeInfo` package + link it to the `SpudDataKit` target, mirroring the existing `LemmyKit` entries)
- Create: `SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift`

**Interfaces:**
- Consumes: `NodeInfoFetching` (Task 3), the `DiasporaNodeInfo` package (`NodeInfoManager`, `NodeInfo`).
- Produces: `public struct LiveNodeInfoFetcher: NodeInfoFetching` with `public init()`.

- [ ] **Step 1: Get the package remote URL and confirm the tag**

Run: `git -C ../DiasporaNodeInfo remote get-url origin && git -C ../DiasporaNodeInfo tag --list | tail -5`
Note the URL and the tag to pin (e.g. `1.4.0`). If no suitable tag exists, STOP — denis must cut one first.

- [ ] **Step 2: Add the package to `project.yml`**

Under the top-level `packages:` map, add (using the URL + tag from Step 1, mirroring the `LemmyKit` entry's style):

```yaml
  DiasporaNodeInfo:
    url: <DiasporaNodeInfo remote URL from Step 1>
    exactVersion: <tag from Step 1>
```

Then, in the `SpudDataKit` target's `dependencies:` list, add:

```yaml
    - package: DiasporaNodeInfo
```

- [ ] **Step 3: Regenerate and resolve**

Run:
```bash
make project
xcodebuild -resolvePackageDependencies -project Spud.xcodeproj
```
Expected: resolves `DiasporaNodeInfo` at the pinned tag with no error.

- [ ] **Step 4: Write the live fetcher**

```swift
// SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift
import DiasporaNodeInfo
import Foundation

/// Production `NodeInfoFetching` backed by the DiasporaNodeInfo package.
/// Coalesces the version-specific software projections locally (no dependency
/// on a version-agnostic accessor in the package).
public struct LiveNodeInfoFetcher: NodeInfoFetching {
    struct MissingSoftwareName: Error {}

    public init() {}

    public func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) {
        let info = try await NodeInfoManager().fetch(for: host)
        let name = info.v2_1?.software.name ?? info.v2_0?.software.name ?? ""
        let version = info.v2_1?.software.version ?? info.v2_0?.software.version
        guard !name.isEmpty else { throw MissingSoftwareName() }
        return (name, version)
    }
}
```

- [ ] **Step 5: Verify the target builds**

Run: `make build`
Expected: build succeeds (SpudDataKit compiles with `import DiasporaNodeInfo`).

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift
git add project.yml SpudDataKit/Services/NodeInfo/LiveNodeInfoFetcher.swift
git commit -m "chore: pin DiasporaNodeInfo package + LiveNodeInfoFetcher"
```

---

### Task 7: AccountService pre-flight + DI wiring

Guard `login` and `register` inside `AccountService`, and construct/inject `NodeInfoService` in the app DI graph. `signInAsSignedOut` is intentionally NOT guarded (it is sync and the first-launch bootstrap path).

**Files:**
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (init gains an optional `nodeInfoService`; add `preflightHomeConnection`; call it in `login` and `register`)
- Modify: `Spud/App/DependencyContainer.swift` (conform `HasNodeInfoService`; construct `nodeInfoService` before `accountService`; pass it into `AccountService`)
- Test: `SpudDataKitTests/NodeInfo/AccountServicePreflightTests.swift`

**Interfaces:**
- Consumes: `NodeInfoServiceType`, `PlatformRouter`, `PlatformUnsupportedError` (Tasks 3, 5), `LiveNodeInfoFetcher` (Task 6).
- Produces: `AccountService.init(appDatabase:reachabilityMonitor:nodeInfoService:)` (new optional trailing param, default `nil`); `DependencyContainer.nodeInfoService: NodeInfoServiceType`.

- [ ] **Step 1: Write the failing test**

This test exercises the pre-flight decision path directly via a small helper the implementation will expose. Add an `internal` test seam on `AccountService`.

```swift
// SpudDataKitTests/NodeInfo/AccountServicePreflightTests.swift
import Foundation
import Testing
@testable import SpudDataKit

private struct StubNodeInfoService: NodeInfoServiceType {
    let detection: NodeInfoDetection
    func detect(host: String, maxAge: TimeInterval) async -> NodeInfoDetection { detection }
}

@MainActor
struct AccountServicePreflightTests {
    private func makeService(_ detection: NodeInfoDetection) -> AccountService {
        AccountService(
            appDatabase: .inMemory(),
            reachabilityMonitor: ReachabilityMonitor(),
            nodeInfoService: StubNodeInfoService(detection: detection)
        )
    }

    @Test func blocksNonLemmyHost() async {
        let service = makeService(.known(.piefed, version: "1.0"))
        await #expect(throws: PlatformUnsupportedError.self) {
            try await service.preflightHomeConnection(host: "piefed.social")
        }
    }

    @Test func allowsLemmyHost() async throws {
        let service = makeService(.known(.lemmy, version: "0.19.5"))
        try await service.preflightHomeConnection(host: "lemmy.world")
    }

    @Test func allowsUnknownHostFailOpen() async throws {
        let service = makeService(.unknown)
        try await service.preflightHomeConnection(host: "waf.example")
    }
}
```

Note: confirm the exact `ReachabilityMonitor()` init in `AccountService`'s existing tests; if it requires arguments, mirror those tests' construction.

- [ ] **Step 2: Run test to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `value of type 'AccountService' has no member 'preflightHomeConnection'` and the new init param is unknown.

- [ ] **Step 3: Add the pre-flight to `AccountService`**

In `AccountService.swift`: add a stored optional router built from the injected service, the pre-flight helper, and the init param. Add the `nodeInfoService` parameter to the existing `init` (default `nil` so the widget/other callers are unaffected), and set:

```swift
// Stored property (near the other stored deps):
private let platformRouter: PlatformRouter?

// In init(...) — add the parameter and initialize the router:
//   public init(appDatabase: AppDatabase, reachabilityMonitor: ReachabilityMonitoring,
//               nodeInfoService: NodeInfoServiceType? = nil) {
//       ...existing assignments...
self.platformRouter = nodeInfoService.map { PlatformRouter(nodeInfoService: $0) }
//   }

/// Blocks a home connection to non-Lemmy software; fail-open when the router
/// is absent or the software could not be determined.
func preflightHomeConnection(host: String) async throws {
    guard let platformRouter else { return }
    if case let .block(software, displayName, version) = await platformRouter.evaluateHomeConnection(host: host) {
        throw PlatformUnsupportedError(software: software, displayName: displayName, version: version, host: host)
    }
}
```

Then call it at the top of `login` and `register`, immediately after the `guard let url = instance.url` line (before `makeApi`):

```swift
try await preflightHomeConnection(host: instance.host)
```

- [ ] **Step 4: Wire the DI graph**

In `Spud/App/DependencyContainer.swift`:
1. Add `HasNodeInfoService` to the struct's conformance list.
2. Add the stored property: `let nodeInfoService: NodeInfoServiceType`.
3. In `init(arguments:)`, construct it BEFORE `accountService`, and pass it in:

```swift
nodeInfoService = NodeInfoService(fetcher: LiveNodeInfoFetcher(), appDatabase: appDatabase)
accountService = AccountService(
    appDatabase: appDatabase,
    reachabilityMonitor: reachabilityMonitor,
    nodeInfoService: nodeInfoService
)
```

(`nodeInfoService` needs only `appDatabase`, which is assigned just above `accountService` today — keep that order.)

- [ ] **Step 5: Run tests + build**

Run: `make project && make test-only ONLY=SpudDataKitTests && make build`
Expected: pre-flight tests PASS; app builds (DependencyContainer conforms).

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/Account/AccountService.swift Spud/App/DependencyContainer.swift SpudDataKitTests/NodeInfo/AccountServicePreflightTests.swift
git add SpudDataKit/Services/Account/AccountService.swift Spud/App/DependencyContainer.swift SpudDataKitTests/NodeInfo/AccountServicePreflightTests.swift
git commit -m "feat: block non-Lemmy home connections in AccountService login/register"
```

---

### Task 8: Login block sheet

Surface `PlatformUnsupportedError` from `LoginViewModel` and present a two-button sheet from `LoginViewController`.

**Files:**
- Modify: `Spud/Scenes/Account/Login/LoginViewModel.swift` (catch `PlatformUnsupportedError` → `blockedPlatform` observable)
- Modify: `Spud/Scenes/Account/Login/LoginViewController.swift` (observe `blockedPlatform`, present the sheet)
- Test: `SpudTests/Login/LoginViewModelBlockTests.swift` (only if `LoginViewModel` is constructible with injectable deps in the existing test suite; otherwise verify by build + manual)

**Interfaces:**
- Consumes: `PlatformUnsupportedError` (Task 5), the pre-flight from Task 7 (thrown through `accountService.login`).
- Produces: `LoginViewModel.blockedPlatform: PlatformUnsupportedError?`.

- [ ] **Step 1: Add the observable + catch branch to `LoginViewModel`**

Add an observable property near `loginError`:

```swift
/// Set when the target instance runs non-Lemmy software; drives a block sheet.
var blockedPlatform: PlatformUnsupportedError?
```

In `login()`, add a typed catch BEFORE the existing generic `catch` (currently at ~L131):

```swift
} catch let error as PlatformUnsupportedError {
    blockedPlatform = error
} catch AccountServiceLoginError.totp2faRequired {
    // ...existing...
```

- [ ] **Step 2: Present the sheet from `LoginViewController`**

Alongside the existing `loginError` observation (~L462), add:

```swift
observationTasks.append(Task { @MainActor [weak self, viewModel] in
    for await blocked in ObservationStream.values(of: { viewModel.blockedPlatform }) {
        guard let self, let blocked else { continue }
        self.presentPlatformBlockedSheet(blocked)
    }
})
```

And add the presenter method (mirrors the existing `UIAlertController(.actionSheet)` + iPad popover pattern used in `PostDetailViewController`):

```swift
private func presentPlatformBlockedSheet(_ blocked: PlatformUnsupportedError) {
    let title = String(
        format: NSLocalizedString("%@ isn't supported yet", comment: "Block sheet title; %@ is software name like PieFed"),
        blocked.displayName
    )
    let message = String(
        format: NSLocalizedString("%1$@ runs %2$@. Spud can only connect to Lemmy instances right now.",
                                  comment: "Block sheet body; %1$@ host, %2$@ software name"),
        blocked.host, blocked.displayName
    )
    let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
    if let url = URL(string: "https://\(blocked.host)") {
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Open in Safari", comment: "Block sheet: open the instance in the browser"),
            style: .default
        ) { _ in UIApplication.shared.open(url) })
    }
    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
    if let popover = alert.popoverPresentationController {
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    present(alert, animated: true)
}
```

- [ ] **Step 3: Write the view-model test (if constructible), else build-verify**

If the existing suite constructs `LoginViewModel` with fakes, add a test injecting a fake `accountService` whose `login` throws `PlatformUnsupportedError` and assert `blockedPlatform != nil`. Otherwise skip the unit test and rely on Step 4 + manual verification, and note that in the commit body.

- [ ] **Step 4: Build + manual verify**

Run: `make build`
Manual (sim): attempt to log into a known non-Lemmy host and confirm the sheet appears with the software name and an "Open in Safari" action. (idb tap automation is dead here; drive by hand or via the XCUITest in the optional follow-up.)

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/Account/Login/LoginViewModel.swift Spud/Scenes/Account/Login/LoginViewController.swift
git add Spud/Scenes/Account/Login/LoginViewModel.swift Spud/Scenes/Account/Login/LoginViewController.swift
git commit -m "feat: present block sheet on non-Lemmy login"
```

---

### Task 9: Register block sheet

Same treatment for the register flow.

**Files:**
- Modify: `Spud/Scenes/Account/Register/RegisterViewModel.swift` (catch `PlatformUnsupportedError` → `blockedPlatform`)
- Modify: `Spud/Scenes/Account/Register/RegisterViewController.swift` (observe + present the same style of sheet)

**Interfaces:**
- Consumes: `PlatformUnsupportedError` (Task 5), thrown through `accountService.register`.
- Produces: `RegisterViewModel.blockedPlatform: PlatformUnsupportedError?`.

- [ ] **Step 1: Add the observable + catch to `RegisterViewModel`**

Add near `outcomeMessage`:

```swift
var blockedPlatform: PlatformUnsupportedError?
```

In `register()`, add a typed catch BEFORE the `catch let error as AccountServiceRegisterError` branch (~L138):

```swift
} catch let error as PlatformUnsupportedError {
    blockedPlatform = error
} catch let error as AccountServiceRegisterError {
    // ...existing...
```

- [ ] **Step 2: Present the sheet from `RegisterViewController`**

Add the identical `presentPlatformBlockedSheet(_:)` method (from Task 8, Step 2) and observe `viewModel.blockedPlatform` the same way, alongside the existing `outcomeMessage` observation.

- [ ] **Step 3: Build + manual verify**

Run: `make build`
Manual (sim): attempt to register on a non-Lemmy host; confirm the sheet appears.

- [ ] **Step 4: Format and commit**

```bash
mint run swiftformat Spud/Scenes/Account/Register/RegisterViewModel.swift Spud/Scenes/Account/Register/RegisterViewController.swift
git add Spud/Scenes/Account/Register/RegisterViewModel.swift Spud/Scenes/Account/Register/RegisterViewController.swift
git commit -m "feat: present block sheet on non-Lemmy register"
```

---

### Task 10: Instance-detail software badge

On the "before you commit" instance detail screen, probe NodeInfo on appear and show the detected software name.

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` (add `HasNodeInfoService` to `OwnDependencies`, a `nodeInfoService` accessor, a `softwareBadgeLabel`, and an async probe)

**Interfaces:**
- Consumes: `NodeInfoServiceType` + `NodeInfoDetection` (Task 3), `PlatformProfile` (Task 4). The VC is constructed with `dependencies: Dependencies`, and `DependencyContainer` already conforms to `HasNodeInfoService` (Task 7).

- [ ] **Step 1: Extend the VC's dependencies**

Change `OwnDependencies` (currently L20-23) to include the new protocol, and add an accessor:

```swift
typealias OwnDependencies =
    HasAccountService &
    HasAppDatabase &
    HasImageService &
    HasNodeInfoService

private var nodeInfoService: NodeInfoServiceType {
    dependencies.own.nodeInfoService
}
```

- [ ] **Step 2: Add the badge label near the identity stack**

Add a stored label:

```swift
/// Detected software name (e.g. "PieFed"), populated by a NodeInfo probe on appear.
private let softwareBadgeLabel = UILabel()
```

Configure it where the `hostLabel` is built (~L207) and append it into the `identity` stack (~L210) after `hostLabel`:

```swift
softwareBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
softwareBadgeLabel.textColor = .secondaryLabel
softwareBadgeLabel.isHidden = true
// change the identity stack to: UIStackView(arrangedSubviews: [nameLabel, hostLabel, softwareBadgeLabel])
```

- [ ] **Step 3: Probe on appear and populate the badge**

In `viewDidLoad` (after layout is built), append an observation/probe task:

```swift
observationTasks.append(Task { @MainActor [weak self] in
    guard let self else { return }
    let host = self.record.baseurl
    if case let .known(software, version) = await self.nodeInfoService.detect(host: host) {
        let profile = PlatformProfile.profile(for: software, version: version)
        self.softwareBadgeLabel.text = profile.displayName
        self.softwareBadgeLabel.isHidden = false
    }
})
```

(On `.unknown` the badge stays hidden — no error state.)

- [ ] **Step 4: Update snapshot-test construction sites**

Run: `grep -rn "InstanceDetailViewController(" --include="*.swift" SpudSnapshotTests SpudUITests`
Any test that constructs the VC with a `dependencies` double must supply a `nodeInfoService`. If the test double is a shared fake container, add a `nodeInfoService` returning a stub (a `StubNodeInfoService` returning `.unknown` keeps existing snapshots byte-identical since the badge stays hidden). Show the exact edit for each hit found.

- [ ] **Step 5: Build + verify snapshots unchanged**

Run: `make build && make snapshot`
Expected: build succeeds; existing InstanceDetail snapshots still pass (badge hidden under a `.unknown` stub). If the shared snapshot double returns a real `.known(.lemmy, …)`, re-record that one class per the snapshot workflow and stage only those refs.

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift
git add Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift
git commit -m "feat: show detected software name on instance detail"
```

---

### Task 11: Documentation

**Files:**
- Create: `docs/features/instance-software-detection.md`
- Modify: `docs/features/README.md` (capability table + "Feature coverage by area" map)

**Interfaces:** none (docs only).

- [ ] **Step 1: Write the feature doc**

Create `docs/features/instance-software-detection.md` following the `_TEMPLATE.md` convention (no `.swift` links; accurate `Status:`; `Surfaces:` = union of scenario tags). Cover the rules and these Given/When/Then scenarios:
- Given a user logs into a host running PieFed, When the pre-flight probes NodeInfo, Then login is blocked with "PieFed isn't supported yet" and an Open-in-Safari option.
- Given a host running Lemmy, When the pre-flight runs, Then login proceeds normally.
- Given a host whose NodeInfo probe fails or is blocked by a WAF, When the pre-flight runs, Then login proceeds (fail-open) exactly as before.
- Given a user opens an instance's detail screen, When NodeInfo is detected, Then the detected software name is shown; when undetermined, no badge is shown.
- Note the privacy rule: probes happen only on explicit engagement (login/register/instance-detail), never during feed browsing.

- [ ] **Step 2: Update the README index**

Add a row to the capability table and an entry to the "Feature coverage by area" map in `docs/features/README.md` for instance software detection.

- [ ] **Step 3: Commit**

```bash
git add docs/features/instance-software-detection.md docs/features/README.md
git commit -m "docs: instance software detection feature doc"
```

---

## Deferred (decide separately — see spec §Integration 3)

- **Bare-instance link signpost.** The originally-approved tap-fallback insertion (`InternalLinkRouting` L79) is shared with all external links, so probing there would hit arbitrary websites (violates the privacy boundary). Better-scoped candidate: the Search paste-to-open path (`SearchURLDetector`). Not in this plan.
- **Optional XCUITest** for the block sheet (stub `/.well-known/nodeinfo` + `/nodeinfo/2.1` to a PieFed payload via SBTUITestTunnel; assert the sheet appears). Valuable but "should, not must."
- **`signInAsSignedOut` / signed-out "visit instance" guarding.** Excluded from v1 (sync bootstrap path).

## Self-Review

- **Spec coverage:** detection layer (Tasks 1-3, 6), capability seam (Tasks 4-5), home-connection pre-flight (Task 7), block sheet (Tasks 8-9), instance-detail badge (Task 10), cache/migration (Task 2), testing (Tasks 1-7 unit; 8-10 build/manual), docs (Task 11), dependency changes (Task 6). Bare-instance signpost intentionally deferred (documented). All spec sections mapped.
- **Type consistency:** `InstanceSoftware`, `NodeInfoDetection` (`.known`/`.unknown`), `NodeInfoServiceType.detect(host:maxAge:)`, `PlatformProfile.profile(for:version:)`, `PlatformRouter.evaluateHomeConnection(host:)`, `HomeConnectionDecision.block(software:displayName:version:)`, `PlatformUnsupportedError(software:displayName:version:host:)`, `AccountService.preflightHomeConnection(host:)` — used consistently across tasks.
- **Placeholder scan:** the two "get the value" steps (package URL in Task 6, test-double sites in Task 10) are concrete discovery commands, not hand-waves; the code to add is shown.
