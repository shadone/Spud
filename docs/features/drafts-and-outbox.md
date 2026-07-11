# Drafts and Outbox

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Draft persistence](draft-persistence.md), [Replying](replying.md), [New post](new-post.md), [Voting](voting.md), [Saving](saving.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

A single recovery screen lists every pending or failed outbound content item — unsent drafts, in-flight sends, and permanently-failed items — for the signed-in account. It is the one place to retry failed sends, review what is queued, and discard items that should not be sent. Reachable from Preferences and from the "Couldn't post / Couldn't send comment — View" failure toast.

This screen covers the **content** outbox only (new/edited comments, posts, and direct messages — anything with text a user might want to review, retry, or discard). A separate, idempotent **mutation** outbox durably applies and retries simple state toggles — vote, save, hide, comment/post delete-restore, and community subscribe/unsubscribe — with its own instant optimistic write and its own rollback-plus-toast on permanent failure (e.g. "Couldn't update subscription"). It has no draft/sending/failed list here because there is nothing to draft: a toggle is either applied (optimistically, right away) or, on permanent failure, rolled back with a toast — never left as a recoverable item a user re-triggers from this screen. See [Voting](voting.md), [Saving](saving.md), and [Subscribe / unsubscribe](subscribe-unsubscribe.md) for that outbox's own behavior.

## Behavior and rules

- **Covers comments, posts, and direct messages.** Every durable outbound content item — a reply, a new post, an edit, or a private message — flows through this one queue and recovery screen.
- **Three item states.** Each item is shown with its current status:
  - **Draft** — composed and saved but not yet submitted (the user dismissed with "Save Draft").
  - **Sending** — queued in the background send queue; may be waiting for a retry interval or for network.
  - **Failed** — the background queue gave up after exhausting retries or hit a permanent error (auth failure, deleted parent, rate limit).
- **Item content is always preserved.** A Failed item retains its full content (title, body, URL, community, recipient, etc.) — it is never silently discarded by the system.
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

### Retry a failed direct message

- **Given** a private message whose send permanently failed
- **When** I open Drafts and Outbox and swipe Retry on its "Message to <name>" row
- **Then** it re-enters the background send queue and its status changes to Sending

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

- **Editing an already-posted comment is not done from this screen.** Items in this screen are exclusively unsent (Draft, Sending, or Failed). Editing a *posted* comment is offered inline in its thread (long-press → Edit), which enqueues its own outbound item that may briefly appear here while sending or if it fails — see [Replying](replying.md). Editing a *posted* post works the same way — offered inline on the post (overflow → Edit) and routed through its own outbound item — see [New post](new-post.md).
- **Push notifications for failures.** Failed sends surface a non-blocking in-app toast only; no push notification is sent.
