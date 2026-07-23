# ADR-0001: GRDB over SwiftData for the App Group store

**Date**: 2026-05 (decided) / 2026-07-22 (written up)
**Status**: accepted
**Deciders**: Denis

> Backfilled. The decision was made and shipped during the Stage 7 Core Data
> demolition in May 2026; this record was written afterwards from the code and
> the working notes so the argument does not have to be had again.

## Context

Spud was moving off Core Data. The obvious successor was SwiftData — it is
Apple's, it is the direction of travel, and staying in the Apple stack is
normally the right default here.

The blocker is the shape of Spud's store. The database lives in the App Group
container (`group.info.ddenis.Spud.shared/AppDatabase/AppDatabase.sqlite`) and is
opened by **two separate processes**: the app, and `SpudWidgetExtension` (which
constructs its own `AppDatabase` in `SpudWidget/DependencyContainer.swift`).
Within the app there are two `DatabasePool`s at launch — the DI graph and the
`AppDatabase.shared` singleton. The widget is not a reader of a convenience
cache; it is a first-class client of the same file, and it opens it while the
app may be mid-write or mid-migration.

(The other two extensions, `OpenInAppExtension` and `OpenInSpudAction`, hold no
App Group entitlement and never touch the store. Two writing processes is
already enough to decide this — the count is not the argument, the absence of
any supported multi-writer story is.)

On top of that the read side is SQL-shaped: FTS (`postInteractionFts`), joins
across `postInteraction -> post -> community`, backfill migrations, and raw-SQL
epoch date columns. The UI is UIKit + `AsyncStream`, not SwiftUI.

## Decision

Spud uses **GRDB/SQLite** as its persistence layer, in
`SpudDataKit/Services/AppDatabase/`. SwiftData is not used anywhere in the app.

## Alternatives Considered

### Alternative 1: SwiftData

- **Pros**: first-party; no third-party dependency; `@Model` macro removes
  boilerplate; automatic lightweight schema migration; a plausible path to
  CloudKit sync later.
- **Cons**: no supported story for multiple processes writing one store — the
  cross-process change story is Core Data's `NSPersistentStoreRemoteChange`
  plumbing, which coordinates *notification*, not *concurrent open and migrate*;
  `ModelContext` is not `Sendable` and `@Model` types are reference types, which
  fights Swift 6 strict concurrency (on across all shipped targets); `@Query` is
  SwiftUI-only, so an already-UIKit app gets none of the ergonomic payoff; no
  FTS; predicate expressiveness well short of the joins Spud runs; migrations are
  opaque, so a backfill cannot be unit-tested step by step.
- **Why not**: the multi-process App Group requirement is not negotiable and
  SwiftData has no answer for it. Every other objection is survivable; that one
  is not.

### Alternative 2: Stay on Core Data

- **Pros**: already there; zero migration cost; `NSPersistentCloudKitContainer`
  for free.
- **Why not**: this was the thing being escaped. Core Data is de-emphasized by
  Apple, caused ongoing friction with newer platform surfaces (notably Widgets),
  and its own multi-process story still relies on careful external coordination.
  Migrating from Core Data to SwiftData would have been re-platforming onto the
  same store engine while inheriting a *weaker* API over it.

### Alternative 3: Raw SQLite (no wrapper)

- **Pros**: total control; no dependency.
- **Why not**: hand-rolling record mapping, migrations, and change observation
  is exactly what GRDB already does well. Buying that is worth the dependency.

## Consequences

### Positive

- Cross-process access is expressible: WAL, an explicit busy timeout, and an
  `flock` held across the whole open-and-migrate in `init(onDiskAt:)`.
- Migrations are named, ordered, and testable — `DatabaseMigrator` registrations
  in `AppDatabase+Migrations.swift`, with the `AppDatabase.migrator` seam letting
  a backfill be driven to an intermediate `vNN` and asserted.
- Records are plain structs in `Records/`, so they are `Sendable` and strict
  concurrency is a non-event.
- `ValueObservation` maps onto the `AsyncSequence`/`@Observable` reactive
  direction the rest of the app took (see the Core Data / Combine exit).
- The full SQL surface is available: FTS, joins, raw SQL where it pays.

### Negative

- A third-party dependency on the critical path, with the bus factor that
  implies.
- Migrations, observation plumbing, and record mapping are hand-written and
  reviewed; nothing is generated.
- No free CloudKit sync. If Spud ever wants cross-device sync it is a build,
  not a checkbox.

### Risks

- **Cross-process locking is now our problem.** This is not theoretical: build
  24 crashed at launch for every TestFlight user when concurrent connections
  raced on `PRAGMA journal_mode=WAL` and on the same pending migration set
  (`SQLITE_BUSY` / "table already exists"). Debug and simulator hid it.
  Mitigated in build 25 by the flock plus busy timeout described above.
  *Never open a second pool at launch, and never migrate from an unserialized
  connection.* See `spud-appdatabase-migration-crash` and Spud/CLAUDE.md,
  "Persistence".

## When to revisit

Only one of these should reopen it:

1. Apple ships a documented, supported multi-process/multi-writer story for
   SwiftData in an App Group — not just remote-change notifications.
2. Spud drops the widget extension, so exactly one process opens the store.
3. GRDB becomes unmaintained or stops supporting a Swift version Spud needs.

"SwiftData is the modern choice" is not a reason. It was the modern choice in
May 2026 too, and it still could not open this database from four processes.
