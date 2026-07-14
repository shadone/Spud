# Instance Meta Communities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect "meta" communities (communities about the instance itself, e.g. `tchncs@discuss.tchncs.de`), badge them wherever community lists appear, and surface the home instance's meta communities in an always-visible "About <instance>" section in the Communities tab with one-tap Subscribe / Favourite.

**Architecture:** A pure `MetaCommunityClassifier` (SpudUtilKit) decides meta-ness from name/title/host/site-name. A per-account cache (`InstanceMetaCommunityRecord` + a v38 migration) is populated by a `MetaCommunityService` (SpudDataKit) that resolves a fixed candidate-name list against an instance through a narrow `MetaCommunityResolving` seam. The classifier runs inline for badges (no cache); the cache powers the "About" section. Nothing is auto-subscribed or auto-favourited — the user taps.

**Tech Stack:** Swift 6, GRDB (persistence), Swift Testing (unit), swift-snapshot-testing (XCTest snapshots), SwiftUI + UIKit, XcodeGen (`make project`).

## Global Constraints

- **No emojis** in code, comments, or documentation.
- **Prefer many small, focused files** over large ones.
- **Suggest-only:** never auto-subscribe or auto-favourite. Every membership change is one explicit user tap.
- **No push-on-new-post.** Out of scope. "Subscribe" = the community joins the Subscribed feed; "Favourite" = a quick-access pin.
- **New Swift files** must be added to the project via `make project` (XcodeGen) before building; adding a `Has*` protocol to `DependencyContainer` cascades into VC `NestedDependencies` and every test double — rebuild all test targets after DI changes.
- **Never edit a shipped GRDB migration.** Add a new `migrator.registerMigration("vN_…")` block. Current highest is `v37_sessionNeedsReauth`; the next is **`v38_instanceMetaCommunity`**.
- **Migrations** live in `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift`, appended immediately before `return migrator`.
- **Every new file** starts with the standard 5-line BSD-2-Clause header (copy from any existing file in the same target).
- **Unit tests** are Swift Testing (`import Testing`, bare `struct` suite, `@Test func`, `#expect`/`#require`, no `test` prefix). Snapshot tests are XCTest. Add `import Foundation` when touching URL/Date; add `import GRDB` when calling `.insert`/`.fetchOne`.
- **Test commands:** `make test-only ONLY=SpudUtilKitTests`, `make test-only ONLY=SpudDataKitTests`, `make test-only ONLY=SpudTests`, `make snapshot`, `make build`.
- **Conventional commits;** small focused commits; end commit messages with the two trailers used elsewhere in this repo (`Co-Authored-By:` + `Claude-Session:`).
- **Document every change** under `docs/features/` with a per-capability doc AND the README index update (standing project discipline).

## File Structure

New files:
- `SpudUtilKit/MetaCommunity/MetaCommunityKeywords.swift` — strong/broad keyword sets.
- `SpudUtilKit/MetaCommunity/MetaCommunityClassifier.swift` — pure classifier + `MetaClassification`/`MetaConfidence`/`MetaReason`.
- `SpudUtilKitTests/MetaCommunityClassifierTests.swift` — classifier unit tests.
- `SpudDataKit/Services/AppDatabase/Records/InstanceMetaCommunityRecord.swift` — cache record.
- `SpudDataKit/Services/AppDatabase/InstanceMetaCommunityQueries.swift` — upsert / freshness / observe join + `MetaCommunityListItem`.
- `SpudDataKit/Services/MetaCommunity/MetaCommunityResolving.swift` — seam protocol + `ResolvedMetaCandidate` + candidate list.
- `SpudDataKit/Services/MetaCommunity/MetaCommunityService.swift` — service protocol + `Has*` + actor.
- `SpudDataKit/Services/MetaCommunity/LiveMetaCommunityResolver.swift` — live seam impl.
- `SpudDataKitTests/AppDatabase/InstanceMetaCommunityRecordTests.swift`
- `SpudDataKitTests/AppDatabase/InstanceMetaCommunityQueriesTests.swift`
- `SpudDataKitTests/MetaCommunity/MetaCommunityServiceTests.swift`
- `Spud/Scenes/Shared/MetaCommunityBadge.swift` — shared SwiftUI pill.
- `SpudSnapshotTests/MetaCommunityBadgeSnapshotTests.swift` (+ any section snapshot files).
- `docs/features/instance-meta-communities.md`

Modified files:
- `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` — v38 block.
- `Spud/App/DependencyContainer.swift` — register `metaCommunityService`.
- `Spud/Scenes/Discover/DiscoverView.swift` — badge in `DiscoverCommunityRow`.
- `Spud/Scenes/Subscriptions/SubscriptionsViewItemType.swift` — `isMeta` on `SubscriptionsCommunityRow`.
- `Spud/Scenes/Subscriptions/SubscriptionsView.swift` — badge on row + "About <instance>" Section.
- `Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift` — meta state, resolution trigger, subscribe/favourite actions.
- `Spud/Scenes/Subscriptions/SubscriptionsViewController.swift` — pass new VM args.
- `Spud/Scenes/Search/SearchResultCells.swift` — badge in `SearchCommunityCell`.
- `Spud/Scenes/Community/Content/CommunityHeaderView.swift` — meta pill.
- `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift` — meta section (optional Task 12).
- `docs/features/README.md` — index entry.

---

### Task 1: `MetaCommunityClassifier` (pure, SpudUtilKit)

**Files:**
- Create: `SpudUtilKit/MetaCommunity/MetaCommunityKeywords.swift`
- Create: `SpudUtilKit/MetaCommunity/MetaCommunityClassifier.swift`
- Test: `SpudUtilKitTests/MetaCommunityClassifierTests.swift`

**Interfaces:**
- Produces:
  - `enum MetaConfidence: String, Sendable, Equatable { case high, low }`
  - `enum MetaReason: String, Sendable, Equatable { case notMeta, nameMatchesInstance, strongKeyword, broadKeyword }`
  - `struct MetaClassification: Sendable, Equatable { let isMeta: Bool; let confidence: MetaConfidence; let reason: MetaReason; static let notMeta = MetaClassification(isMeta: false, confidence: .low, reason: .notMeta) }`
  - `enum MetaCommunityClassifier { static func classify(name: String, title: String?, instanceHost: String, siteName: String?) -> MetaClassification }`
  - `enum MetaCommunityKeywords { static let strong: Set<String>; static let broad: Set<String> }`

- [ ] **Step 1: Write the failing test**

Create `SpudUtilKitTests/MetaCommunityClassifierTests.swift` (copy the BSD header from an existing SpudUtilKitTests file):

```swift
import Testing
@testable import SpudUtilKit

struct MetaCommunityClassifierTests {
    @Test
    func nameMatchingInstanceDomainLabelIsHigh() {
        let c = MetaCommunityClassifier.classify(
            name: "tchncs", title: "tchncs", instanceHost: "discuss.tchncs.de", siteName: nil)
        #expect(c.isMeta)
        #expect(c.confidence == .high)
        #expect(c.reason == .nameMatchesInstance)
    }

    @Test
    func nameMatchingSiteNameIsHigh() {
        let c = MetaCommunityClassifier.classify(
            name: "lemmyworld", title: "Lemmy.World Meta", instanceHost: "lemmy.world", siteName: "Lemmy.World")
        #expect(c.isMeta)
        #expect(c.confidence == .high)
    }

    @Test
    func strongKeywordIsHigh() {
        for name in ["meta", "announcements", "changelog", "sitenews", "site", "instance"] {
            let c = MetaCommunityClassifier.classify(
                name: name, title: nil, instanceHost: "example.social", siteName: nil)
            #expect(c.isMeta, "\(name) should be meta")
            #expect(c.confidence == .high, "\(name) should be high")
            #expect(c.reason == .strongKeyword)
        }
    }

    @Test
    func broadKeywordIsLow() {
        for name in ["support", "help", "feedback", "news", "updates", "welcome", "general", "lounge", "rules"] {
            let c = MetaCommunityClassifier.classify(
                name: name, title: nil, instanceHost: "example.social", siteName: nil)
            #expect(c.isMeta, "\(name) should be meta")
            #expect(c.confidence == .low, "\(name) should be low")
            #expect(c.reason == .broadKeyword)
        }
    }

    @Test
    func multiWordTitleMatchesOnToken() {
        // Broad recall: any word token matching a keyword flags it.
        let c = MetaCommunityClassifier.classify(
            name: "general_discussion", title: "General Discussion", instanceHost: "example.social", siteName: nil)
        #expect(c.isMeta)
        #expect(c.confidence == .low)
    }

    @Test
    func ordinaryCommunityIsNotMeta() {
        let c = MetaCommunityClassifier.classify(
            name: "photography", title: "Photography", instanceHost: "lemmy.world", siteName: "Lemmy.World")
        #expect(!c.isMeta)
        #expect(c.reason == .notMeta)
    }

    @Test
    func domainLabelMatchIsEqualityNotSubstring() {
        // "world" is the TLD-adjacent label of lemmy.world; the primary label is
        // "lemmy". A community named "world" must NOT be flagged by the domain.
        let c = MetaCommunityClassifier.classify(
            name: "world", title: "World News", instanceHost: "lemmy.world", siteName: nil)
        #expect(!c.isMeta)
    }

    @Test
    func normalizationIgnoresCaseAndSeparators() {
        let c = MetaCommunityClassifier.classify(
            name: "Site-News", title: nil, instanceHost: "example.social", siteName: nil)
        #expect(c.isMeta)
        #expect(c.confidence == .high) // "sitenews" is strong
    }

    @Test
    func strongWinsOverBroadWhenBothPresent() {
        let c = MetaCommunityClassifier.classify(
            name: "meta", title: "Support & Meta", instanceHost: "example.social", siteName: nil)
        #expect(c.confidence == .high)
        #expect(c.reason == .strongKeyword)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudUtilKitTests`
