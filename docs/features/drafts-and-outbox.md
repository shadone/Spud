# Drafts and Outbox

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Draft persistence](draft-persistence.md), [Replying](replying.md), [New post](new-post.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

A single recovery screen lists every pending or failed outbound content item — unsent drafts, in-flight sends, and permanently-failed items — for the signed-in account. It is the one place to retry failed sends, review what is queued, and discard items that should not be sent. Reachable from Preferences and from the "Couldn't post / Couldn't send comment — View" failure toast.

## Behavior and rules

- **Three item states.** Each item is shown with its current status:
  - **Draft** — composed and saved but not yet submitted (the user dismissed with "Save Draft").
  - **Sending** — queued in the background send queue; may be waiting for a retry interval or for network.
  - **Failed** — the background queue gave up after exhausting retries or hit a permanent error (auth failure, deleted parent, rate limit).
- **Item content is always preserved.** A Failed item retains its full content (title, body, URL, community, etc.) — it is never silently discarded by the system.
- **Row actions.** Each row supports swipe actions and a context menu:
  - **Retry** (Failed items only) — requeues the item in the background send queue.
  - **Discard** (any item) — removes the item from the outbox and from the durable store. For a Failed comment this also removes the optimistic placeholder from the relevant post-detail thread.
  - There is no in-list **Edit** action in v1. Editing unsent text happens by reopening the relevant composer: a saved Draft reopens its composer with the text silently restored (per target); a **failed comment** can also be edited inline from the post-detail thread (tap the failed comment → Retry / Edit / Discard, where Edit reopens the composer seeded with the failed body text); a **failed post** offers only Retry / Discard on its pending post-detail banner — there is no Edit path for a failed post.
- **Failure toast entry point.** When a send permanently fails, a non-blocking "Couldn't post — View" or "Couldn't send comment — View" toast appears in the app. Tapping "View" navigates here.
- **Preferences entry point.** A row in Preferences opens this screen at any time, not only after a failure.
- **Per-account.** The list shows items for the currently active account only. Switching accounts shows that account's queue.
- **Background queue auto-retry.** Sending items retry automatically with exponential backoff and resume when the network returns or the app relaunches. No user action is needed for transient failures; this screen is for permanent failures and manual management.

## Scenarios

### Retry a failed comment

- **Given** a comment that permanently failed
- **When** I open Drafts and Outbox (via the toast or Preferences) and swipe Retry
- **Then** the item re-enters the background send queue and its status changes to Sending

### Discard a failed post

- **Given** a post that permanently failed
- **When** I swipe Discard
- **Then** the item is removed from the outbox and the pending post-detail screen is dismissed

### Resume a saved draft

- **Given** a draft saved via "Save Draft" when dismissing the composer
- **When** I open Drafts and Outbox
- **Then** the saved draft appears; tapping it reopens the composer seeded with its content

### View what is in flight

- **Given** items currently being sent (possibly waiting for a backoff interval)
- **When** I open Drafts and Outbox
- **Then** each is listed with a Sending status; no action is required

## Not supported / out of scope

- **Private messages.** The DM composer uses the old blocking flow and does not appear in this screen.
- **Editing an already-posted comment or post.** Items in this screen are exclusively unsent (Draft, Sending, or Failed); successfully sent content is managed via the thread or feed directly.
- **Push notifications for failures.** Failed sends surface a non-blocking in-app toast only; no push notification is sent.
