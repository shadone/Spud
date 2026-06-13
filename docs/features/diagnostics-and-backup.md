# Diagnostics and backup

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [acknowledgements.md](acknowledgements.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Settings → About bundles three diagnostics: a Logs viewer that shows the app's recent log entries, a Storage size readout for the local database, and an Export Backup action that shares the database file out through the system share sheet.

## Behavior and rules

- **Logs viewer.** A Logs row opens a screen that reads the system unified log (`OSLogStore`) for the current process, keeps only entries from the last hour belonging to Spud's own subsystem, and shows them as plain text — each line a timestamp, the log category, and the message. It is read-only.
- **Storage size.** The Storage section shows the local database's size on disk, formatted as a human-readable byte count (for example "128 MB"). The size is read from the app database at the time the screen is built.
- **Export Backup.** A ShareLink shares the local database file itself. Tapping it opens the system share sheet with the database file as the item, so it can be saved to Files, AirDropped, or sent to another app. The backup is the raw SQLite database file — there is no separate archive or transformation step.

## Scenarios

### View recent logs

- **Given** Settings → About
- **When** I open Logs
- **Then** I see the app's log entries from the last hour as text, each with a timestamp, category, and message

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

- The Logs viewer is read-only and limited to roughly the last hour of Spud's own subsystem entries; there is no log level filter, search, or clear action.
- Export Backup produces the raw SQLite database file shared through the share sheet — it is not an encrypted, versioned, or selective backup, and there is no in-app restore/import flow that consumes it.
- The storage size is the database only; it is not a full breakdown of caches or image storage.
- Logs and backup are diagnostics, not a sync or cloud-backup feature.