Expected: FAIL — `MetaCommunityClassifier` / `MetaClassification` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `SpudUtilKit/MetaCommunity/MetaCommunityKeywords.swift` (with BSD header):

```swift
import Foundation

/// Keyword sets that mark a community as "meta" (about the instance itself).
///
/// Centralized so the lists are tunable in one place. `strong` keywords are
/// unambiguous instance-meta signals (high confidence); `broad` keywords catch
/// more real meta communities at the cost of mislabeling some ordinary ones
/// (low confidence) — an accepted trade because meta status is only ever
/// *suggested*, never auto-acted on.
public enum MetaCommunityKeywords {
    public static let strong: Set<String> = [
        "meta", "announcements", "announcement", "changelog", "sitenews",
        "site", "instance",
    ]

    public static let broad: Set<String> = [
        "support", "help", "feedback", "news", "updates", "admin", "welcome",
        "general", "lounge", "rules", "moderators", "mods",
    ]
}
```

Create `SpudUtilKit/MetaCommunity/MetaCommunityClassifier.swift` (with BSD header):

```swift
import Foundation

public enum MetaConfidence: String, Sendable, Equatable {
    case high
    case low
}

public enum MetaReason: String, Sendable, Equatable {
    case notMeta
    case nameMatchesInstance
    case strongKeyword
    case broadKeyword
}

public struct MetaClassification: Sendable, Equatable {
    public let isMeta: Bool
    public let confidence: MetaConfidence
    public let reason: MetaReason

    public init(isMeta: Bool, confidence: MetaConfidence, reason: MetaReason) {
        self.isMeta = isMeta
        self.confidence = confidence
        self.reason = reason
    }

    public static let notMeta = MetaClassification(
        isMeta: false, confidence: .low, reason: .notMeta)
}

/// Decides whether a community is "meta" for its own home instance. Pure: no
/// DB, no account, no I/O. Meta status is intrinsic to (name/title, home host,
/// that host's site name) and does not depend on the viewing account.
public enum MetaCommunityClassifier {
    public static func classify(
        name: String,
        title: String?,
        instanceHost: String,
        siteName: String?
    ) -> MetaClassification {
        // Normalized whole-strings (alphanumerics only, lowercased) used for
        // equality against the instance identity.
        let normalizedName = normalizeCollapsed(name)
        let normalizedTitle = title.map(normalizeCollapsed)

        // Word tokens (split on non-alphanumerics) used for keyword matching.
        var tokens = Set(wordTokens(name))
        if let title { tokens.formUnion(wordTokens(title)) }

        // High-confidence: name/title equals the instance identity.
        if matchesInstanceIdentity(
            normalizedName: normalizedName,
            normalizedTitle: normalizedTitle,
            tokens: tokens,
            instanceHost: instanceHost,
            siteName: siteName
        ) {
            return MetaClassification(
                isMeta: true, confidence: .high, reason: .nameMatchesInstance)
        }

        // High-confidence keyword wins over broad.
        if !tokens.isDisjoint(with: MetaCommunityKeywords.strong)
            || MetaCommunityKeywords.strong.contains(normalizedName)
        {
            return MetaClassification(
                isMeta: true, confidence: .high, reason: .strongKeyword)
        }

        if !tokens.isDisjoint(with: MetaCommunityKeywords.broad)
            || MetaCommunityKeywords.broad.contains(normalizedName)
        {
            return MetaClassification(
                isMeta: true, confidence: .low, reason: .broadKeyword)
        }

        return .notMeta
    }

    private static func matchesInstanceIdentity(
        normalizedName: String,
        normalizedTitle: String?,
        tokens: Set<String>,
        instanceHost: String,
        siteName: String?
    ) -> Bool {
        // Match against the site's human name when known (preferred, reliable).
        if let siteName {
            let normalizedSite = normalizeCollapsed(siteName)
            if !normalizedSite.isEmpty,
               normalizedName == normalizedSite
               || normalizedTitle == normalizedSite
               || tokens.contains(normalizedSite)
            {
                return true
            }
        }

        // Fall back to the instance's primary domain label (the second-to-last
        // dot component): discuss.tchncs.de -> "tchncs", lemmy.world -> "lemmy".
        // Equality only, never substring, so "world" does not match lemmy.world.
        if let label = primaryDomainLabel(instanceHost), !label.isEmpty {
            if normalizedName == label || tokens.contains(label) {
                return true
            }
        }
        return false
    }

    /// The registrable-domain primary label: second-to-last dot component,
    /// normalized. Returns nil for single-label hosts (e.g. "localhost").
    static func primaryDomainLabel(_ host: String) -> String? {
        let bare = host.split(separator: ":").first.map(String.init) ?? host
        let labels = bare.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        return normalizeCollapsed(labels[labels.count - 2])
    }

    /// Lowercased, alphanumerics only (drops spaces, hyphens, underscores).
    static func normalizeCollapsed(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// Lowercased word tokens split on any non-alphanumeric boundary.
    static func wordTokens(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-only ONLY=SpudUtilKitTests`
Expected: PASS. (If new files are not found, run `make project` first, then re-run.)

- [ ] **Step 5: Commit**

```bash
git add SpudUtilKit/MetaCommunity SpudUtilKitTests/MetaCommunityClassifierTests.swift
git commit -m "feat: add pure MetaCommunityClassifier"
```

---

### Task 2: `InstanceMetaCommunityRecord` + v38 migration (SpudDataKit)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/InstanceMetaCommunityRecord.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append before `return migrator`)
- Test: `SpudDataKitTests/AppDatabase/InstanceMetaCommunityRecordTests.swift`

**Interfaces:**
- Produces: `struct InstanceMetaCommunityRecord: Codable, Sendable, Equatable, Identifiable` with fields `id: Int64?`, `accountId: Int64`, `instanceHost: String`, `communityActorId: String`, `confidence: String`, `reason: String`, `discoveredAt: Date`; conforms `FetchableRecord, MutablePersistableRecord`; `databaseTableName = "instanceMetaCommunity"`; a `Columns` enum. Table created by migration `v38_instanceMetaCommunity`, unique key `(accountId, instanceHost, communityActorId)`, `accountId` FK to `account` cascade.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/AppDatabase/InstanceMetaCommunityRecordTests.swift` (BSD header):

```swift
import Foundation
import GRDB
import Testing
@testable import SpudDataKit

struct InstanceMetaCommunityRecordTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeAccount() throws -> Int64 {
        try appDatabase.writer.write { db in
            var account = AccountRecord(accountKeychainId: "kc-1")
            try account.insert(db)
            return try #require(account.id)
        }
    }

    @Test
    func roundTripsEveryField() throws {
        let accountId = try makeAccount()
        let record = InstanceMetaCommunityRecord(
            accountId: accountId,
            instanceHost: "discuss.tchncs.de",
            communityActorId: "https://discuss.tchncs.de/c/tchncs",
            confidence: "high",
            reason: "nameMatchesInstance",
            discoveredAt: Date(timeIntervalSince1970: 1_700_000_000))

        let id = try appDatabase.writer.write { db -> Int64 in
            var r = record
            try r.insert(db)
            return try #require(r.id)
        }

        let fetched = try appDatabase.writer.read { db in
            try InstanceMetaCommunityRecord.fetchOne(db, key: id)
        }
        let u = try #require(fetched)
        #expect(u.accountId == accountId)
        #expect(u.instanceHost == "discuss.tchncs.de")
        #expect(u.communityActorId == "https://discuss.tchncs.de/c/tchncs")
        #expect(u.confidence == "high")
        #expect(u.reason == "nameMatchesInstance")
    }

    @Test
    func uniqueKeyRejectsDuplicateTriple() throws {
        let accountId = try makeAccount()
        func insert() throws {
            try appDatabase.writer.write { db in
                var r = InstanceMetaCommunityRecord(
                    accountId: accountId, instanceHost: "h", communityActorId: "a",
                    confidence: "low", reason: "broadKeyword", discoveredAt: Date())
                try r.insert(db)
            }
        }
        try insert()
        #expect(throws: (any Error).self) { try insert() }
    }
}
```

Verify `AccountRecord(accountKeychainId:)` is the correct initializer by opening `SpudDataKit/Services/AppDatabase/Records/Account.swift`; adjust the seed if the memberwise init requires more fields.

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `InstanceMetaCommunityRecord` undefined / table missing.

- [ ] **Step 3: Write minimal implementation**

Create `SpudDataKit/Services/AppDatabase/Records/InstanceMetaCommunityRecord.swift` (BSD header):

```swift
import Foundation
import GRDB

