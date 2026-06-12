# Background unread refresh

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Inbox](inbox.md), [Mark inbox items read](inbox-mark-read.md), [Private messages](private-messages.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

When the app returns to the foreground, Spud refreshes the inbox unread count so the Inbox
tab badge is current the moment you come back. The refresh fetches only the unread *count*
(replies, mentions, private messages) from the server — it does not pull the inbox items
themselves. The badge updates live off the refreshed count. This is the only periodic-style
refresh tied to the unread badge.

## Behavior and rules

- **Triggered on foreground.** The refresh runs when the scene transitions from background to foreground (`sceneWillEnterForeground`), via `MainWindow.refreshUnreadCount()`. It is a scene-lifecycle refresh, not an OS-scheduled background task.
- **Count only.** The refresh calls the server's unread-count endpoint and stores the result in `UnreadCountService`. It fetches counts only — no replies, mentions, or message bodies are loaded by this path.
- **Live badge.** `UnreadCountService.unreadCount` is observable state; the Inbox tab badge observes it, so a foreground refresh that changes the count re-badges the tab immediately.
- **Per active account.** The refresh targets the currently active (default) account. With no active account yet resolved, it is a no-op.
- **Signed-out resets to zero.** For a signed-out account the count refresh skips the network and reports zero, clearing the badge.
- **Failures keep the last count.** A failed refresh is logged and leaves the previously-known count in place, so a transient network error does not blank the badge.
- **Other refresh paths share the same count.** Opening or pull-refreshing the Inbox, marking items read, and sending also update the same `UnreadCountService` count; this feature specifically covers the foreground-driven refresh.

## Scenarios

### Returning to the app refreshes the badge

- **Given** Spud was in the background and new inbox activity arrived
- **When** I bring the app back to the foreground
- **Then** the unread count is re-fetched from the server
- **And** the Inbox tab badge updates to the current total

### Only the count is fetched

- **Given** the app returns to the foreground
- **When** the unread refresh runs
- **Then** only the unread count is fetched, not the inbox items
- **And** the inbox lists are not reloaded by this refresh

### A signed-out account clears the badge

- **Given** the active account is signed out
- **When** the foreground refresh runs
- **Then** no network request is made and the count is reported as zero
- **And** the tab badge is cleared

### A failed refresh keeps the old count

- **Given** the unread-count request fails on foreground
- **When** the error returns
- **Then** the previous count and badge are left unchanged

## Not supported / out of scope

- **This is not a `BGAppRefreshTask`.** Spud does not register a `BGTaskScheduler` app-refresh (or any background task), declares no background execution modes, and does nothing while the app is in the background. The "background" here means *on returning to the foreground*, not OS-scheduled background execution. (This corrects the legacy feature grid, which described it as an "App Refresh task, no server".)
- The refresh **does** contact the server — it calls the unread-count endpoint. It is not an offline/local-only operation.
- There are no local notifications or push for new inbox activity; the only surfacing is the in-app tab badge.
- The unread count is not polled on a timer while the app is open; it updates on foreground, on inbox load / pull-to-refresh, and on read/send actions.
