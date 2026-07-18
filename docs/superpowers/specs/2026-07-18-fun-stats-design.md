# Fun stats (personal usage odometer) — design

Date: 2026-07-18
Status: Approved (brainstorming) — ready for implementation planning
Branch: `feat/fun-stats`

## Problem

Spud already remembers a lot about what the user *does* (posts opened, posts
seen, votes), but none of it is presented playfully, and the fun, physical
metrics — how far you have scrolled, how many times you have tapped, how long
you have been in the app — are not collected at all. The existing homes for
this data are unsuitable for lifetime totals: `postInteraction` is
retention-pruned, and `diagnosticEvent` is pruned to 14 days by design.

We want a lighthearted, device-wide "usage odometer": total scroll distance
(with real-world equivalences), posts read, taps, sessions, time in app,
streaks, and most-active-hour — collected locally, shown on a standalone
playful screen tucked behind an About/Settings row.

## Decisions (from brainstorming)

- **Experience: standalone Stats screen**, reached from an easter-egg-ish row
  in the About/Preferences area. Not part of the Account → Activity dashboard.
- **Metric families: all four** — motion & touch, reading, time & streaks,
  engagement.
- **Scope: device-wide.** One odometer for the person holding the phone,
  regardless of active account; works signed-out. No account column.
- **Storage: bucketed counters** (not an event log, not UserDefaults). One row
  per `(day, hour, key)`, incremented by upsert. Lifetime totals are `SUM`,
  streaks come from distinct consecutive days, most-active-hour from
  `GROUP BY hour`. Never pruned; growth is a few dozen rows per day at most.
- **Collection is preference-gated (default on) with a reset.** All data is
  local-only and never leaves the device; the screen says so.
- **All increments flow through `StatsService`** (single buffered,
  preference-gated write path) invoked from existing seams/call sites — we do
  not piggyback increments inside other write helpers such as
  `PostInteractionWrites`, so gating and buffering live in exactly one place.
- **No backfill.** Counters start at zero on first run with the feature. The
  existing `postInteraction` / `voteEvent` tables are per-account and (for the
  former) pruned, so seeding from them would be wrong-scope and lossy.

## Non-goals (explicit scope guard)

- **No sharing.** A Share-as-Image "stats card" is an obvious follow-up but is
  out of scope for v1.
- **No per-account breakdown**, no server data, and no sync.
- **No recaps or notifications** (weekly/yearly Wrapped-style delivery is a
  possible later feature over the same table).
- **No backfill / seeding** from existing tables (see decisions).
- **No collection in extensions or the widget.** Only the app process records;
  the metrics are app-interaction metrics by definition.

## Architecture

Four cooperating pieces, smallest-first:

### 1. `FunStatKey` + `FunStatRecord` + migration (SpudDataKit)

A new GRDB table, added as the next `vNN` migration in
`AppDatabase+Migrations.swift` (v39 at the time of writing — confirm with the
usual `grep registerMigration … | tail -1` before implementing):

```sql
CREATE TABLE funStat (
  day   TEXT    NOT NULL,  -- local calendar day, "2026-07-18"
  hour  INTEGER NOT NULL,  -- local hour of day, 0-23
  key   TEXT    NOT NULL,  -- FunStatKey raw value
  value DOUBLE  NOT NULL,
  PRIMARY KEY (day, hour, key)
)
```

`FunStatRecord` lives in `SpudDataKit/Services/AppDatabase/Records/` like every
other record type. `FunStatKey` is a `String`-raw-value enum with 13 cases:

| Family | Keys |
|---|---|
| Motion & touch | `scrollDistancePoints`, `tapCount`, `pullToRefreshCount` |
| Reading | `postsOpened`, `postsSeen`, `imagesViewed`, `linksOpened` |
| Time | `sessionCount`, `foregroundSeconds` |
| Engagement | `votesCast`, `commentsPosted`, `postsPosted`, `searchesRun` |

Streak, most-active-hour, and "counting since" are *derived* at read time, not
stored. Day/hour are computed in the user's current local calendar at record
time; a traveler's timezone shifts can slightly blur bucket boundaries, which
is acceptable for a fun feature (documented, not compensated).

### 2. `StatsService` (actor — SpudDataKit, `Services/Stats/`)

The single write path. API:

- `record(_ key: FunStatKey, amount: Double = 1)` — adds to an in-memory
  accumulator keyed by `(day, hour, key)`. No DB write per call.
- `setEnabled(_ isEnabled: Bool)` — when false, `record` no-ops and pending
  buffered values are discarded. The app target observes
  `PreferencesService.funStatsCollectionEnabledStream` and forwards changes
  here (SpudDataKit cannot read the app-target `PreferencesService` directly;
  same pattern as other preference-passed SpudDataKit behavior). Default: on.
- `flush()` — upserts the accumulator into `funStat`
  (`value = value + excluded.value`) and clears it. Runs on a ~10 s cadence
  while there is buffered data, and is called explicitly on scene
  resign-active/background. Writes are best-effort (mirroring `DiagnosticLog`
  tolerance): a failed stats write logs to OSLog and never surfaces to the
  user or affects app behavior.
- `resetAllStats()` — `DELETE FROM funStat` plus accumulator clear; backs the
  UI reset action.

Session semantics (implemented inside the service, driven by lifecycle calls
from the app):