/// A community classified as "meta" (about the instance itself) for a given
/// instance, cached per account. Populated by `MetaCommunityService` from a
/// fixed candidate-name resolution pass. Holds identity only — live subscribe /
/// favourite state is joined from `community` / `favoritedCommunity` at render.
public struct InstanceMetaCommunityRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "instanceMetaCommunity"

    public var id: Int64?
    public var accountId: Int64
    /// The instance the community is meta *for* (e.g. "discuss.tchncs.de").
    public var instanceHost: String
    /// The community's federation actor id (e.g. "https://discuss.tchncs.de/c/tchncs").
    public var communityActorId: String
    /// `MetaConfidence` raw value: "high" | "low".
    public var confidence: String
    /// `MetaReason` raw value.
    public var reason: String
    public var discoveredAt: Date

    public init(
        id: Int64? = nil,
        accountId: Int64,
        instanceHost: String,
        communityActorId: String,
        confidence: String,
        reason: String,
        discoveredAt: Date = Date()
    ) {
        self.id = id
        self.accountId = accountId
        self.instanceHost = instanceHost
        self.communityActorId = communityActorId
        self.confidence = confidence
        self.reason = reason
        self.discoveredAt = discoveredAt
    }
}

extension InstanceMetaCommunityRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension InstanceMetaCommunityRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let accountId = Column(CodingKeys.accountId)
        public static let instanceHost = Column(CodingKeys.instanceHost)
        public static let communityActorId = Column(CodingKeys.communityActorId)
        public static let confidence = Column(CodingKeys.confidence)
        public static let reason = Column(CodingKeys.reason)
        public static let discoveredAt = Column(CodingKeys.discoveredAt)
    }
}
```

In `AppDatabase+Migrations.swift`, add immediately after the `v37_sessionNeedsReauth` block and before `return migrator`:

```swift
        migrator.registerMigration("v38_instanceMetaCommunity") { db in
            // Per-account cache of communities classified as "meta" (about the
            // instance itself). Keyed by the community's federation actor id so a
            // meta community matches regardless of which feed surfaced it. Scoped
            // per (account, instanceHost) so the same account's view of two
            // instances stays separate. Identity only — subscribe / favourite
            // state is joined live from `community` / `favoritedCommunity`.
            try db.create(table: "instanceMetaCommunity") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer)
                    .notNull()
                    .indexed()
                    .references("account", onDelete: .cascade)
                t.column("instanceHost", .text).notNull()
                t.column("communityActorId", .text).notNull()
                t.column("confidence", .text).notNull()
                t.column("reason", .text).notNull()
                t.column("discoveredAt", .datetime).notNull()
                t.uniqueKey(["accountId", "instanceHost", "communityActorId"])
            }
            try db.create(
                index: "index_instanceMetaCommunity_on_accountId_instanceHost",
                on: "instanceMetaCommunity",
                columns: ["accountId", "instanceHost"])
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/Records/InstanceMetaCommunityRecord.swift \
        SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift \
        SpudDataKitTests/AppDatabase/InstanceMetaCommunityRecordTests.swift
git commit -m "feat: add instanceMetaCommunity cache record and v38 migration"
```

---

### Task 3: `InstanceMetaCommunityQueries` (SpudDataKit)

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/InstanceMetaCommunityQueries.swift`
- Test: `SpudDataKitTests/AppDatabase/InstanceMetaCommunityQueriesTests.swift`

**Interfaces:**
- Consumes: `InstanceMetaCommunityRecord` (Task 2), `CommunityRecord`/`FavoritedCommunityRecord` (existing), `MetaConfidence`/`CommunitySubscribedState` (existing).
- Produces on `public extension AppDatabase`:
  - `func replaceMetaCommunitiesSync(forAccountId accountId: Int64, instanceHost: String, entries: [MetaCommunityCacheEntry])` — atomically replaces the cached set for `(account, host)`.
  - `func metaCommunityFreshnessSync(forAccountId accountId: Int64, instanceHost: String) -> Date?` — max `discoveredAt` (nil if none).
  - `func observeMetaCommunities(forAccountId accountId: Int64, instanceHost: String) -> AsyncStream<[MetaCommunityListItem]>`.
  - `struct MetaCommunityCacheEntry: Sendable, Equatable { let communityActorId: String; let confidence: MetaConfidence; let reason: MetaReason }`
  - `struct MetaCommunityListItem: Sendable, Equatable, Identifiable { let id: Int64; /* serverCommunityId */ var serverCommunityId: Int64 { id }; let name: String; let title: String?; let communityActorId: String; let iconUrl: String?; let confidence: MetaConfidence; let subscribedState: CommunitySubscribedState; let isFavorite: Bool }`

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/AppDatabase/InstanceMetaCommunityQueriesTests.swift` (BSD header):

```swift
import Foundation
import GRDB
import SpudUtilKit
import Testing
@testable import SpudDataKit

struct InstanceMetaCommunityQueriesTests {
    private let appDatabase: AppDatabase

    init() throws {
        appDatabase = try AppDatabase.inMemory()
    }

    private func makeAccount() throws -> Int64 {
        try appDatabase.writer.write { db in
            var account = AccountRecord(accountKeychainId: "kc-1")
            try account.insert(db)
            return try #require(account.id)
        }
    }

    private func insertCommunity(
        accountId: Int64, serverId: Int64, name: String, actorId: String,
        subscribed: CommunitySubscribedState = .notSubscribed
    ) throws {
        try appDatabase.writer.write { db in
            var c = CommunityRecord(
                accountId: accountId, communityId: serverId, name: name, title: name,
                actorId: actorId, descriptionText: nil, iconUrl: nil, bannerUrl: nil,
                isHidden: false, isLocal: true, isNsfw: false,
                isPostingRestrictedToMods: false, isRemoved: false,
                subscribedState: subscribed.rawValue, numberOfSubscribers: 0,
                numberOfPosts: 0, numberOfComments: 0, communityCreatedDate: nil,
                communityUpdatedDate: nil, createdAt: Date(), updatedAt: Date())
            try c.insert(db)
        }
    }

    @Test
    func replaceThenFreshnessReturnsLatest() throws {
        let accountId = try makeAccount()
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "a", confidence: .high, reason: .strongKeyword)])
        #expect(appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "tchncs.de") != nil)
        #expect(appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "other.de") == nil)
    }

    @Test
    func replaceIsAtomicSwap() throws {
        let accountId = try makeAccount()
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "a", confidence: .high, reason: .strongKeyword),
                      .init(communityActorId: "b", confidence: .low, reason: .broadKeyword)])
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "a", confidence: .high, reason: .strongKeyword)])
        let count = try appDatabase.writer.read { db in
            try InstanceMetaCommunityRecord
                .filter(Column("accountId") == accountId)
                .fetchCount(db)
        }
        #expect(count == 1)
    }

    @Test
    func observeJoinsCommunityAndFavourite() async throws {
        let accountId = try makeAccount()
        try insertCommunity(accountId: accountId, serverId: 42, name: "meta",
                            actorId: "https://tchncs.de/c/meta", subscribed: .subscribed)
        appDatabase.favoriteCommunitySync(forKeychainId: "kc-1", communityActorId: "https://tchncs.de/c/meta")
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: "tchncs.de",
            entries: [.init(communityActorId: "https://tchncs.de/c/meta", confidence: .high, reason: .strongKeyword)])

        var iterator = appDatabase.observeMetaCommunities(
            forAccountId: accountId, instanceHost: "tchncs.de").makeAsyncIterator()
        let items = try #require(await iterator.next())
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.serverCommunityId == 42)
        #expect(item.name == "meta")
        #expect(item.confidence == .high)
        #expect(item.subscribedState == .subscribed)
        #expect(item.isFavorite)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: FAIL — query methods / `MetaCommunityListItem` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `SpudDataKit/Services/AppDatabase/InstanceMetaCommunityQueries.swift` (BSD header). Model writes/reads/observation on `FavoritedCommunityQueries.swift`:

