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

### Back-off and give-up on persistent failures

When a site-info fetch fails repeatedly — for example, because a CDN or WAF is returning a persistent HTTP 403 for that instance — the scheduler applies **per-site exponential back-off** and, after enough permanent failures, **permanently gives up**. The back-off schedule is approximately:

| Consecutive permanent failures | Retry delay |
|---|---|
| 1 | ~5 min |
| 2 | ~10 min |
| 3 | ~20 min |
| 4 | ~40 min |
| 5 | give-up — background polling stops |

After N = 5 consecutive permanent (4xx) failures the scheduler marks the site as given up and excludes it from both site-info sweeps permanently. A transient failure (5xx / timeout) does not count toward the permanent-failure total; it applies a short ~5-minute back-off but the site is never abandoned for transient reasons.

The back-off deadline (`siteInfoNextAttemptAt`) and the permanent-failure count are stored in the database per site, so they survive cold app relaunches. A persistently-failing instance is no longer re-probed within seconds of each launch.

### Behavior and rules (scheduler)

- **Transient failures self-heal.** A successful fetch clears the back-off and the permanent-failure count. A brief outage that recovers before the next tick leaves no lasting effect.
- **Reconnect triggers an immediate retry for the signed-in daily-refresh path.** When network connectivity returns, the signed-in daily-refresh clears its in-memory back-off and retries on the next tick. The two site-info sweeps (signed-out-awaiting and ownerless) honor their persisted `siteInfoNextAttemptAt` deadline and do not immediately retry on reconnect — they wait until the stored deadline passes.
- **The failure stays visible in About → Logs.** A `site.fetchFailed` event is recorded on each actual attempt. With back-off, entries appear at most a handful of times early on. Once the give-up threshold is reached, a single `site.giveUp` notice is recorded and entries stop — see [diagnostics-logging.md](diagnostics-logging.md).
- **Back-off and give-up state are persisted per site.** The back-off deadline and permanent-failure count are stored in the database, so a cold app relaunch does not reset them. A persistently-failing instance is not re-probed within seconds of launch.
- **Give-up is self-healing.** The on-demand site-info fetch (user navigating to the instance) still fires regardless of give-up state. A successful fetch from any path (scheduler or on-demand) resets the give-up state and resumes background refresh.
- **No visible UI.** There is no in-app indicator that a specific instance is backed off or given up. The About → Logs viewer is the diagnostic surface.

### Scenarios (scheduler)

#### Persistently-failing instance is backed off and eventually abandoned

- **Given** one of my accounts' Lemmy instances is returning persistent HTTP 403 errors (e.g. from a WAF)
- **When** the scheduler ticks
- **Then** the first failed attempt records a `site.fetchFailed` error event in About → Logs, and the back-off deadline is written to the database
- **And** subsequent retries are spaced roughly 5 minutes, 10 minutes, 20 minutes, and 40 minutes apart
- **And** after the fifth consecutive permanent failure a `site.giveUp` notice event is recorded and the scheduler stops polling that instance — log entries stop appearing

#### Connectivity returning clears back-off (signed-in path)

- **Given** the signed-in daily-refresh has backed off due to repeated site-fetch failures
- **When** network connectivity returns (the device comes back online)
- **Then** the in-memory back-off for the signed-in path is cleared
- **And** the scheduler retries that account on the next tick without waiting out the remaining window
- **Note:** the two site-info sweeps (signed-out-awaiting and ownerless) honor their persisted back-off deadlines and do not immediately retry on reconnect

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

- No UI indicator surfaces the back-off state or give-up state for a specific instance. About → Logs is the only diagnostic surface.
- The scheduler does not distinguish between a transient network error and a permanent authentication/authorization failure (e.g. expired session vs. CDN block) for the signed-in daily-refresh path. A "session needs re-login" hint is a separate, deferred feature.
- The ownerless-sites sweep (instances not yet associated with any account) is subject to the same persisted back-off and give-up rules as the signed-out-awaiting sweep.
- The persisted back-off and give-up apply to the **site-info sweeps only** (signed-out-awaiting and ownerless). The signed-in daily-refresh path uses in-memory back-off that clears on cold launch; a unified persisted back-off path for all scheduler work is deferred.
