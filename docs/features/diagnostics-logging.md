# Diagnostics logging

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — pending release (on `feat/logging-observability`)
- **Related:** [diagnostics-and-backup.md](diagnostics-and-backup.md), [drafts-and-outbox.md](drafts-and-outbox.md), [docs/superpowers/specs/2026-06-29-observability-logging-design.md](../superpowers/specs/2026-06-29-observability-logging-design.md)

## What it does

Spud maintains a durable, in-app diagnostic event log stored in GRDB alongside the main database. Background tasks, both outboxes (vote/save/hide mutations and content creation), site-info fetches, the scheduler, unread refresh, offline downloads, Spotlight indexing, and app lifecycle events all write curated records to this log. The log persists across app relaunches — allowing a user to open About → Logs after a restart and see exactly what the outbox did to an offline vote, which instance is failing its site-info fetch, or how many items an offline download saved.

The Logs screen (Settings → About → Logs) is a two-tab viewer: the **Event Log** tab shows the durable GRDB-backed log with full filter, search, per-entry detail, and export; the **System Log** tab shows an OSLog tail for the current app session, now with level and category filters, a configurable time window, and a share action.

## Behavior and rules

- The durable log is stored in the `diagnosticEvent` GRDB table (migration `v26_diagnosticEvent`), in the shared App Group container alongside the main database.
- Every recorded event fans to both sinks: a durable GRDB row **and** an OSLog entry using the appropriate logger category, so Console.app still receives everything.
- Retention is bounded: at service init (app launch) and after large write bursts, the table is pruned to the most recent 10,000 rows and rows older than 14 days are dropped — whichever bound is tighter.
- Events carry a `category` (outbox / composerOutbox / scheduler / site / offlineDownload / unread / spotlight / lifecycle), a `level` (debug / info / notice / error), a short machine-readable `event` name (e.g. `op.permanentRollback`, `site.fetchFailed`), a human-readable `message`, an optional `instance` host (e.g. `lemmy.world`), and optional structured `metadata` (JSON object with fields such as httpStatus, entityType, entityServerId, attempts, error).
- The instance host stored in the log is public and non-secret (it is the Lemmy instance hostname, not a token or password). Auth tokens, passwords, and the raw `accountKeychainId` are never recorded.
- Export is a deliberate, user-initiated share-sheet action. Nothing leaves the device automatically.
- Individual events can be copied without exporting the whole log: long-pressing a row copies its one-line summary, and the detail view's **Copy Event** button copies the full event (summary plus metadata). Both write to the clipboard only — nothing leaves the device. The row copy, the detail copy, and each exported line share one text formatter, so their formats stay identical.
- The Event Log list is live-updating: GRDB observation delivers changes while the screen is open.
- A vote, save, or hide that is permanently rolled back (e.g. because the server returned a 403) produces an `op.permanentRollback` event at error level, carrying the instance host and HTTP status in metadata. This event is durable and survives relaunch.
- A content submission (comment / post / DM) that is permanently parked (never able to send) produces an `op.permanentPark` event at error level.
- A site-info fetch failure (including a `getSite` HTTP 403 from a CDN or WAF) produces a `site.fetchFailed` event (`.error`) carrying the **instance host** — making it possible to see which specific instance is failing, not just that some fetch failed. The event is now **bounded**: after N = 5 consecutive permanent (4xx) failures the scheduler gives up on that site (see [account-provenance-and-site-refresh.md](account-provenance-and-site-refresh.md)), so `site.fetchFailed` entries for a permanently-blocked instance stop appearing after the give-up rather than recurring forever. For instances still being retried, exponential back-off means entries appear a handful of times early on and then at most every ~2 hours.
- When the scheduler reaches the abandonment threshold for a site it records a **`site.giveUp`** event (category `.site`, level `.notice`, metadata `failureCount`) — a single entry naming the instance host and the number of permanent failures that triggered the give-up. This event makes it possible to see in About → Logs exactly why an instance stopped being polled ("gave up after 5 permanent failures"), rather than just noticing that `site.fetchFailed` entries stopped appearing.
- An offline download (category `offlineDownload`, see [offline-download.md](offline-download.md)) records a curated run lifecycle rather than per-item chatter: `download.start` and a `download.finish` summary, plus `download.retry`, `download.itemFailed`, `download.pageFetchIncomplete`, and `download.cancelled`. The `download.finish` metadata carries `downloadedCount`, `failedCount`, `durationMs`, and the run-wide aggregates `imageWarmFailures` and `archiveCaptureFailures` — the total individual image warms and linked-page snapshots that failed. Those per-item failures are **OSLog-only** (one durable row per image would flood the table); only the run-level sums are persisted. A `download.retry` carries `phase` (`page` for a feed-page fetch, `content` for a post's comment fetch), `attempt`, `delayMs`, `error`, and `pushback` (`true` when the retry was for a server rate-limit signal — HTTP 429/503 or a `rate_limit*` error — so rate-limiting is distinguishable from a plain transient blip); a content-phase retry also carries the `serverPostId`.
- Lifecycle events (`launch`, `foreground`, `accountApplied`) are recorded so drain and refresh activity can be correlated to when the app was opened or brought to the foreground.
- The System Log tab is read-only and limited to the current app session (OSLog cannot retrieve prior-session entries in-app). The Event Log tab persists across sessions.

## Scenarios

### View the durable event log

- **Given** I open Settings → About → Logs
- **When** the screen opens
- **Then** the Event Log tab is shown by default, with a live list of diagnostic events newest-first
- **And** each row shows the time, a level indicator (with a text label, not color alone), the category, and the message

### View the system log for the current session

- **Given** the Logs screen is open
- **When** I tap the System Log tab
- **Then** I see OSLog entries for the current app process, each showing the level, category, timestamp, and message
- **And** I can change the time window (Last hour / Last 24 hours / Since launch) to narrow or broaden what is shown

### Filter the event log by category and level

- **Given** the Event Log tab is open
- **When** I select one or more category chips (e.g. "outbox") or raise the minimum level (e.g. "Errors only")
- **Then** the list immediately narrows to events matching those criteria
- **And** I can also type into the search field to further narrow by message, event name, instance host, or metadata content

### Diagnose a vote that did not stick — durable rollback record

- **Given** I voted on a post while offline (a "we'll send your vote when you're back online" toast appeared)
- **When** the app later reconnected and the server returned a permanent error (e.g. HTTP 403)
- **Then** the outbox rolled back the vote to the baseline state and showed a "Couldn't vote" toast
- **And** an `op.permanentRollback` error event was recorded to the durable log, carrying the instance host and HTTP status in its metadata
- **When** I later open Settings → About → Logs → Event Log (even after a relaunch)
- **Then** the `op.permanentRollback` row is present and names the instance and HTTP status — explaining exactly what happened to the vote

### See which instance is failing

- **Given** site-info fetches are failing repeatedly for one of my accounts
- **When** I open the Event Log and filter by category "site" or search for "fetchFailed"
- **Then** I see `site.fetchFailed` error events naming the specific **instance host** (e.g. `lemmy.world`) and the HTTP status
- **And** I can identify which server is failing and at what rate, without needing to inspect source code or Console.app
- **And** because the scheduler backs off on repeated failures, entries appear a handful of times initially and then at most every ~2 hours — not once every 5 minutes — so the log stays readable
- **And** if the instance never recovers, after 5 consecutive permanent failures a single `site.giveUp` notice entry appears and `site.fetchFailed` entries stop — the log explains that the scheduler gave up rather than continuing to spam failures

### See why an instance stopped being polled

- **Given** a `site.giveUp` notice event appears in About → Logs for an instance
- **When** I tap the row to open its detail
- **Then** I see the instance host, the `failureCount` metadata field (showing how many consecutive permanent failures triggered the give-up), and the exact timestamp
- **And** I know the scheduler is no longer polling that instance in the background

### Inspect a log entry in detail

- **Given** the Event Log tab is open
- **When** I tap any row
- **Then** a detail view shows the full message, exact timestamp, category, level, instance host, and all structured metadata fields (formatted for readability)
- **And** a **Copy Event** toolbar button copies the whole event as text — the one-line summary plus a sorted metadata block — to the clipboard (with a light haptic)

### Copy a single event from the list

- **Given** the Event Log tab is open
- **When** I long-press a row and choose **Copy**
- **Then** that event's one-line summary (`<timestamp> [<LEVEL>] <category> <event> — <message> [instance]`) is copied to the clipboard — the same format the export uses for each line — without opening the detail view

### Export the log for a bug report

- **Given** the Event Log tab is open (optionally filtered to the relevant category or time range)
- **When** I tap the Share/Export toolbar button
- **Then** the system share sheet opens with the current (filtered) log rendered as text
- **And** I can save it to Files, send it via Messages, or attach it to a bug report
- **And** the exported text contains only what is in the table: instance hosts, event names, messages, and metadata — no auth tokens or passwords

### Clear the event log

- **Given** the Event Log tab is open
- **When** I tap Clear and confirm
- **Then** all rows are removed from the durable `diagnosticEvent` table
- **And** the list is immediately empty

### Event Log survives relaunch; System Log does not

- **Given** the Event Log contains entries from a previous app session (e.g. an `op.permanentRollback` from an hour ago)
- **When** I force-quit and relaunch the app, then open Settings → About → Logs
- **Then** the Event Log tab shows those prior-session entries (they are stored in GRDB)
- **And** the System Log tab shows only entries from the current process session (OSLog scope is per-process)

## Not supported / out of scope

- The durable log captures curated lifecycle events only. Per-item debug chatter (e.g. every individual HTTP request) goes only to OSLog; the durable table is a high-value subset.
- Log export is always a manual, user-initiated share-sheet action. Nothing is uploaded automatically.
- Widget or extension background runs are not yet instrumented in the durable log (the table is in the App Group container so they could contribute later; that is a future iteration).
- There is no remote log upload or automatic crash reporting — export is the only mechanism for sharing logs.
- The table prune keeps at most 10,000 rows and 14 days of history; older events are dropped.
- The System Log tab can only show entries from the current app session; prior-session OSLog entries are not accessible in-app.