```swift
import Foundation
import GRDB
import SpudUtilKit

public struct MetaCommunityCacheEntry: Sendable, Equatable {
    public let communityActorId: String
    public let confidence: MetaConfidence
    public let reason: MetaReason
    public init(communityActorId: String, confidence: MetaConfidence, reason: MetaReason) {
        self.communityActorId = communityActorId
        self.confidence = confidence
        self.reason = reason
    }
}

public struct MetaCommunityListItem: Sendable, Equatable, Identifiable {
    /// The community's server-side id, also the SwiftUI identity.
    public let id: Int64
    public var serverCommunityId: Int64 { id }
    public let name: String
    public let title: String?
    public let communityActorId: String
    public let iconUrl: String?
    public let confidence: MetaConfidence
    public let subscribedState: CommunitySubscribedState
    public let isFavorite: Bool
}

public extension AppDatabase {
    private var metaLogger: Logger { Logger.appDatabase }

    /// Atomically replace the cached meta set for `(account, instanceHost)`.
    func replaceMetaCommunitiesSync(
        forAccountId accountId: Int64,
        instanceHost: String,
        entries: [MetaCommunityCacheEntry]
    ) {
        do {
            try writer.write { db in
                try InstanceMetaCommunityRecord
                    .filter(Column("accountId") == accountId)
                    .filter(Column("instanceHost") == instanceHost)
                    .deleteAll(db)
                let now = Date()
                for entry in entries {
                    var record = InstanceMetaCommunityRecord(
                        accountId: accountId,
                        instanceHost: instanceHost,
                        communityActorId: entry.communityActorId,
                        confidence: entry.confidence.rawValue,
                        reason: entry.reason.rawValue,
                        discoveredAt: now)
                    try record.insert(db)
                }
            }
        } catch {
            Logger.appDatabase.error("replaceMetaCommunitiesSync failed: \(error, privacy: .public)")
        }
    }

    func metaCommunityFreshnessSync(
        forAccountId accountId: Int64,
        instanceHost: String
    ) -> Date? {
        do {
            return try writer.read { db in
                try Date.fetchOne(db, sql: """
                    SELECT MAX(discoveredAt) FROM instanceMetaCommunity
                    WHERE accountId = ? AND instanceHost = ?
                    """, arguments: [accountId, instanceHost])
            }
        } catch {
            Logger.appDatabase.error("metaCommunityFreshnessSync failed: \(error, privacy: .public)")
            return nil
        }
    }

    func observeMetaCommunities(
        forAccountId accountId: Int64,
        instanceHost: String
    ) -> AsyncStream<[MetaCommunityListItem]> {
        let observation = ValueObservation
            .tracking { db -> [MetaCommunityListItem] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT c.communityId AS serverId,
                           c.name AS name,
                           c.title AS title,
                           c.actorId AS actorId,
                           c.iconUrl AS iconUrl,
                           c.subscribedState AS subscribedState,
                           m.confidence AS confidence,
                           (fc.id IS NOT NULL) AS isFavorite
                    FROM instanceMetaCommunity m
                    JOIN community c
                        ON c.actorId = m.communityActorId AND c.accountId = m.accountId
                    LEFT JOIN favoritedCommunity fc
                        ON fc.communityActorId = m.communityActorId AND fc.accountId = m.accountId
                    WHERE m.accountId = ? AND m.instanceHost = ?
                    ORDER BY (m.confidence = 'high') DESC, LOWER(c.name) ASC
                    """, arguments: [accountId, instanceHost])
                return rows.map { row in
                    MetaCommunityListItem(
                        id: row["serverId"],
                        name: row["name"] ?? "",
                        title: row["title"],
                        communityActorId: row["actorId"] ?? "",
                        iconUrl: row["iconUrl"],
                        confidence: MetaConfidence(rawValue: row["confidence"] ?? "low") ?? .low,
                        subscribedState: CommunitySubscribedState(rawValue: row["subscribedState"] ?? "") ?? .notSubscribed,
                        isFavorite: (row["isFavorite"] as Int64? ?? 0) != 0)
                }
            }
            .removeDuplicates()
        return makeStream(observation: observation)
    }
}
```

If `makeStream` is `private` to `Observations.swift`, either move it to a shared internal helper or inline the same `AsyncStream { … observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) … }` body used there (verify by opening `Observations.swift:191`). Prefer promoting `makeStream` to `internal` in `Observations.swift` so both files share it.

- [ ] **Step 4: Run test to verify it passes**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/InstanceMetaCommunityQueries.swift \
        SpudDataKitTests/AppDatabase/InstanceMetaCommunityQueriesTests.swift
# include Observations.swift if makeStream visibility was changed
git commit -m "feat: add instanceMetaCommunity queries and live observation"
```

---

### Task 4: `MetaCommunityService` + resolving seam (SpudDataKit)

**Files:**
- Create: `SpudDataKit/Services/MetaCommunity/MetaCommunityResolving.swift`
- Create: `SpudDataKit/Services/MetaCommunity/MetaCommunityService.swift`
- Test: `SpudDataKitTests/MetaCommunity/MetaCommunityServiceTests.swift`

**Interfaces:**
- Consumes: `MetaCommunityClassifier` (Task 1), `AppDatabase` meta queries (Task 3).
- Produces:
  - `struct ResolvedMetaCandidate: Sendable, Equatable { let name: String; let title: String?; let actorId: String; let instanceHost: String }`
  - `protocol MetaCommunityResolving: Sendable { func resolveCandidate(name: String, onHost host: String, forAccountKeychainId keychainId: String) async -> ResolvedMetaCandidate? }`
  - `enum MetaCommunityCandidates { static let `default`: [String] }`
  - `protocol MetaCommunityServiceType: Sendable { func refreshInstance(host: String, siteName: String?, forAccountKeychainId keychainId: String) async }`
  - `protocol HasMetaCommunityService { var metaCommunityService: MetaCommunityServiceType { get } }`
  - `actor MetaCommunityService: MetaCommunityServiceType` with `init(resolver:appDatabase:freshness:candidateNames:)`.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/MetaCommunity/MetaCommunityServiceTests.swift` (BSD header). Model the fake seam + call counter on `NodeInfoServiceTests`:

```swift
import Foundation
import Testing
@testable import SpudDataKit

private actor CallLog {
    var names: [String] = []
    func record(_ name: String) { names.append(name) }
}

private struct FakeResolver: MetaCommunityResolving {
    /// name -> resolved candidate (nil = not found on the instance).
    let table: [String: ResolvedMetaCandidate]
    let log: CallLog?
    func resolveCandidate(
        name: String, onHost host: String, forAccountKeychainId _: String
    ) async -> ResolvedMetaCandidate? {
        await log?.record(name)
        return table[name]
    }
}

@MainActor
struct MetaCommunityServiceTests {
    private func seededAccount(_ db: AppDatabase) throws -> Int64 {
        try db.writer.write { d in
            var a = AccountRecord(accountKeychainId: "kc-1")
            try a.insert(d)
            return try #require(a.id)
        }
    }

    @Test
    func resolvesClassifiesAndCachesMetaOnly() async throws {
        let db = try AppDatabase.inMemory()
        let accountId = try seededAccount(db)
        let resolver = FakeResolver(table: [
            "meta": .init(name: "meta", title: "Meta", actorId: "https://tchncs.de/c/meta", instanceHost: "tchncs.de"),
            "photography": .init(name: "photography", title: "Photography", actorId: "https://tchncs.de/c/photography", instanceHost: "tchncs.de"),
        ], log: nil)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600,
            candidateNames: ["meta", "photography", "doesnotexist"])

        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")

        // Only "meta" classifies as meta and exists; "photography" resolves but is
        // not meta; "doesnotexist" returns nil.
        #expect(db.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: "tchncs.de") != nil)
        let count = try db.writer.read { d in
            try InstanceMetaCommunityRecord.filter(Column("accountId") == accountId).fetchCount(d)
        }
        #expect(count == 1)
    }

    @Test
    func skipsWhenCacheIsFresh() async throws {
        let db = try AppDatabase.inMemory()
        _ = try seededAccount(db)
        let log = CallLog()
        let resolver = FakeResolver(table: [
            "meta": .init(name: "meta", title: "Meta", actorId: "https://tchncs.de/c/meta", instanceHost: "tchncs.de"),
        ], log: log)
        let service = MetaCommunityService(
            resolver: resolver, appDatabase: db, freshness: 3600, candidateNames: ["meta"])

        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")
        let firstCalls = await log.names.count
        await service.refreshInstance(host: "tchncs.de", siteName: "tchncs", forAccountKeychainId: "kc-1")
        let secondCalls = await log.names.count
        #expect(firstCalls > 0)
        #expect(secondCalls == firstCalls) // second call skipped by freshness
    }
}
```