- `appDidEnterForeground()` — increments `sessionCount` if more than
  **5 minutes** have elapsed since the last background (or it is the first
  foreground since launch); remembers the activation timestamp.
- `appWillResignActive()` — adds the elapsed foreground interval to
  `foregroundSeconds` (attributed to the current hour bucket at flush time —
  a session spanning an hour boundary attributes to the flush hour, an
  accepted approximation) and flushes.

### 3. Collection hooks (app target — all existing seams)

- **Scroll distance** — a small pure `ScrollOdometer` helper (modeled on the
  unit-tested `ScrollToTopUndo`: UIKit-free, takes contentOffset updates,
  emits absolute-delta distance, ignores rubber-band overshoot beyond content
  bounds). Fed from the existing `scrollViewDidScroll` implementations in
  `PostListViewController`, `PostDetailViewController`,
  `InboxViewController`, `DMThreadViewController`, and
  `ActivityViewController`. Deltas are locally batched (report to
  `StatsService` on scroll-end/at thresholds, not per scroll tick). The Fun
  Stats screen's own scrolling does not feed the odometer.
- **Taps** — a `sendEvent(_:)` override in the existing `MainWindow` counts
  one per ended touch. Genuinely device-wide (every screen), a few lines.
- **Pull-to-refresh** — the post list refresh-control action.
- **Posts opened / seen** — the same two call sites that already call
  `recordPostOpened` (`PostDetailViewModel`) and `recordPostSeen`
  (`PostListViewModel`).
- **Images viewed** — media viewer presentation.
- **Links opened** — the central external-link/Safari opening path.
- **Engagement** — votes/comments/posts increment at the respective
  outbox-enqueue points (so offline actions count exactly once and retries
  never double-count); searches at search execution.
- **Sessions / time** — scene lifecycle callbacks (the same places that fire
  `.lifecycle` diagnostic events) call the two `StatsService` lifecycle
  methods.

### 4. Read side + screen (SpudDataKit queries, app-target UI)

- `FunStatsQueries.swift` / `FunStatsObservations.swift` — one
  `observeFunStatsSummary()` ValueObservation producing a `FunStatsSummary`
  struct: lifetime totals per key, first recorded day, current + longest
  streak (consecutive distinct days with any row), and most-active-hour
  (`GROUP BY hour` over all keys). Live observation so visible counters tick
  as flushes land.
- **`FunStatsView`** — SwiftUI, hosted in a `UIHostingController`
  (matching the Preferences pattern), pushed from a new **"Fun Stats" row in
  the About screen** (the easter-egg placement decided in brainstorming).
  Layout:
  - *Hero odometer:* scroll distance converted to meters/km using
    1 pt = 1/163 inch (a documented fun-not-science constant), with a
    real-world equivalence line driven by a small pure `FunEquivalence`
    helper over a landmark table (Eiffel Tower 330 m, Burj Khalifa 828 m,
    Mount Everest 8,849 m, ISS altitude 408 km, ...): picks the largest
    landmark passed and phrases "that is N x <landmark>".
  - *Tile grid* reusing the Activity Summary stat-tile visual language:
    posts read, posts seen, taps, votes cast, sessions, time in app, longest
    streak, most-active hour (labeled with an SF Symbol night-owl/early-bird
    flavor — no emoji).
  - *Footer:* "Counting since <first recorded day>" and a one-line "All data
    stays on this device." Counts formatted with the shared `CountFormatter`.
  - *Reset:* a toolbar/overflow action behind a confirmation dialog, calling
    `StatsService.resetAllStats()`.
  - Dynamic Type, VoiceOver labels on every tile (label + value combined),
    light/dark — the standard quality bar.
- **Preference** — `funStatsCollectionEnabled` (`@UserDefaultsBacked`,
  default `true`, with the matching `Stream` accessor) surfaced as a toggle
  in the Privacy area of Preferences with a "stays on this device"
  explanation.

## Error handling

- Stats writes are best-effort: failures log and drop; nothing user-visible.
- `record` before DB readiness or with collection disabled is a silent no-op.
- The screen with zero data shows a friendly first-day empty state (tiles at
  zero, "Counting starts today"), never an error.

## Testing

- **Unit (SpudDataKitTests):** migration adds the table; upsert accumulation
  across `(day, hour, key)`; `FunStatsSummary` derivations — lifetime sums,
  current/longest streak (incl. gaps and single-day), most-active-hour;
  reset; enable/disable gating; the 5-minute session rule (injected clock).
- **Unit (SpudTests / SpudUtilKitTests as placed):** `ScrollOdometer` delta
  math incl. rubber-band clamping; `FunEquivalence` landmark selection and
  phrasing; point-to-meter conversion.
- **Snapshot (SpudSnapshotTests):** `FunStatsView` in empty/first-day and
  rich-data states, `deterministicPhone` config.
- **No new UI tests.** The screen is reachable by one row tap; existing
  conventions (launch-arg auto-present) are available if a tap-gated verify is
  ever needed.

## Documentation

- New `docs/features/fun-stats.md` (behavior + Given/When/Then scenarios),
  plus the `docs/features/README.md` capability table *and* by-area map rows.
- API docs on `StatsService`, `FunStatKey`, `FunStatsSummary`, and the
  helpers; internal comments only where non-obvious (session rule, timezone
  stance, best-effort writes).
