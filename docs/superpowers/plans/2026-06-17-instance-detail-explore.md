# Instance Detail — Explore + Onboarding Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app "explore an instance" screen (Markdown sidebar, admins, federated one-tap Join, health cross-link) and extend the existing onboarding instance-detail screen with Admins + top-3 Communities sections, backed by persisting site admins in GRDB.

**Architecture:** A new GRDB `SiteAdminRecord` (populated from the already-fetched-but-discarded `GetSite.admins`) plus a small set of reusable UIKit component views extracted/created under `Spud/Scenes/Account/InstanceDetail/Components/`. Two view controllers compose those components: the existing `InstanceDetailViewController` (onboarding, signup-gated) gains two sections; a new `InstanceExploreViewController` (+ `@Observable` `InstanceExploreViewModel`) is the browse screen. In-app instance taps repoint to the explore screen.

**Tech Stack:** UIKit, GRDB, LemmyKit (`Components.Schemas.*`), SpudMarkdownKit, swift-snapshot-testing. Swift 6 language mode.

## Global Constraints

- iOS 18+ SDK; shipped targets (Spud, SpudDataKit) at Swift 6.0 language mode.
- No emojis in code, comments, commit messages.
- Conventional commit subjects (`feat:`, `refactor:`, `test:`); small focused commits.
- No Combine. View models are `@Observable`; bind UI via `ObservationStream.values(of:)`.
- GRDB migrations are append-only — add a new `registerMigration("vN_…")`; never edit a shipped one. Current latest is `v15_postInteractionFts`, so the new one is `v16_siteAdmin`.
- GRDB observations from non-isolated AsyncStream init closures MUST pass `scheduling: .async(onQueue: .global(qos: .userInitiated))` (never the default main-queue scheduler).
- Markdown renders via SpudMarkdownKit (`MarkdownBlockCache.shared.blocks(for:)` + `MarkdownBodyView`), never a hand-rolled parser.
- Colours come from `SpudUIKit` semantic tokens (`Theme.*`) + `UIColor.system*`; accent is `ThemeManager.currentAccentColor`. No new colour assets.
- Stage explicit paths when committing (never `git add -A`); `.remember/remember.md` is a session buffer — do not stage it.
- Build: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
- Unit tests (single class): `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:<Target>/<Class> test`
- Snapshot tests (single class): `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudSnapshotTests/<Class> test` — first run records missing references and FAILS; rerun verifies. Snapshot reference PNGs are git-annex-tracked (unlocked); `git add` them after recording.
- After adding/removing source files, regenerate the project: `make project` (XcodeGen; `project.pbxproj` is gitignored).

---

## File Structure

**Create (SpudDataKit):**
- `SpudDataKit/Services/AppDatabase/Records/SiteAdminRecord.swift` — admin row.
- `SpudDataKit/Services/AppDatabase/SiteAdminObservations.swift` — sync read + AsyncStream keyed by instance actor id.

**Modify (SpudDataKit):**
- `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` — add `v16_siteAdmin`.
- `SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift` — persist admins in `upsertSite`.

**Create (Spud app — shared components under `Spud/Scenes/Account/InstanceDetail/Components/`):**
- `InstanceHealthStyle.swift` — pure helpers: level→`UIColor`, trust/registration symbols + short labels, compact count formatting.
- `InstanceScoreRingView.swift` — extracted score donut.
- `InstanceWrapView.swift` — extracted flow layout.
- `InstanceHealthPillView.swift` — tinted icon+label pill.
- `InstanceAdminsView.swift` — admins section (+ unavailable / anonymous states).
- `InstanceCommunityRowView.swift` — community row + Join/Joined pill (or chevron) + display helpers.
- `InstanceAboutServerView.swift` — collapsible Markdown sidebar.
- `InstanceBannerHeaderView.swift` — banner + icon + identity + glass nav buttons.

**Create (Spud app — explore screen):**
- `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift`
- `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewModel.swift`

**Modify (Spud app):**
- `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` — adopt extracted components; add Admins + top-3 Communities; add `showsActions`; lazy admin/community load.
- `Spud/Scenes/Community/Content/CommunityHeaderView.swift` — tappable handle + `onInstanceTapped`.
- `Spud/Scenes/Community/Content/CommunityViewController.swift` — wire `onInstanceTapped` → explore.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — `openInstance` → explore.
- `Spud/Scenes/Discover/DiscoverViewController.swift` — `openInstanceDetail` → explore.

**Create (tests):**
- `SpudDataKitTests/SiteAdminRecordTests.swift`
- `SpudDataKitTests/SiteAdminImportTests.swift`
- `SpudDataKitTests/InstanceCommunityDisplayTests.swift`
- `SpudSnapshotTests/InstanceExploreSnapshotTests.swift`

**Modify (tests):**
- `SpudSnapshotTests/InstanceDetailSnapshotTests.swift` — re-record references (screen grew).

---

## Task 1: `SiteAdminRecord` + migration

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/Records/SiteAdminRecord.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append after `v15_postInteractionFts`)
- Test: `SpudDataKitTests/SiteAdminRecordTests.swift`

**Interfaces:**
- Produces: `SiteAdminRecord` (struct with `id: Int64?`, `siteId: Int64`, `ordinal: Int`, `personActorId: String`, `personName: String`, `displayName: String?`, `avatarUrl: String?`); table `siteAdmin`.

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/SiteAdminRecordTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import XCTest
@testable import SpudDataKit