Note: `import GRDB` may be needed for `Column`; add it if the build complains.

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: FAIL — `MetaCommunityService` / `MetaCommunityResolving` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `SpudDataKit/Services/MetaCommunity/MetaCommunityResolving.swift` (BSD header):

```swift
import Foundation

/// A community resolved from a candidate name against an instance.
public struct ResolvedMetaCandidate: Sendable, Equatable {
    public let name: String
    public let title: String?
    public let actorId: String
    public let instanceHost: String
    public init(name: String, title: String?, actorId: String, instanceHost: String) {
        self.name = name
        self.title = title
        self.actorId = actorId
        self.instanceHost = instanceHost
    }
}

/// Narrow seam over "resolve one candidate community name on one instance".
/// The live implementation goes through `LemmyService.fetchCommunityInfo`;
/// tests inject a fake. Returns nil when the community does not exist there.
public protocol MetaCommunityResolving: Sendable {
    func resolveCandidate(
        name: String,
        onHost host: String,
        forAccountKeychainId keychainId: String
    ) async -> ResolvedMetaCandidate?
}

/// The fixed candidate names probed against each instance. Bounded so a refresh
/// is at most this many lookups. Broad enough for common meta communities;
/// oddly-named ones are still badged in lists via the inline classifier.
public enum MetaCommunityCandidates {
    public static let `default`: [String] = [
        "meta", "announcements", "support", "help", "feedback", "changelog",
        "news", "updates", "admin", "welcome", "rules", "site",
    ]
}
```

Create `SpudDataKit/Services/MetaCommunity/MetaCommunityService.swift` (BSD header):

```swift
import Foundation
import SpudUtilKit

public protocol MetaCommunityServiceType: Sendable {
    /// Resolve + classify + cache the meta communities of `host` for the given
    /// account. No-op when the cache is fresher than the service's freshness
    /// window. `siteName` (when known) sharpens name-matching.
    func refreshInstance(host: String, siteName: String?, forAccountKeychainId keychainId: String) async
}

public protocol HasMetaCommunityService {
    var metaCommunityService: MetaCommunityServiceType { get }
}

public actor MetaCommunityService: MetaCommunityServiceType {
    private let resolver: MetaCommunityResolving
    private let appDatabase: AppDatabase
    private let freshness: TimeInterval
    private let candidateNames: [String]
    /// Guards against overlapping refreshes for the same (account, host).
    private var inFlight: Set<String> = []

    public init(
        resolver: MetaCommunityResolving,
        appDatabase: AppDatabase,
        freshness: TimeInterval = 24 * 3600,
        candidateNames: [String] = MetaCommunityCandidates.default
    ) {
        self.resolver = resolver
        self.appDatabase = appDatabase
        self.freshness = freshness
        self.candidateNames = candidateNames
    }

    public func refreshInstance(
        host: String, siteName: String?, forAccountKeychainId keychainId: String
    ) async {
        guard let accountId = appDatabase.accountRowIdSync(forKeychainId: keychainId) else { return }
        let key = "\(accountId)\u{1}\(host)"
        guard !inFlight.contains(key) else { return }

        if let last = appDatabase.metaCommunityFreshnessSync(forAccountId: accountId, instanceHost: host),
           Date().timeIntervalSince(last) < freshness {
            return
        }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        var entries: [MetaCommunityCacheEntry] = []
        for name in candidateNames {
            guard let resolved = await resolver.resolveCandidate(
                name: name, onHost: host, forAccountKeychainId: keychainId) else { continue }
            let classification = MetaCommunityClassifier.classify(
                name: resolved.name, title: resolved.title,
                instanceHost: resolved.instanceHost, siteName: siteName)
            guard classification.isMeta else { continue }
            guard !entries.contains(where: { $0.communityActorId == resolved.actorId }) else { continue }
            entries.append(MetaCommunityCacheEntry(
                communityActorId: resolved.actorId,
                confidence: classification.confidence,
                reason: classification.reason))
        }

        // Only overwrite the cache when we found something, so a transient
        // all-miss network pass does not wipe a good prior result.
        guard !entries.isEmpty else { return }
        appDatabase.replaceMetaCommunitiesSync(
            forAccountId: accountId, instanceHost: host, entries: entries)
    }
}
```

Verify `appDatabase.accountRowIdSync(forKeychainId:)` exists (it is referenced in `AccountService.reminderService(...)`); if the exact name differs, open `AppDatabase.swift` and use the actual accessor.

- [ ] **Step 4: Run test to verify it passes**

Run: `make project && make test-only ONLY=SpudDataKitTests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/MetaCommunity/MetaCommunityResolving.swift \
        SpudDataKit/Services/MetaCommunity/MetaCommunityService.swift \
        SpudDataKitTests/MetaCommunity/MetaCommunityServiceTests.swift
git commit -m "feat: add MetaCommunityService and resolving seam"
```

---

### Task 5: Live resolver + DI registration

**Files:**
- Create: `SpudDataKit/Services/MetaCommunity/LiveMetaCommunityResolver.swift`
- Modify: `Spud/App/DependencyContainer.swift`

**Interfaces:**
- Consumes: `MetaCommunityResolving` (Task 4), `AccountServiceType`/`LemmyServiceType.fetchCommunityInfo` (existing), `AppDatabase` (existing).
- Produces: `struct LiveMetaCommunityResolver: MetaCommunityResolving`; `DependencyContainer.metaCommunityService: MetaCommunityServiceType`; `DependencyContainer: HasMetaCommunityService`.

- [ ] **Step 1: Write the live resolver**

Create `SpudDataKit/Services/MetaCommunity/LiveMetaCommunityResolver.swift` (BSD header):

```swift
import Foundation
import GRDB
import LemmyKit
import SpudUtilKit

/// Live `MetaCommunityResolving`: resolves a candidate community name through
/// `LemmyService.fetchCommunityInfo`, then reads the mirrored `CommunityRecord`
/// back to build the resolved candidate. Returns nil when the community does
/// not exist on the instance (fetch throws) or cannot be read back.
public struct LiveMetaCommunityResolver: MetaCommunityResolving {
    private let accountService: AccountServiceType
    private let appDatabase: AppDatabase

    public init(accountService: AccountServiceType, appDatabase: AppDatabase) {
        self.accountService = accountService
        self.appDatabase = appDatabase
    }

    public func resolveCandidate(
        name: String, onHost host: String, forAccountKeychainId keychainId: String
    ) async -> ResolvedMetaCandidate? {
        let homeHost = await MainActor.run {
            accountService.instanceActorId(forAccountKeychainId: keychainId)?.hostWithPort
        }
        // Bare name for a community local to the account's own instance;
        // "name@host" for any other instance.
        let query = (host == homeHost) ? name : "\(name)@\(host)"
        let lemmyService = await MainActor.run {
            accountService.lemmyService(forAccountKeychainId: keychainId)
        }
        guard let serverId = try? await lemmyService.fetchCommunityInfo(communityName: query) else {
            return nil
        }
        return appDatabase.resolvedMetaCandidateSync(
            forKeychainId: keychainId, serverCommunityId: Int64(serverId))
    }
}
```

Add the read-back helper to `InstanceMetaCommunityQueries.swift` (Task 3 file) so the resolver stays thin:

```swift
public extension AppDatabase {
    /// Read back a just-mirrored community as a `ResolvedMetaCandidate`.
    func resolvedMetaCandidateSync(
        forKeychainId keychainId: String, serverCommunityId: Int64
    ) -> ResolvedMetaCandidate? {
        do {
            return try writer.read { db -> ResolvedMetaCandidate? in
                guard
                    let accountId = try AccountRecord
                        .filter(Column("accountKeychainId") == keychainId)
                        .fetchOne(db)?.id,
                    let community = try CommunityRecord
                        .filter(Column("accountId") == accountId)
                        .filter(Column("communityId") == serverCommunityId)
                        .fetchOne(db),
                    let actorId = community.actorId,
                    let host = actorId.range(of: "://").map({ String(actorId[$0.upperBound...]) })
                        .flatMap({ $0.split(separator: "/").first }).map(String.init)
                else { return nil }
                return ResolvedMetaCandidate(
                    name: community.name ?? "", title: community.title,
                    actorId: actorId, instanceHost: host)
            }
        } catch {
            Logger.appDatabase.error("resolvedMetaCandidateSync failed: \(error, privacy: .public)")
            return nil
        }
    }
}
```

Confirm `LemmyKit` is the module exposing `Lemmy.CommunityID` (it is imported in `LemmyService.swift`); import it in the resolver only if the compiler needs it for `Int64(serverId)` (a `Lemmy.CommunityID`).

