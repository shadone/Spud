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

---

## Periodic account and site refresh

In addition to the foreground unread-count refresh above, Spud runs a periodic **scheduler** (`SchedulerService`) that keeps account and site information current. On a five-minute tick it checks each account for pending or stale site data (display name, site configuration) and fetches it from the server when needed. This path has no visible UI; its health is observable through About → Logs.

### Back-off on persistent failures

When a site-info fetch fails repeatedly — for example, because a CDN or WAF is returning a persistent HTTP 403 for that instance — the scheduler applies **per-account exponential back-off** rather than retrying every tick. The back-off schedule is approximately:

| Consecutive failures | Retry delay |
|---|---|
| 1 | ~5 min |
| 2 | ~10 min |
| 3 | ~20 min |
| 4 | ~40 min |
| 5 | ~80 min |
| 6+ | ~2 h (cap) |

Once the cap is reached the account is retried roughly every two hours until the instance recovers or the app is relaunched.

### Behavior and rules (scheduler)

- **Transient failures self-heal.** A successful fetch clears the back-off. A brief outage that recovers before the next tick leaves no lasting effect.
- **Reconnect triggers an immediate retry.** When network connectivity returns, all per-account back-off counters are cleared so previously-failing accounts are retried at the next scheduler tick without waiting out their back-off window.
- **The failure stays visible in About → Logs.** A `site.fetchFailed` event is recorded on each actual attempt. With back-off, entries appear at most a handful of times early on and then at most every ~2 hours — not once every 5 minutes. The instance host is always named so it is easy to identify which server is failing.
- **In-memory only; resets on cold launch.** Back-off state is not persisted to the database. A cold app relaunch resets all counters, so a recovered instance is attempted promptly on the first tick after launch.
- **No visible UI.** There is no in-app indicator that a specific account is backed off. The About → Logs viewer is the diagnostic surface.

### Scenarios (scheduler)

#### Persistently-failing instance is backed off progressively

- **Given** one of my accounts' Lemmy instances is returning persistent errors (e.g. HTTP 403 from a WAF)
- **When** the scheduler ticks
- **Then** the first failed attempt records a `site.fetchFailed` event in About → Logs
- **And** the next retry is scheduled roughly 5 minutes later, then doubling each time, up to a cap of about 2 hours
- **And** the instance is no longer attempted on every 5-minute tick — log spam stops after the first few entries

#### Connectivity returning clears back-off

- **Given** an account has backed off due to repeated site-fetch failures
- **When** network connectivity returns (the device comes back online)
- **Then** the per-account back-off is cleared
- **And** the scheduler retries that account on the next tick without waiting out the remaining back-off window

#### A transient failure self-heals

- **Given** a site-info fetch failed once or a few times during a brief outage
- **When** the instance recovers and the next scheduled attempt succeeds
- **Then** the back-off counter is cleared
- **And** subsequent ticks attempt the account on the normal schedule

#### Failed attempts remain visible in About → Logs

- **Given** an account's site-info fetches are backed off
- **When** I open Settings → About → Logs → Event Log and filter by category "site"
- **Then** I see `site.fetchFailed` error entries naming the instance host
- **And** the entries are spaced progressively farther apart as back-off grows, reflecting actual retry attempts

## Not supported / out of scope (scheduler)

- No UI indicator surfaces the back-off state for a specific account.
- The scheduler does not distinguish between a transient network error and a permanent authentication/authorization failure (e.g. expired session vs. CDN block). A "session needs re-login" hint is a separate, deferred feature.
- The ownerless-sites sweep (instances not yet associated with any account) does not apply per-account back-off and is out of scope for this iteration.