final class SiteAdminRecordTests: XCTestCase {
    func test_insertAndFetch_roundTrips() throws {
        let appDatabase = try AppDatabase.inMemory()
        try appDatabase.writer.write { db in
            // A site row is required for the foreign key.
            var instance = InstanceRecord(actorId: "https://lemmy.world", createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, name: "Lemmy World")
            try site.insert(db)

            var admin = SiteAdminRecord(
                siteId: site.id!, ordinal: 0,
                personActorId: "https://lemmy.world/u/ruud",
                personName: "ruud", displayName: "Ruud", avatarUrl: nil
            )
            try admin.insert(db)

            let fetched = try SiteAdminRecord.fetchAll(db)
            XCTAssertEqual(fetched.count, 1)
            XCTAssertEqual(fetched[0].personName, "ruud")
            XCTAssertEqual(fetched[0].displayName, "Ruud")
            XCTAssertEqual(fetched[0].ordinal, 0)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminRecordTests test`
Expected: FAIL — `cannot find 'SiteAdminRecord' in scope`.

- [ ] **Step 3: Create the record**

Create `SpudDataKit/Services/AppDatabase/Records/SiteAdminRecord.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

/// An administrator of a Lemmy site, sourced from `GetSiteResponse.admins`.
/// One row per admin per ``SiteRecord``; `ordinal` preserves the API order
/// (ordinal 0 is treated as the site owner by the UI).
public struct SiteAdminRecord: Codable, Sendable, Equatable, Identifiable {
    public static let databaseTableName = "siteAdmin"

    public var id: Int64?
    public var siteId: Int64
    public var ordinal: Int
    public var personActorId: String
    public var personName: String
    public var displayName: String?
    public var avatarUrl: String?

    public init(
        id: Int64? = nil,
        siteId: Int64,
        ordinal: Int,
        personActorId: String,
        personName: String,
        displayName: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.siteId = siteId
        self.ordinal = ordinal
        self.personActorId = personActorId
        self.personName = personName
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

extension SiteAdminRecord: FetchableRecord, MutablePersistableRecord {
    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public extension SiteAdminRecord {
    enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let siteId = Column(CodingKeys.siteId)
        public static let ordinal = Column(CodingKeys.ordinal)
    }

    /// Human label: display name if present, else the bare username.
    var label: String {
        displayName ?? personName
    }

    /// Role label shown in the UI. Lemmy exposes no explicit owner flag, so the
    /// first admin (ordinal 0) is treated as the owner. Documented approximation.
    var roleLabel: String {
        ordinal == 0 ? "Owner" : "Admin"
    }
}
```

- [ ] **Step 4: Add the migration**

In `AppDatabase+Migrations.swift`, immediately after the `v15_postInteractionFts` migration block (and before `return migrator`), add:

```swift
        migrator.registerMigration("v16_siteAdmin") { db in
            try db.create(table: "siteAdmin") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer)
                    .notNull()
                    .indexed()
                    .references("site", onDelete: .cascade)
                t.column("ordinal", .integer).notNull().defaults(to: 0)
                t.column("personActorId", .text).notNull()
                t.column("personName", .text).notNull()
                t.column("displayName", .text)
                t.column("avatarUrl", .text)
            }
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminRecordTests test`
Expected: PASS. (`AppDatabase.inMemory()` runs all migrations, including `v16_siteAdmin`.)

- [ ] **Step 6: Commit**

```bash
make project
git add SpudDataKit/Services/AppDatabase/Records/SiteAdminRecord.swift \
        SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift \
        SpudDataKitTests/SiteAdminRecordTests.swift
git commit -m "feat(explorer): add SiteAdminRecord + v16 migration"
```

---

## Task 2: Persist admins in `SiteImporter`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift`
- Test: `SpudDataKitTests/SiteAdminImportTests.swift`

**Interfaces:**
- Consumes: `SiteAdminRecord` (Task 1), `AppDatabase.upsertSite(from:)`.
- Produces: after `upsertSite(from:)`, `siteAdmin` rows for the resolved site mirror `response.admins` (replace-all, ordered).

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/SiteAdminImportTests.swift`. (Reuse the existing test fakes for `GetSiteResponse` — the SpudDataKitTests target already builds `Components.Schemas.*` fixtures; mirror whatever helper the other importer tests use to construct a `GetSiteResponse`. The test below names that helper `Self.makeGetSiteResponse`; implement it alongside, or reuse an existing fixture factory if one exists in the target.)

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import LemmyKit
import XCTest
@testable import SpudDataKit

final class SiteAdminImportTests: XCTestCase {
    func test_upsertSite_storesAdminsInOrder() async throws {
        let appDatabase = try AppDatabase.inMemory()
        let response = Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [
                Self.personView(name: "ruud", display: "Ruud", actorId: "https://lemmy.world/u/ruud"),
                Self.personView(name: "milan", display: nil, actorId: "https://lemmy.world/u/milan"),
            ]
        )

        let (_, siteId) = try await appDatabase.upsertSite(from: response)

        let admins = try appDatabase.writer.read { db in
            try SiteAdminRecord
                .filter(SiteAdminRecord.Columns.siteId == siteId)
                .order(SiteAdminRecord.Columns.ordinal)
                .fetchAll(db)
        }
        XCTAssertEqual(admins.map(\.personName), ["ruud", "milan"])
        XCTAssertEqual(admins.map(\.ordinal), [0, 1])
        XCTAssertEqual(admins[0].displayName, "Ruud")
        XCTAssertNil(admins[1].displayName)
    }

    func test_upsertSite_replacesAdminsOnReimport() async throws {
        let appDatabase = try AppDatabase.inMemory()
        _ = try await appDatabase.upsertSite(from: Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [Self.personView(name: "old", display: nil, actorId: "https://lemmy.world/u/old")]
        ))
        let (_, siteId) = try await appDatabase.upsertSite(from: Self.makeGetSiteResponse(
            actorId: "https://lemmy.world",
            admins: [Self.personView(name: "new", display: nil, actorId: "https://lemmy.world/u/new")]
        ))

        let names = try appDatabase.writer.read { db in
            try SiteAdminRecord.filter(SiteAdminRecord.Columns.siteId == siteId).fetchAll(db).map(\.personName)
        }
        XCTAssertEqual(names, ["new"])
    }
}
```

Add the fixture helpers at the bottom of the file (fill the remaining required `PersonView` / `GetSiteResponse` fields by copying the construction pattern an existing importer test in `SpudDataKitTests` already uses — the schema requires several non-optional fields):

```swift
extension SiteAdminImportTests {
    static func personView(name: String, display: String?, actorId: String) -> Components.Schemas.PersonView {
        // Construct Components.Schemas.PersonView with a Person whose
        // name/display_name/actor_id/avatar are set; copy the full required-field
        // construction from an existing SpudDataKitTests PersonView fixture.
        fatalError("Replace with the project's PersonView fixture construction")
    }

    static func makeGetSiteResponse(actorId: String, admins: [Components.Schemas.PersonView]) -> Components.Schemas.GetSiteResponse {
        // Construct a minimal GetSiteResponse whose site_view.site.actor_id == actorId
        // and whose admins == admins; copy required-field construction from the
        // existing SpudDataKitTests GetSiteResponse fixture.
        fatalError("Replace with the project's GetSiteResponse fixture construction")
    }
}
```

NOTE to implementer: before running, replace the two `fatalError` fixture helpers with real constructions. Search `SpudDataKitTests` for an existing `GetSiteResponse`/`PersonView` fixture (the target already has importer-test fakes per the repo notes) and reuse its field set. If none exists, build them field-by-field from `Components.Schemas` in DerivedData `Types.swift`.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminImportTests test`
Expected: FAIL — admins not stored (zero rows).

- [ ] **Step 3: Persist admins in `upsertSite`**

In `SiteImporter.swift`, inside `upsertSite(from:)`'s `writer.write` block, after `resolvedSiteId` is assigned (just before `return (instanceId, resolvedSiteId)`), insert:

```swift
            try Self.applyAdmins(response.admins, siteId: resolvedSiteId, db: db)
```

Then add this private helper to the same `public extension AppDatabase` (next to `apply(response:to:now:)`):

```swift
    /// Replaces the site's admin rows with `admins`, preserving API order via
    /// `ordinal`. `ON DELETE CASCADE` on the FK is not relied on here; we delete
    /// the prior set explicitly so a shrinking admin list converges.
    private static func applyAdmins(
        _ admins: [Components.Schemas.PersonView],
        siteId: Int64,
        db: Database
    ) throws {
        try SiteAdminRecord
            .filter(Column("siteId") == siteId)
            .deleteAll(db)
        for (ordinal, view) in admins.enumerated() {
            var record = SiteAdminRecord(
                siteId: siteId,
                ordinal: ordinal,
                personActorId: view.person.actor_id,
                personName: view.person.name,
                displayName: view.person.display_name,
                avatarUrl: view.person.avatar
            )
            try record.insert(db)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminImportTests test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/AppDatabase/Importers/SiteImporter.swift \
        SpudDataKitTests/SiteAdminImportTests.swift
git commit -m "feat(explorer): persist site admins from GetSite"
```

---

## Task 3: `SiteAdminObservations`

**Files:**
- Create: `SpudDataKit/Services/AppDatabase/SiteAdminObservations.swift`
- Test: extend `SpudDataKitTests/SiteAdminImportTests.swift` (or a new `SiteAdminObservationsTests.swift`)

**Interfaces:**
- Consumes: `SiteAdminRecord`, `InstanceActorId`.
- Produces:
  - `AppDatabase.siteAdminsSync(forInstanceActorId: InstanceActorId) -> [SiteAdminRecord]`
  - `AppDatabase.observeSiteAdmins(forInstanceActorId: InstanceActorId) -> AsyncStream<[SiteAdminRecord]>`

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/SiteAdminObservationsTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB
import XCTest
@testable import SpudDataKit

final class SiteAdminObservationsTests: XCTestCase {
    func test_siteAdminsSync_returnsAdminsForInstanceOrdered() throws {
        let appDatabase = try AppDatabase.inMemory()
        let actorId = "https://lemmy.world"
        try appDatabase.writer.write { db in
            var instance = InstanceRecord(actorId: actorId, createdAt: Date(), updatedAt: Date())
            try instance.insert(db)
            var site = SiteRecord(instanceId: instance.id!, name: "Lemmy World")
            try site.insert(db)
            for (i, name) in ["ruud", "milan"].enumerated() {
                var a = SiteAdminRecord(siteId: site.id!, ordinal: i, personActorId: "\(actorId)/u/\(name)", personName: name)
                try a.insert(db)
            }
        }

        let instance = try XCTUnwrap(InstanceActorId(from: actorId))
        let admins = appDatabase.siteAdminsSync(forInstanceActorId: instance)
        XCTAssertEqual(admins.map(\.personName), ["ruud", "milan"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminObservationsTests test`
Expected: FAIL — `value of type 'AppDatabase' has no member 'siteAdminsSync'`.

- [ ] **Step 3: Implement the observations**

Create `SpudDataKit/Services/AppDatabase/SiteAdminObservations.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

public extension AppDatabase {
    /// One-shot read of a site's admins (ordered) for the given instance.
    func siteAdminsSync(forInstanceActorId actorId: InstanceActorId) -> [SiteAdminRecord] {
        do {
            return try writer.read { db in
                try Self.fetchSiteAdmins(in: db, instanceActorId: actorId.actorId)
            }
        } catch {
            logger.error("siteAdminsSync failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Live observation of a site's admins for the given instance.
    func observeSiteAdmins(forInstanceActorId actorId: InstanceActorId) -> AsyncStream<[SiteAdminRecord]> {
        let normalized = actorId.actorId
        let observation = ValueObservation
            .tracking { db in
                try Self.fetchSiteAdmins(in: db, instanceActorId: normalized)
            }
            .removeDuplicates()
        return AsyncStream { continuation in
            let cancellable = observation.start(in: writer, scheduling: .async(onQueue: .global(qos: .userInitiated))) { error in
                logger.error("observeSiteAdmins failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            } onChange: { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }

    private static func fetchSiteAdmins(in db: Database, instanceActorId: String) throws -> [SiteAdminRecord] {
        try SiteAdminRecord.fetchAll(db, sql: """
                SELECT siteAdmin.*
                FROM siteAdmin
                JOIN site ON site.id = siteAdmin.siteId
                JOIN instance ON instance.id = site.instanceId
                WHERE instance.actorId = ?
                ORDER BY siteAdmin.ordinal ASC
            """, arguments: [instanceActorId])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudDataKitTests/SiteAdminObservationsTests test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
make project
git add SpudDataKit/Services/AppDatabase/SiteAdminObservations.swift \
        SpudDataKitTests/SiteAdminObservationsTests.swift
git commit -m "feat(explorer): observe site admins by instance"
```

---

## Task 4: Extract shared primitives (`InstanceHealthStyle`, score ring, wrap view, pill)

This refactor lifts the private helpers currently inside `InstanceDetailViewController` into reusable files so both screens share them, with no visual change.

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift`
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceScoreRingView.swift`
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceWrapView.swift`
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthPillView.swift`
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift`
- Test: `SpudDataKitTests` is not applicable (UI); covered by build + existing snapshots.

**Interfaces:**
- Produces:
  - `enum InstanceHealthStyle` with `static func color(for: HealthLevel) -> UIColor`, `static func trustSymbol(_: HealthLevel) -> String`, `static func registrationSymbol(_: ExplorerRegistrationMode) -> String`, `static func registrationShort(_: ExplorerRegistrationMode) -> String`, `static func formatCount(_: Int64?) -> String`.
  - `final class InstanceScoreRingView: UIView` with `func configure(score100: Double?, color: UIColor)`.
  - `final class InstanceWrapView: UIView` with `var hSpacing/vSpacing: CGFloat` and `func setItems(_: [UIView])`.
  - `final class InstanceHealthPillView: UIView` with `init(symbol: String, text: String, color: UIColor)`.

- [ ] **Step 1: Create `InstanceHealthStyle.swift`**

Move the `color(for:)`, `trustSymbol(_:)`, `registrationSymbol(_:)`, `registrationShort(_:)`, `formatCount(_:)`, and `trim(_:)` logic out of `InstanceDetailViewController` into static methods:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Pure mapping of Explorer health/quality levels to colours, SF Symbols, and
/// compact strings. Shared by both instance-detail screens.
enum InstanceHealthStyle {
    static func color(for level: HealthLevel) -> UIColor {
        switch level {
        case .good: .systemGreen
        case .ok: .systemOrange
        case .bad: .systemRed
        case .unknown: .tertiaryLabel
        }
    }

    static func trustSymbol(_ level: HealthLevel) -> String {
        switch level {
        case .good: "checkmark.shield.fill"
        case .ok: "shield"
        case .bad: "exclamationmark.triangle.fill"
        case .unknown: "shield"
        }
    }

    static func registrationSymbol(_ mode: ExplorerRegistrationMode) -> String {
        switch mode {
        case .open: "globe"
        case .requireApplication: "doc.text"
        case .closed: "lock.fill"
        case .unknown: "globe"
        }
    }

    static func registrationShort(_ mode: ExplorerRegistrationMode) -> String {
        switch mode {
        case .open: "Open"
        case .requireApplication: "Apply"
        case .closed: "Closed"
        case .unknown: "—"
        }
    }

    /// Compact count (e.g. "1.2K", "32K"). Returns "—" for nil/zero.
    static func formatCount(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        let n = Double(value)
        switch value {
        case 1_000_000...: return trim(n / 1_000_000) + "M"
        case 1000...: return trim(n / 1000) + "K"
        default: return "\(value)"
        }
    }

    private static func trim(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
```

- [ ] **Step 2: Create `InstanceScoreRingView.swift`**

Move the existing `ScoreRingView` class (lines ~814-885 of `InstanceDetailViewController.swift`) into this file **verbatim**, renamed `InstanceScoreRingView` and made non-private (`final class InstanceScoreRingView: UIView`). Keep `init()`, `configure(score100:color:)`, and `layoutSubviews()` exactly as they are.

- [ ] **Step 3: Create `InstanceWrapView.swift`**

Move the existing `WrapView` class (lines ~891-941) into this file **verbatim**, renamed `InstanceWrapView` and made non-private. Keep `hSpacing`, `vSpacing`, `setItems(_:)`, `layoutSubviews()`, `intrinsicContentSize`, and `layout(width:apply:)` exactly as they are.

- [ ] **Step 4: Create `InstanceHealthPillView.swift`**

Extract the `makePill(symbol:text:level:)` body into a reusable view that takes a resolved colour:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A tinted health/quality pill: SF Symbol + label on a translucent fill.
final class InstanceHealthPillView: UIView {
    init(symbol: String, text: String, color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = color.withAlphaComponent(0.15)
        layer.cornerRadius = 8
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = color
        icon.contentMode = .scaleAspectFit
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = color
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            icon.widthAnchor.constraint(equalToConstant: 13.5),
            icon.heightAnchor.constraint(equalToConstant: 13.5),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 5: Update `InstanceDetailViewController` to use the extracted types**

In `InstanceDetailViewController.swift`: delete the now-moved `ScoreRingView` and `WrapView` class definitions; delete the private `color(for:)`, `trustSymbol`, `registrationSymbol`, `registrationShort`, `formatCount`, `trim`, and `makePill` methods. Replace usages:
- `ScoreRingView()` → `InstanceScoreRingView()`
- `WrapView()` → `InstanceWrapView()`
- `color(for: x)` → `InstanceHealthStyle.color(for: x)`
- `trustSymbol(x)` → `InstanceHealthStyle.trustSymbol(x)`
- `registrationSymbol(x)` → `InstanceHealthStyle.registrationSymbol(x)`
- `registrationShort(x)` → `InstanceHealthStyle.registrationShort(x)`
- `formatCount(x)` → `InstanceHealthStyle.formatCount(x)`
- `makePill(symbol:text:level:)` → `InstanceHealthPillView(symbol: ..., text: ..., color: InstanceHealthStyle.color(for: level))`

- [ ] **Step 6: Regenerate, build, and verify existing snapshots are unchanged**

Run: `make project`
Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.
Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudSnapshotTests/InstanceDetailSnapshotTests test`
Expected: PASS — extraction is behaviour-preserving, so references still match. (If it fails on pixels, the extraction changed layout; reconcile before continuing — do NOT re-record here.)

- [ ] **Step 7: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/Components/ \
        Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift
git commit -m "refactor(instance-detail): extract shared primitives into Components"
```

---

## Task 5: `InstanceCommunityRowView` + display helpers

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceCommunityRowView.swift`
- Test: `SpudDataKitTests/InstanceCommunityDisplayTests.swift` (pure helpers live in SpudDataKit-free code, so test via the Spud test target instead — put the test in `SpudTests` if SpudDataKitTests cannot import Spud). Use the Spud unit test target.

**Interfaces:**
- Consumes: `CommunityListRow` (SpudDataKit), `InstanceHealthStyle.formatCount`.
- Produces:
  - `enum InstanceCommunityDisplay { static func subtitle(for: CommunityListRow) -> String }`
  - `final class InstanceCommunityRowView: UIView` with `enum Action { case join, chevron }`, `init(row:, action:, joined:, accent:)`, and `var onJoinTapped: (() -> Void)?`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/InstanceCommunityDisplayTests.swift` (Spud unit test target — it can `@testable import Spud`):

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

final class InstanceCommunityDisplayTests: XCTestCase {
    func test_subtitle_showsSubscribersAndWeeklyActive() {
        let row = CommunityListRow(
            id: 1, communityUrl: "https://lemmy.world/c/technology",
            instanceHost: "lemmy.world", name: "technology", title: "Technology",
            numberOfSubscribers: 286_000, usersActiveWeek: 1200
        )
        XCTAssertEqual(InstanceCommunityDisplay.subtitle(for: row), "286K subscribers · 1.2K/wk")
    }

    func test_subtitle_degradesWeeklyActiveToDash() {
        let row = CommunityListRow(
            id: 1, communityUrl: "https://x/c/y", instanceHost: "x",
            name: "y", numberOfSubscribers: 0, usersActiveWeek: 0
        )
        XCTAssertEqual(InstanceCommunityDisplay.subtitle(for: row), "— subscribers · —/wk")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudTests/InstanceCommunityDisplayTests test`
Expected: FAIL — `InstanceCommunityDisplay` / `InstanceCommunityRowView` undefined.

- [ ] **Step 3: Implement the row view + display helper**

Create `Spud/Scenes/Account/InstanceDetail/Components/InstanceCommunityRowView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// Subtitle string for a community row: "N subscribers · M/wk". The lemmyverse
/// dataset has no posts/week figure, so weekly-active users stand in for it.
enum InstanceCommunityDisplay {
    static func subtitle(for row: CommunityListRow) -> String {
        let subs = InstanceHealthStyle.formatCount(row.numberOfSubscribers)
        let week = InstanceHealthStyle.formatCount(row.usersActiveWeek)
        return "\(subs) subscribers · \(week)/wk"
    }
}

/// A community row: square icon mark + `c/name` + subtitle, trailed by either a
/// Join/Joined pill (explore) or a chevron (onboarding's top-3 list).
final class InstanceCommunityRowView: UIView {
    enum Action { case join, chevron }

    var onJoinTapped: (() -> Void)?

    private let joinButton = UIButton(type: .system)
    private var joined: Bool
    private let accent: UIColor

    init(row: CommunityListRow, action: Action, joined: Bool, accent: UIColor) {
        self.joined = joined
        self.accent = accent
        super.init(frame: .zero)

        let icon = InstanceCommunityRowView.iconMark(for: row)

        let nameLabel = UILabel()
        nameLabel.text = "c/\(row.name)"
        nameLabel.font = .systemFont(ofSize: 14.5, weight: .bold)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail

        let subtitle = UILabel()
        subtitle.text = InstanceCommunityDisplay.subtitle(for: row)
        subtitle.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .tertiaryLabel

        let text = UIStackView(arrangedSubviews: [nameLabel, subtitle])
        text.axis = .vertical
        text.spacing = 1

        let trailing: UIView
        switch action {
        case .join:
            configureJoinButton()
            trailing = joinButton
        case .chevron:
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.tintColor = .tertiaryLabel
            chevron.contentMode = .scaleAspectFit
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            trailing = chevron
        }

        let stack = UIStackView(arrangedSubviews: [icon, text, trailing])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = .init(top: 10, left: 13, bottom: 10, right: 13)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Optimistically reflect a join/leave without rebuilding the row.
    func setJoined(_ value: Bool) {
        joined = value
        configureJoinButton()
    }

    private func configureJoinButton() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.imagePadding = 4
        if joined {
            config.title = NSLocalizedString("Joined", comment: "Instance community joined pill")
            config.image = UIImage(systemName: "checkmark")
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .secondaryLabel
        } else {
            config.title = NSLocalizedString("Join", comment: "Instance community join pill")
            config.image = UIImage(systemName: "plus")
            config.baseBackgroundColor = accent
            config.baseForegroundColor = .white
        }
        joinButton.configuration = config
        joinButton.setContentHuggingPriority(.required, for: .horizontal)
        joinButton.removeTarget(nil, action: nil, for: .touchUpInside)
        joinButton.addAction(UIAction { [weak self] _ in self?.onJoinTapped?() }, for: .touchUpInside)
        joinButton.accessibilityLabel = joined
            ? NSLocalizedString("Joined", comment: "Instance community joined pill a11y")
            : NSLocalizedString("Join", comment: "Instance community join pill a11y")
    }

    private static func iconMark(for row: CommunityListRow) -> UIView {
        let container = UIView()
        container.layer.cornerRadius = 10
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true
        let hue = CGFloat(row.instanceHost.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        container.backgroundColor = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        let letter = UILabel()
        letter.text = String((row.title ?? row.name).prefix(1)).uppercased()
        letter.font = .systemFont(ofSize: 16, weight: .bold)
        letter.textColor = .white
        letter.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(letter)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `make project` then `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudTests/InstanceCommunityDisplayTests test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/Components/InstanceCommunityRowView.swift \
        SpudTests/InstanceCommunityDisplayTests.swift
git commit -m "feat(instance-detail): community row view + subtitle helper"
```

---

## Task 6: `InstanceAdminsView`

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceAdminsView.swift`
- Test: build-only (rendered in snapshots later).

**Interfaces:**
- Consumes: `SiteAdminRecord`, `SectionHeaderView` (defined inline here as `InstanceSectionHeader`).
- Produces:
  - `enum InstanceAdminsState { case loading; case unavailable; case anonymous; case admins([SiteAdminRecord]) }`
  - `final class InstanceAdminsView: UIView` with `func update(_ state: InstanceAdminsState)`.

- [ ] **Step 1: Implement the view**

Create `Spud/Scenes/Account/InstanceDetail/Components/InstanceAdminsView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

enum InstanceAdminsState: Equatable {
    case loading
    case unavailable
    case anonymous
    case admins([SiteAdminRecord])
}

/// "Admins" section: a header + a card listing admins, or one of the degraded
/// states (loading / unavailable / anonymous-operator warning).
final class InstanceAdminsView: UIView {
    private let header = InstanceSectionHeader()
    private let card = UIView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let outer = UIStackView(arrangedSubviews: [header, card])
        outer.axis = .vertical
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: InstanceAdminsState) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch state {
        case .loading:
            header.configure(title: "Admins", count: nil)
            card.backgroundColor = Theme.secondaryGroupedBackground
            stack.addArrangedSubview(messageRow("Loading…", color: .tertiaryLabel))
        case .unavailable:
            header.configure(title: "Admins", count: nil)
            card.backgroundColor = Theme.secondaryGroupedBackground
            stack.addArrangedSubview(messageRow("Admin list unavailable for this server.", color: .tertiaryLabel))
        case .anonymous:
            header.configure(title: "Admins", count: 0)
            card.backgroundColor = UIColor.systemRed.withAlphaComponent(0.10)
            card.layer.borderWidth = 1
            card.layer.borderColor = UIColor.systemRed.withAlphaComponent(0.24).cgColor
            let row = warningRow("No admins are publicly listed — operator is anonymous.")
            stack.addArrangedSubview(row)
        case let .admins(admins):
            header.configure(title: "Admins", count: admins.count)
            card.backgroundColor = Theme.secondaryGroupedBackground
            card.layer.borderWidth = 0
            for (index, admin) in admins.enumerated() {
                stack.addArrangedSubview(adminRow(admin))
                if index < admins.count - 1 {
                    stack.addArrangedSubview(hairline())
                }
            }
        }
    }

    private func messageRow(_ text: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13.5)
        label.textColor = color
        label.numberOfLines = 0
        return inset(label, insets: .init(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func warningRow(_ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        icon.tintColor = .systemRed
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .systemRed
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16)])
        return inset(row, insets: .init(top: 12, left: 14, bottom: 12, right: 14))
    }

    private func adminRow(_ admin: SiteAdminRecord) -> UIView {
        let avatar = InstancePersonAvatarView(seed: admin.personName)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        let name = UILabel()
        name.text = admin.label
        name.font = .systemFont(ofSize: 14.5, weight: .bold)
        name.textColor = .label
        let handle = UILabel()
        handle.text = "@\(admin.personName)"
        handle.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        handle.textColor = .tertiaryLabel
        let text = UIStackView(arrangedSubviews: [name, handle])
        text.axis = .vertical
        text.spacing = 1
        let role = PaddedChipLabel(text: admin.roleLabel)
        let row = UIStackView(arrangedSubviews: [avatar, text, role])
        row.axis = .horizontal
        row.spacing = 11
        row.alignment = .center
        NSLayoutConstraint.activate([avatar.widthAnchor.constraint(equalToConstant: 36), avatar.heightAnchor.constraint(equalToConstant: 36)])
        return inset(row, insets: .init(top: 9, left: 13, bottom: 9, right: 13))
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        let wrap = inset(line, insets: .init(top: 0, left: 13, bottom: 0, right: 0))
        return wrap
    }

    private func inset(_ view: UIView, insets: UIEdgeInsets) -> UIView {
        let stack = UIStackView(arrangedSubviews: [view])
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = insets
        return stack
    }
}
```

- [ ] **Step 2: Add the small shared subviews used above**

In the same file (or a sibling `InstanceMisc.swift`), add `InstanceSectionHeader`, `InstancePersonAvatarView`, and `PaddedChipLabel`:

```swift
/// Uppercase section label with an optional count, e.g. "ADMINS  3".
final class InstanceSectionHeader: UIView {
    private let titleLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .tertiaryLabel
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        countLabel.textColor = .tertiaryLabel
        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel, UIView()])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, count: Int?) {
        titleLabel.text = title.uppercased()
        countLabel.text = count.map { "\($0)" }
        countLabel.isHidden = count == nil
    }
}

/// A round placeholder avatar mark seeded by a string (deterministic hue).
final class InstancePersonAvatarView: UIView {
    init(seed: String) {
        super.init(frame: .zero)
        let hue = CGFloat(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        backgroundColor = UIColor(hue: hue, saturation: 0.45, brightness: 0.55, alpha: 1)
        clipsToBounds = true
        let letter = UILabel()
        letter.text = String(seed.prefix(1)).uppercased()
        letter.font = .systemFont(ofSize: 15, weight: .bold)
        letter.textColor = .white
        letter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(letter)
        NSLayoutConstraint.activate([
            letter.centerXAnchor.constraint(equalTo: centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

/// A small rounded role chip ("Owner" / "Admin").
final class PaddedChipLabel: UIView {
    init(text: String) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 7
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
```

- [ ] **Step 3: Regenerate, build**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/Components/InstanceAdminsView.swift
git commit -m "feat(instance-detail): admins section view with degraded states"
```

---

## Task 7: `InstanceAboutServerView` (collapsible Markdown sidebar)

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceAboutServerView.swift`
- Test: build-only (rendered in snapshots later).

**Interfaces:**
- Consumes: SpudMarkdownKit (`MarkdownBlockCache`, `MarkdownBodyView`, `MarkdownContext`), `InstanceSectionHeader`.
- Produces: `final class InstanceAboutServerView: UIView` with `func configure(sidebar: String, imageService: ImageServiceType?)` and `var onHeightChange: (() -> Void)?`.

- [ ] **Step 1: Implement the view**

Create `Spud/Scenes/Account/InstanceDetail/Components/InstanceAboutServerView.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudMarkdownKit
import SpudUIKit
import UIKit

/// "About this server": the instance sidebar rendered as Markdown, clamped to a
/// few lines with a bottom fade and a Read more / Show less toggle.
final class InstanceAboutServerView: UIView {
    /// Fired when expand/collapse changes the intrinsic height so a scrolling
    /// host can re-measure.
    var onHeightChange: (() -> Void)?

    private let header = InstanceSectionHeader()
    private let card = UIView()
    private let bodyView: MarkdownBodyView = {
        let context = MarkdownContext(kind: .post, textScale: 0, density: .comfortable)
        return MarkdownBodyView(context: context)
    }()

    private let fade = GradientView()
    private let toggleButton = UIButton(type: .system)
    private var expanded = false
    private var collapsedHeightConstraint: NSLayoutConstraint!

    private let collapsedHeight: CGFloat = 124

    override init(frame: CGRect) {
        super.init(frame: frame)
        header.configure(title: "About this server", count: nil)

        card.backgroundColor = Theme.secondaryGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true

        let clip = UIView()
        clip.clipsToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(bodyView)
        clip.addSubview(fade)
        fade.translatesAutoresizingMaskIntoConstraints = false
        fade.isUserInteractionEnabled = false

        toggleButton.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .bold)
        toggleButton.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)

        let separator = UIView()
        separator.backgroundColor = .separator

        let outer = UIStackView(arrangedSubviews: [header, card])
        outer.axis = .vertical
        outer.spacing = 8
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        card.addSubview(clip)
        card.addSubview(separator)
        card.addSubview(toggleButton)
        clip.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        toggleButton.translatesAutoresizingMaskIntoConstraints = false

        collapsedHeightConstraint = clip.heightAnchor.constraint(equalToConstant: collapsedHeight)
        collapsedHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),

            clip.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            clip.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 15),
            clip.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -15),

            bodyView.topAnchor.constraint(equalTo: clip.topAnchor),
            bodyView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),

            fade.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 46),

            separator.topAnchor.constraint(equalTo: clip.bottomAnchor, constant: 11),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            toggleButton.topAnchor.constraint(equalTo: separator.bottomAnchor),
            toggleButton.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            toggleButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            toggleButton.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            toggleButton.heightAnchor.constraint(equalToConstant: 42),
        ])
        applyState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(sidebar: String, imageService: ImageServiceType?) {
        if let imageService {
            bodyView.imageLoader = { [imageService] url in
                for await state in imageService.fetch(url) {
                    if case let .ready(image) = state { return image }
                }
                return nil
            }
        }
        bodyView.setBlocks(MarkdownBlockCache.shared.blocks(for: sidebar))
    }

    private func toggle() {
        expanded.toggle()
        let animate = !UIAccessibility.isReduceMotionEnabled
        let work = { self.applyState(); self.superview?.layoutIfNeeded() }
        if animate {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) { work() }
        } else {
            work()
        }
        onHeightChange?()
    }

    private func applyState() {
        collapsedHeightConstraint.isActive = !expanded
        fade.isHidden = expanded
        let accent = ThemeManager.currentAccentColor
        toggleButton.setTitleColor(accent, for: .normal)
        toggleButton.setTitle(expanded ? "Show less" : "Read more", for: .normal)
        toggleButton.setImage(UIImage(systemName: expanded ? "chevron.up" : "chevron.down"), for: .normal)
        toggleButton.tintColor = accent
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fade.topColor = Theme.secondaryGroupedBackground.withAlphaComponent(0)
        fade.bottomColor = Theme.secondaryGroupedBackground
    }
}

/// A simple vertical gradient used for the collapsed-sidebar fade.
final class GradientView: UIView {
    var topColor: UIColor = .clear { didSet { update() } }
    var bottomColor: UIColor = .clear { didSet { update() } }

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    private func update() {
        gradientLayer.colors = [topColor.cgColor, bottomColor.cgColor]
        gradientLayer.locations = [0, 0.86]
    }
}
```

- [ ] **Step 2: Regenerate, build**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/Components/InstanceAboutServerView.swift
git commit -m "feat(instance-detail): collapsible markdown about-server view"
```

---

## Task 8: `InstanceBannerHeaderView`

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/Components/InstanceBannerHeaderView.swift`
- Test: build-only (rendered in snapshots later).

**Interfaces:**
- Consumes: `ImageServiceType`.
- Produces: `final class InstanceBannerHeaderView: UIView` with `init(name:, host:)`, `func loadImages(iconUrl:, bannerUrl:, imageService:)`, and a fixed banner height matching the design (158).

- [ ] **Step 1: Implement the view**

Create `Spud/Scenes/Account/InstanceDetail/Components/InstanceBannerHeaderView.swift`. Reuse the banner/icon/identity layout already proven in `InstanceDetailViewController.makeHeader()` + `loadImages()` + `fetch(...)`, generalised into a standalone view (banner 158pt, 64pt icon overlapping by 30pt with a 3pt page-coloured border, name 20pt heavy, monospaced host). Use `Theme.groupedBackground` for the icon border.

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import UIKit

/// Banner image + overlapping rounded instance icon + name/host identity.
/// Shared by both instance-detail screens. The owning controller overlays its
/// own transparent nav buttons; this view draws only the banner and identity.
final class InstanceBannerHeaderView: UIView {
    let bannerHeight: CGFloat = 158

    private let bannerImageView = UIImageView()
    private let iconImageView = UIImageView()
    private let iconLetterLabel = UILabel()
    private var imageTasks: [Task<Void, Never>] = []
    private let host: String

    init(name: String, host: String) {
        self.host = host
        super.init(frame: .zero)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.backgroundColor = Self.placeholderColor(seed: host, saturation: 0.5, brightness: 0.5)
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerImageView)

        iconImageView.contentMode = .scaleAspectFill
        iconImageView.clipsToBounds = true
        iconImageView.layer.cornerRadius = 16
        iconImageView.layer.cornerCurve = .continuous
        iconImageView.layer.borderWidth = 3
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
        iconImageView.backgroundColor = Self.placeholderColor(seed: host, saturation: 0.45, brightness: 0.55)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconLetterLabel.text = String(name.prefix(1)).uppercased()
        iconLetterLabel.font = .systemFont(ofSize: 26, weight: .heavy)
        iconLetterLabel.textColor = .white
        iconLetterLabel.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.addSubview(iconLetterLabel)
        addSubview(iconImageView)

        let nameLabel = UILabel()
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 20, weight: .heavy)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 2

        let hostLabel = UILabel()
        hostLabel.text = host
        hostLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        hostLabel.textColor = .secondaryLabel

        let identity = UIStackView(arrangedSubviews: [nameLabel, hostLabel])
        identity.axis = .vertical
        identity.spacing = 3
        identity.translatesAutoresizingMaskIntoConstraints = false
        addSubview(identity)

        NSLayoutConstraint.activate([
            bannerImageView.topAnchor.constraint(equalTo: topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconImageView.topAnchor.constraint(equalTo: bannerImageView.bottomAnchor, constant: -30),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),
            iconLetterLabel.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            iconLetterLabel.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),

            identity.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 13),
            identity.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            identity.bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: -2),

            bottomAnchor.constraint(equalTo: iconImageView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { imageTasks.forEach { $0.cancel() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconImageView.layer.borderColor = Theme.groupedBackground.cgColor
    }

    func loadImages(iconUrl: String?, bannerUrl: String?, imageService: ImageServiceType) {
        if let url = iconUrl.flatMap(URL.init(string:)) {
            iconLetterLabel.isHidden = true
            fetch(url, into: iconImageView, imageService: imageService, fallbackLetter: true)
        }
        if let url = bannerUrl.flatMap(URL.init(string:)) {
            fetch(url, into: bannerImageView, imageService: imageService, fallbackLetter: false)
        }
    }

    private func fetch(_ url: URL, into imageView: UIImageView, imageService: ImageServiceType, fallbackLetter: Bool) {
        let stream = imageService.fetch(url)
        let task = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                switch state {
                case .loading: break
                case let .ready(image):
                    imageView.image = image
                    if fallbackLetter { iconLetterLabel.isHidden = true }
                case .failure:
                    if fallbackLetter { iconLetterLabel.isHidden = false }
                }
            }
        }
        imageTasks.append(task)
    }

    private static func placeholderColor(seed: String, saturation: CGFloat, brightness: CGFloat) -> UIColor {
        let hue = CGFloat(seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }
}
```

- [ ] **Step 2: Regenerate, build**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/Components/InstanceBannerHeaderView.swift
git commit -m "feat(instance-detail): shared banner+identity header view"
```

---

## Task 9: Onboarding screen — Admins + top-3 Communities + `showsActions`

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift`
- Test: snapshots updated in Task 12.

**Interfaces:**
- Consumes: `InstanceAdminsView`, `InstanceCommunityRowView`, `InstanceSectionHeader`, `SiteAdminObservations`, `ExplorerCommunityListObservations`, `ExplorerCommunityDirectory`, `AccountServiceType`.
- Produces: `InstanceDetailViewController.init(record:, showsActions: Bool = true, dependencies:)`.

- [ ] **Step 1: Add the `showsActions` flag**

Change the initializer to `init(record: ExplorerInstanceRecord, showsActions: Bool = true, dependencies: Dependencies)`, store `private let showsActions: Bool`. In `setup()`, only build/add the sticky action bar and the `scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor)` when `showsActions`; otherwise pin `scrollView.bottomAnchor` to `view.bottomAnchor`. (All four existing call sites keep passing only `record:` + `dependencies:`, relying on the default.)

- [ ] **Step 2: Append the Admins + Communities sections to the body**

In `makeBody()`, after the tags `WrapView` block, append:

```swift
        adminsView = InstanceAdminsView()
        adminsView.update(.loading)
        stack.setCustomSpacing(4, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(adminsView)

        communitiesContainer = UIStackView()
        communitiesContainer.axis = .vertical
        communitiesContainer.spacing = 8
        stack.addArrangedSubview(communitiesContainer)
```

Add stored properties `private var adminsView: InstanceAdminsView!` and `private var communitiesContainer: UIStackView!`, plus `private var observationTasks: [Task<Void, Never>] = []` (cancel in `deinit`).

- [ ] **Step 3: Load admins + top-3 communities in `viewDidLoad`**

After `loadImages()`, call a new `loadSecondaryData()`:

```swift
    private func loadSecondaryData() {
        guard let instance = InstanceActorId(from: record.url ?? "https://\(record.baseurl)") else { return }

        // Top-3 communities from the bundled directory (synchronous snapshot).
        let allRows = accountService is AccountService
            ? appDatabaseCommunityRows()
            : []
        renderCommunities(host: record.baseurl, allRows: allRows)

        // Admins: trigger a signed-out site fetch, then observe.
        let keychainId = accountService.accountForSignedOut(forInstance: instance, isServiceAccount: true)
        let service = accountService.lemmyService(forAccountKeychainId: keychainId)
        observationTasks.append(Task { [weak self] in
            try? await service.fetchSiteInfo()
            guard let self else { return }
            for await admins in appDatabase.observeSiteAdmins(forInstanceActorId: instance) {
                adminsView.update(Self.adminsState(admins))
            }
        })
    }

    static func adminsState(_ admins: [SiteAdminRecord]) -> InstanceAdminsState {
        admins.isEmpty ? .unavailable : .admins(admins)
    }
```

NOTE: this VC's `OwnDependencies` must gain `HasAppDatabase` so `appDatabase` and the directory query are reachable. Add `HasAppDatabase` to the `OwnDependencies` typealias and an `appDatabase` accessor (mirroring `imageService`/`accountService`). All call sites pass `dependencies.nested`, and the live container conforms to `HasAppDatabase`, so this compiles. Use `appDatabase.explorerCommunityListRowsSync()` for `appDatabaseCommunityRows()`.

`renderCommunities(host:allRows:)` builds the section: an `InstanceSectionHeader` ("Communities", count `record.numberOfCommunities` formatted), then up to 3 `InstanceCommunityRowView(row:, action: .chevron, joined: false, accent: accent)` rows inside a card, then a "Browse all N communities" footer row that pushes `InstanceCommunitiesView` (reuse Discover's pattern — see Task 11 for the exact push). When `ExplorerCommunityDirectory.communities(onInstance: host, in: allRows, sort: .members)` is empty, show a single "Community list unavailable." message row instead.

- [ ] **Step 4: Regenerate, build**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift
git commit -m "feat(instance-detail): add admins + top communities to onboarding screen"
```

---

## Task 10: `InstanceExploreViewModel` + `InstanceExploreViewController`

**Files:**
- Create: `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewModel.swift`
- Create: `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift`
- Test: snapshots in Task 12.

**Interfaces:**
- Consumes: all shared components, `SiteAdminObservations`, `observeAllSites`/`SiteRecord` read for sidebar, `ExplorerCommunityDirectory`, `AccountServiceType`, `AlertServiceType`, `ImageServiceType`.
- Produces: `InstanceExploreViewController.init(record:, accountKeychainId:, dependencies:)`.

- [ ] **Step 1: Implement the view model**

Create `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewModel.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit

/// State + actions for the in-app instance explore screen. Identity/stats/health
/// come from `record`; sidebar/admins are fetched live; communities come from the
/// bundled directory; Join federates through the browsing account.
@MainActor
@Observable
final class InstanceExploreViewModel {
    let record: ExplorerInstanceRecord
    let accountKeychainId: String

    private(set) var sidebar: String?
    private(set) var adminsState: InstanceAdminsState = .loading
    private(set) var communities: [CommunityListRow] = []
    private(set) var joinedCommunityUrls: Set<String> = []

    private let accountService: AccountServiceType
    private let appDatabase: AppDatabase
    private let alertService: AlertServiceType

    var instance: InstanceActorId? {
        InstanceActorId(from: record.url ?? "https://\(record.baseurl)")
    }

    var isSignedOut: Bool {
        accountService.isSignedOut(forAccountKeychainId: accountKeychainId)
    }

    init(
        record: ExplorerInstanceRecord,
        accountKeychainId: String,
        accountService: AccountServiceType,
        appDatabase: AppDatabase,
        alertService: AlertServiceType
    ) {
        self.record = record
        self.accountKeychainId = accountKeychainId
        self.accountService = accountService
        self.appDatabase = appDatabase
        self.alertService = alertService
    }

    func load() async {
        // Communities (synchronous directory snapshot).
        let allRows = appDatabase.explorerCommunityListRowsSync()
        communities = ExplorerCommunityDirectory.communities(onInstance: record.baseurl, in: allRows, sort: .members)

        guard let instance else { adminsState = .unavailable; return }

        // Trigger a signed-out site fetch (sidebar + admins), then observe both.
        let keychainId = accountService.accountForSignedOut(forInstance: instance, isServiceAccount: true)
        let service = accountService.lemmyService(forAccountKeychainId: keychainId)
        try? await service.fetchSiteInfo()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in await self?.observeAdmins(instance) }
            group.addTask { [weak self] in await self?.observeSidebar(instance) }
        }
    }

    private func observeAdmins(_ instance: InstanceActorId) async {
        for await admins in appDatabase.observeSiteAdmins(forInstanceActorId: instance) {
            adminsState = admins.isEmpty ? .unavailable : .admins(admins)
        }
    }

    private func observeSidebar(_ instance: InstanceActorId) async {
        for await sites in appDatabase.observeAllSites() {
            if let site = sites.first(where: { $0.instance == instance }) {
                // SiteListRow does not carry sidebar; read it directly.
                sidebar = appDatabase.siteSidebarSync(forInstanceActorId: instance)
            }
        }
    }

    /// Toggle Join for a community via the browsing account's home instance.
    /// Returns the resulting joined state (so the row can settle), or throws.
    func toggleJoin(_ row: CommunityListRow) async throws -> Bool {
        let service = accountService.lemmyService(forAccountKeychainId: accountKeychainId)
        let wantJoined = !joinedCommunityUrls.contains(row.communityUrl)
        let id = try await service.fetchCommunityInfo(communityName: "\(row.name)@\(row.instanceHost)")
        try await service.setSubscribed(serverCommunityId: id, subscribed: wantJoined)
        if wantJoined { joinedCommunityUrls.insert(row.communityUrl) }
        else { joinedCommunityUrls.remove(row.communityUrl) }
        return wantJoined
    }
}
```

NOTE: `observeSidebar` needs a one-shot sidebar read. Add a tiny helper to SpudDataKit alongside Task 3 (or in `SiteAdminObservations.swift`):

```swift
    func siteSidebarSync(forInstanceActorId actorId: InstanceActorId) -> String? {
        try? writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT site.sidebar FROM site
                JOIN instance ON instance.id = site.instanceId
                WHERE instance.actorId = ?
            """, arguments: [actorId.actorId])
        } ?? nil
    }
```

(Implement this helper as part of this task and commit it with the data layer or here; the test in Task 3 already covers the admin path, this is a trivial scalar read.)

- [ ] **Step 2: Implement the view controller**

Create `Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift`. Compose a `UIScrollView` with a vertical stack:

1. `InstanceBannerHeaderView(name: record.name, host: record.baseurl)` pinned to the scroll content top, full width (the banner bleeds; overlay back/share via `navigationItem` rather than glass buttons — simplest native fit, consistent with onboarding which also uses `navigationItem`). Set `navigationItem.title = record.baseurl`, `largeTitleDisplayMode = .never`, and a share `rightBarButtonItem` (reuse the onboarding share action: open `https://<host>`).
2. Description label (`record.descriptionText` or "No description provided by this server."), 16pt insets.
3. `InstanceAboutServerView` — hidden until `viewModel.sidebar` is non-nil; `configure(sidebar:imageService:)` then unhide; `onHeightChange` triggers `view.layoutIfNeeded()`.
4. 4-stat strip (Members / Active/mo / Communities / Posts) — reuse the onboarding `statTile`/grid styling, values via `InstanceHealthStyle.formatCount`.
5. Health cross-link card: `InstanceScoreRingView` (40pt, configured from `record.score`*100 + trust colour), trust label + "uptime · since —" line, trailing "Health ›". A tap pushes `InstanceDetailViewController(record: record, showsActions: false, dependencies: dependencies.nested)`.
6. `InstanceAdminsView` driven by `viewModel.adminsState`.
7. Communities section: `InstanceSectionHeader("Communities", count: record.numberOfCommunities)`, a card of `InstanceCommunityRowView(row:, action: .join, joined: viewModel.joinedCommunityUrls.contains(row.communityUrl), accent:)` for each `viewModel.communities` row, and a "Browse all N communities" footer pushing `InstanceCommunitiesView` (Task 11 push pattern). Each row's `onJoinTapped` calls `handleJoin(row, rowView:)`.

Bind to the view model via `ObservationStream.values(of:)` (per the repo's Observation pattern) in `viewDidLoad`, and call `Task { await viewModel.load() }`. Re-render the admins/sidebar/communities sections when the observed values change.

`handleJoin`:

```swift
    private func handleJoin(_ row: CommunityListRow, rowView: InstanceCommunityRowView) {
        guard !viewModel.isSignedOut else {
            Haptics.warning()
            alertService.handle(
                SignedOutGate(title: NSLocalizedString("Sign in to join", comment: "Sign-in gate when a signed-out user taps Join on a community")),
                for: .setSubscribed
            )
            return
        }
        Haptics.tap()
        let optimistic = !viewModel.joinedCommunityUrls.contains(row.communityUrl)
        rowView.setJoined(optimistic)
        Task {
            do {
                let settled = try await viewModel.toggleJoin(row)
                rowView.setJoined(settled)
            } catch {
                rowView.setJoined(!optimistic)
                alertService.handle(error, for: .setSubscribed)
            }
        }
    }
```

NOTE: match the signed-out gate to however the Community Subscribe button does it (`Spud/Scenes/Community/Content/CommunityViewController.swift:444-447`). Use the SAME `alertService` API/argument shape that call uses — replace the `SignedOutGate(...)`/`.setSubscribed` placeholders above with the project's actual signed-out-alert call (copy it from `setSubscribed()` in that file). Likewise `Haptics.tap()`/`Haptics.warning()` are the shared helpers from the design brief — confirm the exact spelling against `SpudUIKit`/`SpudUtilKit`.

The VC's `Dependencies` typealias must compose: `HasAccountService & HasImageService & HasAlertService & HasAppDatabase`, plus `InstanceDetailViewController.Dependencies` (for the Health push) and `CommunityOrLoadingViewController.Dependencies` + whatever `InstanceCommunitiesView`'s host needs (for "Browse all"). Mirror `InstanceDetailViewController`'s `(own:, nested:)` dependency split. All three call sites (Community/PostDetail/Discover) already pass `dependencies.nested`, which the live `DependencyContainer` satisfies.

- [ ] **Step 3: Regenerate, build**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Account/InstanceDetail/InstanceExploreViewModel.swift \
        Spud/Scenes/Account/InstanceDetail/InstanceExploreViewController.swift \
        SpudDataKit/Services/AppDatabase/SiteAdminObservations.swift
git commit -m "feat(instance-detail): in-app explore screen + view model"
```

---

## Task 11: Routing — Community handle tap + repoint PostDetail/Discover

**Files:**
- Modify: `Spud/Scenes/Community/Content/CommunityHeaderView.swift`
- Modify: `Spud/Scenes/Community/Content/CommunityViewController.swift`
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift`
- Modify: `Spud/Scenes/Discover/DiscoverViewController.swift`

**Interfaces:**
- Consumes: `InstanceExploreViewController.init(record:, accountKeychainId:, dependencies:)`.

- [ ] **Step 1: Make the community handle tappable**

In `CommunityHeaderView.swift`: add `var onInstanceTapped: (() -> Void)?`. In `setup()`, after configuring `handleLabel`, set `handleLabel.isUserInteractionEnabled = true`, add a `UITapGestureRecognizer` (`#selector(handleTapped)`), and set `handleLabel.accessibilityTraits = .button`. Add:

```swift
    @objc private func handleTapped() { onInstanceTapped?() }
```

- [ ] **Step 2: Wire the Community VC**

In `CommunityViewController.setup()` (where the other `headerView.*` callbacks are set), add:

```swift
        headerView.onInstanceTapped = { [weak self] in self?.openInstanceDetail() }
```

Add the push helper (resolve host from `viewModel.actorId`; require an Explorer record like Discover/PostDetail do):

```swift
    private func openInstanceDetail() {
        guard
            let actorId = viewModel.actorId,
            let url = URL(string: actorId),
            let host = url.host
        else { return }
        guard let record = appDatabase.explorerInstanceSync(baseurl: host) else {
            if let instanceURL = URL(string: "https://\(host)") { UIApplication.shared.open(instanceURL) }
            return
        }
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
    }
```

NOTE: confirm `CommunityViewModel` exposes `actorId: String?` (it is used to build the handle). If the property name differs, use the actual one. `appDatabase.explorerInstanceSync(baseurl:)` is the same lookup PostDetail/Discover use.

- [ ] **Step 3: Repoint PostDetail**

In `PostDetailViewController.swift`, `openInstance(_:)` (currently builds `InstanceDetailViewController`), replace the push with:

```swift
        let vc = InstanceExploreViewController(
            record: record,
            accountKeychainId: viewModel.accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(vc, animated: true)
```

(Keep the existing `guard let record = appDatabase.explorerInstanceSync(...) else { browser fallback }`.)

- [ ] **Step 4: Repoint Discover**

In `DiscoverViewController.swift`, `openInstanceDetail(host:)`, replace the `InstanceDetailViewController(record:, dependencies:)` push with:

```swift
        let detail = InstanceExploreViewController(
            record: record,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies.nested
        )
        navigationController?.pushViewController(detail, animated: true)
```

NOTE: `DiscoverViewController` has `accountKeychainId` (used by `openCommunity`). Leave `SiteListViewController` and `OnboardingHomeBaseViewController` untouched (they keep `InstanceDetailViewController`).

- [ ] **Step 5: Regenerate, build, smoke test**

Run: `make project` then `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds, 0 errors.

- [ ] **Step 6: Commit**

```bash
git add Spud/Scenes/Community/Content/CommunityHeaderView.swift \
        Spud/Scenes/Community/Content/CommunityViewController.swift \
        Spud/Scenes/PostDetail/Content/PostDetailViewController.swift \
        Spud/Scenes/Discover/DiscoverViewController.swift
git commit -m "feat(instance-detail): repoint in-app instance taps to explore screen"
```

---

## Task 12: Snapshot tests — onboarding re-record + new explore tests

**Files:**
- Modify: `SpudSnapshotTests/InstanceDetailSnapshotTests.swift` (fixtures gain admins/communities; re-record references)
- Create: `SpudSnapshotTests/InstanceExploreSnapshotTests.swift`

**Interfaces:**
- Consumes: `InstanceDetailViewController`, `InstanceExploreViewController`, in-memory services.

- [ ] **Step 1: Seed directory community rows into the in-memory DB for fixtures**

The onboarding/explore screens read admins from `observeSiteAdmins` and communities from `explorerCommunityListRowsSync()`. For deterministic snapshots, the test's in-memory `AppDatabase` must contain: (a) a `site` + `siteAdmin` rows for each fixture instance, and (b) `explorerCommunity` rows for that host. Add a helper in `InstanceDetailSnapshotTests` that, given an `ExplorerInstanceRecord` fixture, inserts a matching instance/site/admins and a few `ExplorerCommunityRecord` rows (use `try appDatabase.writer.write { ... }`). For the suspicious fixture, insert zero admins (drives the anonymous/unavailable state); for `missing`, insert none.

NOTE: because the screen also kicks off an async `fetchSiteInfo()` against a real network, the snapshot must render the already-seeded DB state without waiting on the network. Build the VC, seed the DB first, then drive one synchronous render. If the VC's admin load only updates via the async observation, give the test a way to render the seeded state deterministically — prefer constructing the VC against a DB already containing the admin/community rows so the first synchronous layout shows them, and stub the account service's signed-out `lemmyService` so `fetchSiteInfo()` is a no-op (the existing `StaticImageService` pattern shows how lightweight fakes are wired). Confirm the account service used in tests does not perform real network I/O; if it does, inject a fake `AccountServiceType` whose `lemmyService(...)` returns a no-op `LemmyServiceType`.

- [ ] **Step 2: Update onboarding fixtures + re-record**

Extend the `Fixtures` in `InstanceDetailSnapshotTests.swift` and the seeding helper so each state renders its admins + top-3 communities. Delete the stale reference PNGs for `InstanceDetailSnapshotTests`, then run once to record:

Run: `rm -f SpudSnapshotTests/__Snapshots__/InstanceDetailSnapshotTests/*.png`
Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudSnapshotTests/InstanceDetailSnapshotTests test`
Expected: FAIL (references recorded).
Run the same command again.
Expected: PASS. Eyeball the new PNGs to confirm admins + communities render as designed.

- [ ] **Step 3: Write the explore snapshot tests**

Create `SpudSnapshotTests/InstanceExploreSnapshotTests.swift` mirroring `InstanceDetailSnapshotTests`' structure (pinned `.image(on: .iPhone13Pro, traits:)`, light + dark, `StaticImageService`, in-memory `AccountService`/`AlertService`). Cover: `world` (admins + communities + sidebar collapsed), a sidebar-expanded variant, `suspicious` (anonymous admins), `missing` (unavailable admins + communities), and a joined-row variant (seed `joinedCommunityUrls` via a pre-subscribed community row). Construct `InstanceExploreViewController(record:, accountKeychainId:, dependencies:)` inside a `UINavigationController`.

- [ ] **Step 4: Record + verify the explore references**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudSnapshotTests/InstanceExploreSnapshotTests test`
Expected: FAIL (records). Rerun → PASS. Eyeball the PNGs.

- [ ] **Step 5: Commit**

```bash
make project
git add SpudSnapshotTests/InstanceExploreSnapshotTests.swift \
        SpudSnapshotTests/InstanceDetailSnapshotTests.swift \
        SpudSnapshotTests/__Snapshots__/InstanceDetailSnapshotTests \
        SpudSnapshotTests/__Snapshots__/InstanceExploreSnapshotTests
git commit -m "test(instance-detail): snapshot admins/communities + explore screen"
```

---

## Task 13: Full regression + finish

**Files:** none (verification).

- [ ] **Step 1: Build app + widget**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudWidgetExtension`
Expected: both succeed (Spud ≤ 1 pre-existing benign rpath warning; widget 0 warnings).

- [ ] **Step 2: Run the unit test plan**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: green (new `SiteAdmin*` and `InstanceCommunityDisplay` tests included).

- [ ] **Step 3: Run the snapshot plan**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: green.

- [ ] **Step 4: SwiftFormat lint**

Run: `mint run swiftformat --lint Spud SpudDataKit`
Expected: no required changes (format any flagged files with `mint run swiftformat <paths>` before final commit).

- [ ] **Step 5: Manual smoke (optional but recommended)**

Boot a sim, run the app, open a community, tap the `!name@instance` handle → explore screen appears with sidebar/admins/communities; tap Join on a row (signed in) → flips to Joined; tap Health → onboarding detail with no action bar. Confirm PostDetail and Discover instance taps now open the explore screen.

- [ ] **Step 6: Open the PR**

```bash
git push -u origin feat/instance-explore-detail
gh pr create --title "feat: instance explore screen + onboarding admins/communities" --body "<summary + link to docs/superpowers/specs/2026-06-17-instance-detail-explore-design.md>"
```

---

## Self-Review

**Spec coverage:**
- Admins persistence (record + migration + importer + observation) → Tasks 1-3. ✓
- Sidebar from SiteRecord via signed-out fetch → Task 10 (`load()` + `siteSidebarSync`). ✓
- Communities from `ExplorerCommunityDirectory` (subs + active/wk; no posts/wk) → Tasks 5, 9, 10. ✓
- Federated Join (`fetchCommunityInfo(communityName:)` → `setSubscribed`) + sign-in gate → Task 10. ✓
- Shared component kit → Tasks 4-8. ✓
- Onboarding additions + `showsActions` → Task 9. ✓
- Explore screen (banner, description, sidebar, stat strip, health cross-link, admins, communities) → Task 10. ✓
- Routing (community handle, PostDetail, Discover; onboarding/SiteList/login untouched) → Task 11. ✓
- Modlog omitted; concepts B/C omitted → not built (correct). ✓
- States/a11y → folded into component tasks (loading/unavailable/anonymous; `.button` trait; Dynamic Type via system fonts; Reduce Motion in the sidebar toggle). ✓
- Testing (admins unit, community display unit, onboarding re-record, explore snapshots) → Tasks 1-3, 5, 12. ✓

**Placeholder scan:** The three `fatalError`/`SignedOutGate`/`Haptics` spots in Tasks 2, 10, 11 are explicitly flagged NOTES instructing the implementer to substitute the project's real fixture/alert/haptic calls (those exact APIs live in the test target / `AlertService` / `SpudUIKit` and are referenced by file:line). They are integration points against existing code, not invented logic. No other placeholders.

**Type consistency:** `SiteAdminRecord` fields, `InstanceHealthStyle` method names, `InstanceAdminsState` cases, `InstanceCommunityRowView.Action`, and `InstanceExploreViewController.init(record:accountKeychainId:dependencies:)` are used consistently across tasks. `observeSiteAdmins(forInstanceActorId:)` / `siteAdminsSync(forInstanceActorId:)` / `siteSidebarSync(forInstanceActorId:)` names match between definition (Tasks 3/10) and use (Tasks 9/10).