- [ ] **Step 2: Register in `DependencyContainer`**

In `Spud/App/DependencyContainer.swift`:
1. Add `HasMetaCommunityService` to the conformance list.
2. Add the stored property near the other services: `let metaCommunityService: MetaCommunityServiceType`.
3. In `init`, after `accountService` and `appDatabase` are assigned, add:

```swift
        metaCommunityService = MetaCommunityService(
            resolver: LiveMetaCommunityResolver(
                accountService: accountService, appDatabase: appDatabase),
            appDatabase: appDatabase)
```

- [ ] **Step 3: Build**

Run: `make project && make build`
Expected: BUILD SUCCEEDED. If a VC's `NestedDependencies` now fails to satisfy `HasMetaCommunityService`, add the protocol to that VC's `Dependencies` typealias (only where the "About" section is wired, Task 10 — otherwise no VC needs it yet).

- [ ] **Step 4: Run existing tests to confirm no regression**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/MetaCommunity/LiveMetaCommunityResolver.swift \
        SpudDataKit/Services/AppDatabase/InstanceMetaCommunityQueries.swift \
        Spud/App/DependencyContainer.swift
git commit -m "feat: wire live meta community resolver into the dependency graph"
```

---

### Task 6: `MetaCommunityBadge` + Discover row badge

**Files:**
- Create: `Spud/Scenes/Shared/MetaCommunityBadge.swift`
- Modify: `Spud/Scenes/Discover/DiscoverView.swift` (`DiscoverCommunityRow`, title `HStack` ~lines 435-443)
- Test: `SpudSnapshotTests/MetaCommunityBadgeSnapshotTests.swift`

**Interfaces:**
- Consumes: `MetaCommunityClassifier` (Task 1), `CommunityListRow` (existing: `name`, `title`, `instanceHost`).
- Produces: `struct MetaCommunityBadge: View` (SwiftUI pill). `CommunityListRow.isMetaCommunity: Bool` convenience.

- [ ] **Step 1: Write the badge view + convenience**

Create `Spud/Scenes/Shared/MetaCommunityBadge.swift` (BSD header). Match `NsfwBadge.swift` style but tinted + symbol:

```swift
import SwiftUI

/// The single "meta" pill marking a community that is about its own instance
/// (e.g. an announcements / site community). One definition so it reads
/// identically across Discover, the Communities tab, and search.
struct MetaCommunityBadge: View {
    var body: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(Text("Instance community", comment: "Accessibility label for the meta-community badge"))
    }
}
```

Add a convenience in the same file (or in a `CommunityListRow+Meta.swift`):

```swift
import SpudDataKit
import SpudUtilKit

extension CommunityListRow {
    /// Whether this directory row is a meta community. Directory rows carry no
    /// site name, so name-match degrades to the domain label; keyword match
    /// still applies.
    var isMetaCommunity: Bool {
        MetaCommunityClassifier.classify(
            name: name, title: title, instanceHost: instanceHost, siteName: nil).isMeta
    }
}
```

- [ ] **Step 2: Insert the badge into `DiscoverCommunityRow`**

In `DiscoverView.swift`, in the title `HStack(spacing: 6)` (currently `Text(row.displayName)` then `if row.isNsfw { NsfwBadge() }`), add after the NSFW badge:

```swift
                    if row.isMetaCommunity {
                        MetaCommunityBadge()
                    }
```

- [ ] **Step 3: Write the snapshot test**

Create `SpudSnapshotTests/MetaCommunityBadgeSnapshotTests.swift` (BSD header). Model imports/setUp on `InstanceDetailSnapshotTests`:

```swift
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Spud

@MainActor
final class MetaCommunityBadgeSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    func test_badge() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = MetaCommunityBadge().padding()
            let host = UIHostingController(rootView: view)
            assertSnapshot(
                matching: host,
                as: .image(traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light")
        }
    }
}
```

- [ ] **Step 4: Record + verify snapshots**

Run: `make project`, then record once: set `isRecording = true` locally (or delete any prior `__Snapshots__/MetaCommunityBadgeSnapshotTests`), run `make snapshot`, then re-run `make snapshot` to confirm PASS. Visually inspect the recorded PNGs for a legible pill.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Shared/MetaCommunityBadge.swift \
        Spud/Scenes/Discover/DiscoverView.swift \
        SpudSnapshotTests/MetaCommunityBadgeSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/MetaCommunityBadgeSnapshotTests
git commit -m "feat: add meta community badge and show it in Discover rows"
```

---

### Task 7: Communities tab row badge

**Files:**
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewItemType.swift` (`SubscriptionsCommunityRow`)
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift` (`makeRow`)
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsView.swift` (`SubscriptionsCommunityView`)
- Test: `SpudTests/SubscriptionsMetaRowTests.swift`

**Interfaces:**
- Consumes: `MetaCommunityClassifier` (Task 1).
- Produces: `SubscriptionsCommunityRow.isMeta: Bool`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/SubscriptionsMetaRowTests.swift` (BSD header). Verify how `makeRow` is invoked and what it takes (open `SubscriptionsViewModel.swift:makeRow`); this test asserts the flag via the same public entry the VM uses. If `makeRow` is `private`, expose the classification through the row model instead by computing `isMeta` in `makeRow` and asserting on a constructed `SubscriptionsCommunityRow`:

```swift
import SpudUtilKit
import Testing
@testable import Spud

struct SubscriptionsMetaRowTests {
    @Test
    func metaCommunityNameFlagsRow() {
        let row = SubscriptionsCommunityRow(
            id: 1, name: "announcements",
            instanceActorId: InstanceActorId(from: "https://lemmy.world")!,
            communityActorId: "https://lemmy.world/c/announcements",
            isFavorite: false, isMeta: true)
        #expect(row.isMeta)
    }
}
```

Then the real behavioral coverage is the classifier (Task 1); this test locks the row-model field exists and is wired.

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudTests`
Expected: FAIL — `SubscriptionsCommunityRow` has no `isMeta`.

- [ ] **Step 3: Add the field + compute it + render it**

In `SubscriptionsViewItemType.swift`, add to `SubscriptionsCommunityRow`:

```swift
    /// Whether this community is "meta" for its instance (announcements / site
    /// community). Rendered with a small badge.
    var isMeta: Bool = false
```

In `SubscriptionsViewModel.swift` `makeRow`, compute it from the `CommunityRecord` before building the row (add `import SpudUtilKit` if absent):

```swift
        let isMeta = MetaCommunityClassifier.classify(
            name: community.name ?? "",
            title: community.title,
            instanceHost: instanceActorId.host,
            siteName: nil).isMeta
```

and pass `isMeta: isMeta` into the `SubscriptionsCommunityRow(...)` construction. (`instanceActorId` is already derived inside `makeRow` per the existing code.)

In `SubscriptionsView.swift` `SubscriptionsCommunityView`, add the badge next to the name — change the name `Text` line into an `HStack`:

```swift
                HStack(spacing: 6) {
                    Text(row.name)
                        .foregroundStyle(Color(.label))
                    if row.isMeta {
                        MetaCommunityBadge()
                    }
                }
```

- [ ] **Step 4: Run tests + build**

Run: `make project && make test-only ONLY=SpudTests && make build`
Expected: PASS + BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Subscriptions/SubscriptionsViewItemType.swift \
        Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift \
        Spud/Scenes/Subscriptions/SubscriptionsView.swift \
        SpudTests/SubscriptionsMetaRowTests.swift
git commit -m "feat: badge meta communities in the Communities tab"
```

---

### Task 8: Search cell badge (UIKit)

**Files:**
- Modify: `Spud/Scenes/Search/SearchResultCells.swift` (`SearchCommunityCell`)
- Test: `SpudSnapshotTests/SearchCommunityCellSnapshotTests.swift` (new) OR extend an existing search snapshot file.

**Interfaces:**
- Consumes: `MetaCommunityClassifier` (Task 1), `SearchCommunityResult` (existing — open the file to confirm its `name`/host/`qualifiedName` fields).

- [ ] **Step 1: Determine the classifier inputs**

Open `SearchResultCells.swift` and the `SearchCommunityResult` type. Identify the community `name` and instance host fields (e.g. `result.name` and a host parsed from `result.qualifiedName` / an actor id). If only `qualifiedName` ("name@host") is available, split on "@" for name + host.

- [ ] **Step 2: Add the badge glyph**

Add a `UIImageView` badge to the cell (declared next to `iconView`), configured from the classifier. Reuse the symbol from `MetaCommunityBadge` for consistency:

```swift
    private let metaBadge: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "building.2.fill"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .secondaryLabel
        iv.contentMode = .scaleAspectFit
        iv.isHidden = true
        iv.isAccessibilityElement = true
        iv.accessibilityLabel = NSLocalizedString("Instance community", comment: "Meta community badge")
        return iv
    }()
```

