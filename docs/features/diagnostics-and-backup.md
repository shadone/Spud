# Diagnostics and backup

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [acknowledgements.md](acknowledgements.md), [diagnostics-logging.md](diagnostics-logging.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → About bundles two diagnostics alongside a backup export: a Logs viewer (see [diagnostics-logging.md](diagnostics-logging.md) for full capability details), a Storage size readout for the local database, and an Export Backup action that shares the database file through the system share sheet.

## Behavior and rules

- **Logs viewer.** A Logs row opens the diagnostic log screen — a two-tab viewer (Event Log and System Log). See [diagnostics-logging.md](diagnostics-logging.md) for the full specification: durable GRDB-backed event log that survives relaunch, filter by category + level, search, per-entry detail, export, and a live OSLog tail for the current session.
- **Storage size.** The Storage section shows the local database's size on disk, formatted as a human-readable byte count (for example "128 MB"). The size is read from the app database at the time the screen is built.
- **Export Backup.** A ShareLink shares the local database file itself. Tapping it opens the system share sheet with the database file as the item, so it can be saved to Files, AirDropped, or sent to another app. The backup is the raw SQLite database file — there is no separate archive or transformation step.

## Scenarios

### Open the logs viewer

- **Given** Settings → About
- **When** I tap Logs
- **Then** the diagnostic log screen opens, showing the Event Log tab with durable events newest-first
- **And** I can switch to the System Log tab for the current-session OSLog tail
- **And** the full filter, search, detail, and export capabilities are available (see [diagnostics-logging.md](diagnostics-logging.md))

### See the database size

- **Given** Settings → About
- **When** I look at the Storage section
- **Then** it shows the local database's size as a human-readable byte count

### Export a backup via the share sheet

- **Given** the Storage section
- **When** I tap Export Backup
- **Then** the system share sheet opens with the local database file
- **And** I can save or send it from there

## Not supported / out of scope

- Export Backup produces the raw SQLite database file shared through the share sheet — it is not an encrypted, versioned, or selective backup, and there is no in-app restore/import flow that consumes it.
- The storage size is the database only; it is not a full breakdown of caches or image storage.
- Logs and backup are diagnostics, not a sync or cloud-backup feature.