Place it in a horizontal stack with `nameLabel` (replace the bare `nameLabel` in `textStack` with `UIStackView(arrangedSubviews: [nameLabel, metaBadge, UIView()])`, axis `.horizontal`, spacing 6, alignment `.center`), and set visibility in `configure(with:imageService:)`:

```swift
        let (name, host) = Self.nameAndHost(from: result.qualifiedName)
        metaBadge.isHidden = !MetaCommunityClassifier.classify(
            name: name, title: nil, instanceHost: host, siteName: nil).isMeta
```

Add a small `private static func nameAndHost(from qualified: String) -> (String, String)` splitting on "@" (host defaults to empty when absent — keyword match still works on the name). Add `import SpudUtilKit`.

- [ ] **Step 3: Snapshot test**

Create `SpudSnapshotTests/SearchCommunityCellSnapshotTests.swift` modeled on the existing search / cell snapshot tests (find one with `git ls-files SpudSnapshotTests | grep -i search`), rendering the cell configured with a meta result (`announcements@lemmy.world`) and a non-meta result, in light + dark. Record then verify (`make snapshot` twice).

- [ ] **Step 4: Build + verify**

Run: `make project && make build && make snapshot`
Expected: BUILD SUCCEEDED, snapshots PASS.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Search/SearchResultCells.swift SpudSnapshotTests/SearchCommunityCellSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/SearchCommunityCellSnapshotTests
git commit -m "feat: badge meta communities in search results"
```

---

### Task 9: Community header meta pill (UIKit)

**Files:**
- Modify: `Spud/Scenes/Community/Content/CommunityHeaderView.swift`
- Test: extend `SpudSnapshotTests/` community header snapshots if present (find via `git ls-files SpudSnapshotTests | grep -i communit`), else add one.

**Interfaces:**
- Consumes: `MetaCommunityClassifier` (Task 1). The header already resolves the community name + instance host (see `qualifiedName` usage in `CommunityViewModel`).

- [ ] **Step 1: Add a `metaBadge` pill**

Mirror the existing `nsfwBadge` (`CommunityHeaderView.swift:153-166`) — a padded `UILabel` styled as a pill, but neutral-tinted with the meta symbol via `NSAttributedString.symbol(...)` if available, else a plain "META" text pill:

```swift
    private lazy var metaBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("META", comment: "Meta community badge on community header")
        label.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
        label.textColor = .white
        label.backgroundColor = .secondaryLabel
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        label.accessibilityLabel = NSLocalizedString("Instance community", comment: "Meta community badge")
        return label
    }()
```

- [ ] **Step 2: Constrain it without colliding with the NSFW pill**

The NSFW pill is pinned `leadingAnchor == titleLabel.trailingAnchor + 6` with a trailing cap (`CommunityHeaderView.swift:255-262`). Chain the meta pill after the NSFW pill: constrain `metaBadge.leadingAnchor == nsfwBadge.trailingAnchor + 6` (and keep the same `centerYAnchor`, height 16, min width, and a trailing cap `<= trailingAnchor - margin`). Because either pill can be hidden, add both possible leading constraints is fragile — instead put both pills in a horizontal `UIStackView` after the title and let hidden views collapse. If a stack refactor is too invasive, pin `metaBadge.leadingAnchor` to `titleLabel.trailingAnchor + 6` and `nsfwBadge.leadingAnchor` to `metaBadge.trailingAnchor + 6`, toggling spacing by hiding — verify with the snapshot in both NSFW-on/off states.

- [ ] **Step 3: Toggle in `configure`**

Add an `isMeta` parameter to `configure(...)` (signature at `CommunityHeaderView.swift:286-296`) and set `metaBadge.isHidden = !isMeta` (next to `nsfwBadge.isHidden = !isNsfw` at line 313). Compute `isMeta` at the call site (the community VC/VM) via `MetaCommunityClassifier.classify(name:title:instanceHost:siteName:)`, passing the loaded community's name/title/host and the instance site name when available.

- [ ] **Step 4: Build + snapshot**

Run: `make project && make build && make snapshot`
Expected: BUILD SUCCEEDED; snapshots PASS (record first if a header snapshot exists).

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Community/Content/CommunityHeaderView.swift SpudSnapshotTests
git commit -m "feat: show meta pill on the community header"
```

---

### Task 10: "About <instance>" section — view model

**Files:**
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift`
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsViewController.swift`
- Test: `SpudTests/SubscriptionsMetaSectionViewModelTests.swift`

**Interfaces:**
- Consumes: `AppDatabase.observeMetaCommunities` (Task 3), `MetaCommunityServiceType.refreshInstance` (Task 4), `AccountScope` (existing: `.lemmyService`, `.instanceActorId`, `.accountKeychainId`), `MetaCommunityListItem` (Task 3), `favoriteCommunitySync`/`unfavoriteCommunitySync` (existing).
- Produces on `SubscriptionsViewModel`: `var metaCommunities: [MetaCommunityListItem]`, `var metaInstanceName: String?`, `func toggleSubscribe(_:)`, `func toggleFavorite(_:)`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/SubscriptionsMetaSectionViewModelTests.swift` (BSD header). Because subscribe/favourite need `AccountScope`/`LemmyService`, use a local stub conforming to the `LemmyServiceType`-style protocol used by `SubscriptionsViewModel`, and an `AppDatabase.inMemory()`. Assert that a favourite tap writes through and that `metaCommunities` reflects the observation. Model doubles on `SpudTests/DMThreadViewModelSendGuardTests.swift`. Keep the first test minimal — a favourite round-trip:

```swift
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

@MainActor
struct SubscriptionsMetaSectionViewModelTests {
    @Test
    func favouriteTogglePersists() async throws {
        let db = try AppDatabase.inMemory()
        // Seed account + a meta community + cache row (reuse helpers from
        // SpudDataKit test seeding patterns; inline here).
        let accountId = try db.writer.write { d -> Int64 in
            var a = AccountRecord(accountKeychainId: "kc-1"); try a.insert(d)
            return try #require(a.id)
        }
        // ... seed one CommunityRecord + instanceMetaCommunity row (see Task 3 test helpers) ...
        // Build the VM with the injected db + a stub scope, call toggleFavorite, assert isCommunityFavoritedSync == true.
        _ = accountId
    }
}
```

Flesh out the seed using the same `insertCommunity` + `replaceMetaCommunitiesSync` helpers from Task 3's test. Assert `db.isCommunityFavoritedSync(forKeychainId:communityActorId:)` flips to `true` after `viewModel.toggleFavorite(item)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-only ONLY=SpudTests`
Expected: FAIL — VM lacks `metaCommunities` / `toggleFavorite`.

- [ ] **Step 3: Expand the view model**

In `SubscriptionsViewModel.swift`:
1. Add stored observable state:
```swift
    var metaCommunities: [MetaCommunityListItem] = []
    /// Human name of the home instance for the "About <name>" section header.
    var metaInstanceName: String?
```
2. Add injected dependencies to `init` (new parameters, keep existing ones): `accountScope: AccountScope?`, `metaCommunityService: MetaCommunityServiceType?`. Store them (`@ObservationIgnored private let accountScope`, `@ObservationIgnored private let metaCommunityService`).
3. Compute the home host + start the observation + trigger a refresh, inside the existing `guard let accountRowId` block:
```swift
        if let host = accountScope?.instanceActorId?.hostWithPort {
            metaInstanceName = accountScope?.instanceActorId?.host
            let db = appDatabase
            metaObservationTask = Task { [weak self] in
                for await items in db.observeMetaCommunities(forAccountId: accountRowId, instanceHost: host) {
                    if Task.isCancelled { break }
                    await MainActor.run { self?.metaCommunities = items }
                }
            }
            if let keychainId = accountScope?.accountKeychainId, let service = metaCommunityService {
                Task { await service.refreshInstance(host: host, siteName: nil, forAccountKeychainId: keychainId) }
            }
        }
```
   Add `@ObservationIgnored private var metaObservationTask: Task<Void, Never>?` and cancel it in `deinit` alongside the others.
4. Add the actions:
```swift
    func toggleSubscribe(_ item: MetaCommunityListItem) {
        guard let scope = accountScope else { return }
        let subscribe = !item.subscribedState.isSubscribed
        Task {
            try? await scope.lemmyService.setSubscribed(
                serverCommunityId: Lemmy.CommunityID(item.serverCommunityId), subscribed: subscribe)
        }
    }

    func toggleFavorite(_ item: MetaCommunityListItem) {
        guard let keychainId = accountScope?.accountKeychainId else { return }
        if item.isFavorite {
            appDatabase.unfavoriteCommunitySync(forKeychainId: keychainId, communityActorId: item.communityActorId)
        } else {
            appDatabase.favoriteCommunitySync(forKeychainId: keychainId, communityActorId: item.communityActorId)
        }
    }
```
   Add `import LemmyKit` for `Lemmy.CommunityID` if not present. The observation re-emits after both actions (subscribe via the outbox's optimistic mirror; favourite via the favorites table), so the UI updates without manual state juggling.

- [ ] **Step 4: Pass the new args from the view controller**

In `SubscriptionsViewController.swift`, find the `SubscriptionsViewModel(` construction and add:
```swift
            accountScope: dependencies.<accountService>.scope(forAccountKeychainId: accountKeychainId),
            metaCommunityService: dependencies.<metaCommunityService>,
```
Confirm the VC's `Dependencies` typealias includes `HasAccountService` and add `HasMetaCommunityService` to it (and to `OwnDependencies`). If the VC currently builds the VM without an account keychain id (signed-out), pass `accountScope: nil, metaCommunityService: nil`.

- [ ] **Step 5: Run tests + build, then commit**

Run: `make project && make test-only ONLY=SpudTests && make build`
Expected: PASS + BUILD SUCCEEDED.
```bash
git add Spud/Scenes/Subscriptions/SubscriptionsViewModel.swift \
        Spud/Scenes/Subscriptions/SubscriptionsViewController.swift \
        SpudTests/SubscriptionsMetaSectionViewModelTests.swift
git commit -m "feat: drive the About-instance meta section from the subscriptions view model"
```

---

### Task 11: "About <instance>" section — SwiftUI rendering

**Files:**
- Modify: `Spud/Scenes/Subscriptions/SubscriptionsView.swift`
- Test: `SpudSnapshotTests/SubscriptionsAboutSectionSnapshotTests.swift`

**Interfaces:**
- Consumes: `viewModel.metaCommunities`, `viewModel.metaInstanceName`, `viewModel.toggleSubscribe`, `viewModel.toggleFavorite`, `MetaCommunityListItem`, `MetaConfidence`.

- [ ] **Step 1: Add the Section**

In `SubscriptionsView.swift`, inside the `List`, when `viewModel.searchText.isEmpty` and `!viewModel.metaCommunities.isEmpty`, add a section ABOVE `SubscriptionsDiscoverView` (or right after it). Split high vs low confidence; low ones go under a disclosure:

```swift
            if viewModel.searchText.isEmpty, !viewModel.metaCommunities.isEmpty {
                Section(viewModel.metaInstanceName.map { "About \($0)" } ?? "About this instance") {
                    ForEach(viewModel.metaCommunities.filter { $0.confidence == .high }) { item in
                        MetaCommunityAboutRow(item: item,
                            onSubscribe: { viewModel.toggleSubscribe(item) },
                            onFavorite: { viewModel.toggleFavorite(item) })
                    }
                    let low = viewModel.metaCommunities.filter { $0.confidence == .low }
                    if !low.isEmpty {
                        DisclosureGroup("More on this instance") {
                            ForEach(low) { item in
                                MetaCommunityAboutRow(item: item,
                                    onSubscribe: { viewModel.toggleSubscribe(item) },
                                    onFavorite: { viewModel.toggleFavorite(item) })
                            }
                        }
                    }
                }
            }
```

- [ ] **Step 2: Add the row view**

Add `MetaCommunityAboutRow` in the same file (model layout on `SubscriptionsCommunityView`; inline Subscribe reuses the label copy centralised in `CommunitySubscribeButtonLabel.swift`):

```swift
struct MetaCommunityAboutRow: View {
    let item: MetaCommunityListItem
    let onSubscribe: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SubscriptionsCommunityIconView(communityName: item.name)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title ?? item.name).foregroundStyle(Color(.label))
                    MetaCommunityBadge()
                }
                Text("c/\(item.name)").font(.footnote).foregroundStyle(Color(.tertiaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite")
            Button(action: onSubscribe) {
                Text(item.subscribedState.isSubscribed ? "Subscribed" : "Subscribe")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Snapshot test**

Create `SpudSnapshotTests/SubscriptionsAboutSectionSnapshotTests.swift`. Build a `SubscriptionsView` (or just the section list) with a `SubscriptionsViewModel` whose `metaCommunities` is seeded to a mix of high + low items (construct `MetaCommunityListItem`s directly). Render in light + dark, record, verify. If constructing the full VM is heavy, snapshot a small wrapper `List { …the same section… }` fed by a fixed `[MetaCommunityListItem]`.

- [ ] **Step 4: Build + snapshot**

Run: `make project && make build && make snapshot`
Expected: BUILD SUCCEEDED; snapshots PASS.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Subscriptions/SubscriptionsView.swift \
        SpudSnapshotTests/SubscriptionsAboutSectionSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/SubscriptionsAboutSectionSnapshotTests
git commit -m "feat: add About-instance meta section to the Communities tab"
```

---

### Task 12 (optional): Instance About screen meta section

Lowest priority — the core asks (badge + home section) are complete after Task 11. Ship this only if time allows; it can be a follow-up.

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift`

**Interfaces:**
- Consumes: `MetaCommunityServiceType`, `AppDatabase.observeMetaCommunities`, the existing `communitiesContainer` card-row builder in the same controller (`InstanceExploreViewController.swift:323-402`).

- [ ] **Step 1:** In `InstanceExploreViewController`, add a sibling section in the vertical `stack` (near `aboutServerView`, ~line 187) titled "About this instance", populated by reusing the controller's existing compact community-row builder.
- [ ] **Step 2:** Trigger resolution for the visited host: call `dependencies.metaCommunityService.refreshInstance(host: <visitedHost>, siteName: <site.name>, forAccountKeychainId: <keychainId>)` in the controller's load path, and observe `appDatabase.observeMetaCommunities(forAccountId:instanceHost:)` for the visited host to populate the section. Hide the section when empty. Add `HasMetaCommunityService` to the controller's `Dependencies`.
- [ ] **Step 3:** Build + snapshot (extend `InstanceDetailSnapshotTests` with a seeded meta case). Record, verify.
- [ ] **Step 4:** Commit: `git commit -m "feat: surface meta communities on the instance about screen"`

---

### Task 13: Documentation

**Files:**
- Create: `docs/features/instance-meta-communities.md`
- Modify: `docs/features/README.md`

- [ ] **Step 1:** Write `docs/features/instance-meta-communities.md` covering: what a meta community is, the heuristic classifier (strong vs broad, name-match, the domain-label equality rule + fuzziness caveat), where badges appear, the "About <instance>" section behavior (always visible, one-tap Subscribe/Favourite, high-vs-low disclosure), the per-account cache + candidate-resolution refresh, and the explicit non-goals (suggest-only, no push-on-new-post). No `.swift` links. Follow the structure of a sibling doc (e.g. `docs/features/discover.md`).
- [ ] **Step 2:** Add an entry to `docs/features/README.md` — both the capability table and the by-area map, per the project's doc discipline.
- [ ] **Step 3:** Commit:
```bash
git add docs/features/instance-meta-communities.md docs/features/README.md
git commit -m "docs: document instance meta communities"
```

---

## Final verification

- [ ] `make project && make test` (full plan) — all unit targets green.
- [ ] `make snapshot` — all snapshots green; new snapshots visually inspected.
- [ ] `make build` — BUILD SUCCEEDED.
- [ ] Manual on-device / simulator sanity: sign into an account whose instance has meta communities (e.g. a test instance seeded with an `announcements`/`meta` community), open the Communities tab, confirm the "About <instance>" section appears with one-tap Subscribe/Favourite, and confirm badges render in Discover / search / community header. (UI-test automation is unreliable here per project notes — verify by screenshot per the "verify tap-gated UI" pattern.)
- [ ] Broad-review the whole branch (fresh reviewer) before merge.

## Self-review notes (coverage vs spec)

- Spec §1 classifier → Task 1 (incl. two-tier confidence, name-match, domain-label equality-not-substring, centralized keywords).
- Spec §2 badge across surfaces → Tasks 6 (Discover), 7 (Communities tab), 8 (search), 9 (community header).
- Spec §3 "About <instance>" section, always-visible, one-tap, high/low disclosure, no auto-act → Tasks 10-11.
- Spec §4 instance About screen → Task 12 (optional).
- Spec §5 cache record + queries + resolution service + candidate resolution + freshness throttle → Tasks 2, 3, 4, 5.
- Spec §6 non-goals (suggest-only, no push) → enforced in Global Constraints + Task 10 actions (one-tap only).
- Spec §7 testing (classifier unit incl. negatives, service with stub seam, snapshots, state join) → Tasks 1, 3, 4, 6-11.
- Spec Risks (fuzzy domain label) → Task 1 equality-only rule + `domainLabelMatchIsEqualityNotSubstring` test.
