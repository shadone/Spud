# Post & Comment Reminders — Design Spec

**Date:** 2026-07-12
**Status:** Approved (brainstorm) — pending implementation plan

**Goal:** Let a user set a reminder to come back to a post or a comment subtree — either at a chosen time (read-later) or when new comments arrive (follow the discussion) — delivered as a local notification and surfaced in a Reminders segment of the Inbox.

---

## 1. Concept

One unified feature, **"Reminders."** A reminder targets **a whole post** or **a comment subtree** and has one of two **triggers**:

- **Time trigger** (`.at(date)`) — one-shot. Fires once at a chosen time, then is done. Delivered by a reliable OS-scheduled local notification (works even if the app never runs).
- **Activity trigger** (`.newComments`) — recurring. Notifies as the discussion grows (a fixed smart rule), re-arming after each notification, until the user removes it. Best-effort: evaluated by a poll that runs in the foreground and via an opportunistic iOS background-refresh task (no backend, so timing is not guaranteed).

A single target may carry **both** triggers independently (one `.at` and one `.newComments`). "Follow"/"subscribe"/"watch" is just the informal name for the activity trigger; the UI always says "Remind me when there are new comments."

Reminders are a **distinct concept from Save** — setting a reminder does not save the post, and vice versa.

### Terminology (consistent across all surfaces)

- Action verb: **"Remind Me…"**
- The list / Inbox segment: **"Reminders"**
- Activity trigger phrasing: **"When there are new comments"** (never "Follow"/"Watch" in UI copy)

---

## 2. User-facing behavior

### 2.1 Entry points

A **"Remind Me…"** submenu (modeled on the existing `MuteDuration` submenu) appears in:
- the post-detail ••• overflow menu (targets the whole post),
- the feed cell long-press context menu (whole post),
- the comment long-press context menu (targets that comment's subtree).

The submenu is one flat list, every item one tap:

> **In 3 hours · This evening · Tomorrow · In 2 days · In a week · Pick a time…**  ·  **When there are new comments**

- Time presets resolve to concrete dates (see §2.4). "Pick a time…" presents a date/time picker.
- "When there are new comments" creates/removes the activity trigger.
- Items already active show a checkmark; tapping an active item **removes** that trigger (toggle). So the same menu sets and cancels.
- On selection, a lightweight confirmation toast: e.g. "Reminder set for tomorrow" / "You'll be notified of new comments." Removing: "Reminder cleared."

### 2.2 Notification behavior

- **First reminder ever** triggers a just-in-time system permission prompt (§6). If granted, reminders deliver OS notifications. If denied/undecided, reminders are still created and fully functional **in-app** (Inbox Reminders segment + badge) — they just don't push; a one-time inline note explains this with a link to Settings.
- **Time reminder fires** → local notification: title = post title, body = the community handle + "Tap to revisit." Tapping opens the post.
- **Activity reminder fires** → local notification: title = post (or thread) title, body = "N new comments" + community. Tapping opens the post (scrolled to the first new comment; for a subtree, to the subtree root).
- Tapping any reminder notification routes through the existing `AppCoordinator.open(_:in:)` via a `info.ddenis.spud://internal/...` deep link stored in the notification's `userInfo` (`.objectAtURL(ap_id)`, with `scrollToCommentId` for a comment target).

### 2.3 Inbox "Reminders" segment + badge

- The Inbox tab gains a distinct **"Reminders"** segment/filter, separate from Lemmy replies/mentions/DMs so it never muddies them.
- It lists the account's reminders (a durable GRDB observation of the reminder table — unlike the transient server-fetched Lemmy inbox), each showing its target (title/community/thumbnail) and status: "in 2 days", "watching · 3 new", "fired · 5 new comments".
- **Fired-but-unseen** reminders contribute to the Inbox tab badge (blended with the server unread count). Opening the Reminders segment marks fired items **seen**, decrementing the badge.
- Tapping a row opens the post/comment. Swipe to remove a reminder. A pending time reminder can be rescheduled from its row (reopens the picker) — optional, low priority.

### 2.4 Time presets

Computed relative to now in the user's current calendar/timezone:
- **In 3 hours** = now + 3h.
- **This evening** = today 18:00 (if already past ~17:00, treat as now + 3h to avoid an immediate/past fire).
- **Tomorrow** = tomorrow 09:00.
- **In 2 days** = now + 2 days, 09:00.
- **In a week** = now + 7 days, 09:00.
- **Pick a time…** = user-chosen (reject past times).

---

## 3. Activity trigger rule (fixed smart default — no user knobs)

For a followed target, let `new = commentsNow - baselineCount` and `elapsed = now - baselineAt`. The reminder **fires** when:

```
new >= 5
OR (new >= 1 AND elapsed >= 24h)
```

(≥5 new is the "meaningful batch"; the 24h fallback nudges on slow threads with at least some activity. Zero new never fires.) On fire: post the notification, set `unseen = true`, and **re-arm** the baseline (`baselineCount = commentsNow`, `baselineAt = now`) so the next batch can fire again. The `5` and `24h` constants are internal and centralized (one place) for easy future tuning.

- **Whole-post count:** `commentsNow` = `PostRecord.numberOfComments` from a `getPost` (cheap; a single integer delta). Baseline seeded from the current count at creation.
- **Subtree count:** `new` = count of new comments *within the subtree* since `baselineAt`, derived from a `getComments` fetch by reusing `NewCommentState.compute` + `CommentCollapseState`'s pre-order/depth ownership rule (already implemented for the collapsed-new-badge). Heavier (a tree fetch), so subtree follows are polled on the same throttle as whole-post follows.

---

## 4. Data model

New GRDB migration **`v35_reminder`** (latest is `v34_postCrossPost`). One table, `reminder`, per-account.

| column | type | notes |
|---|---|---|
| `id` | INTEGER PK | |
| `accountId` | INTEGER NOT NULL | the owning account (as elsewhere) |
| `postServerId` | INTEGER NOT NULL | plain int (survives `post`-cache eviction, like `postInteraction`) |
| `rootCommentServerId` | INTEGER NOT NULL | **`0` = whole post** (sentinel); else the subtree root's server comment id. Sentinel not NULL — see the unique-key gotcha below. |
| `kind` | TEXT NOT NULL | `"time"` \| `"activity"` |
| `fireAt` | (date) NULL | time reminders — when to fire |
| `nextCheckAt` | (date) NULL | activity reminders — next poll due-time |
| `baselineCount` | INTEGER NULL | activity — comment count at (re)arm |
| `baselineAt` | (date) NULL | activity — time of (re)arm |
| `lastNotifiedAt` | (date) NULL | last fire, for de-dup/backoff |
| `status` | TEXT NOT NULL | `"scheduled"` \| `"fired"` \| `"dismissed"` \| `"failed"` |
| `unseen` | BOOLEAN NOT NULL | fired and not yet seen in the Reminders segment → drives badge |
| `notificationRequestId` | TEXT NULL | UNNotificationRequest id for a scheduled time reminder (to cancel it) |
| `titleSnapshot` / `communityName` / `instanceHost` / `thumbnailUrl` | denormalized | render + open without the `post` row |
| `createdAt` | (date) NOT NULL | |

- **Unique key:** `(accountId, postServerId, rootCommentServerId, kind)` — at most one time and one activity reminder per target. **Gotcha:** SQLite treats NULLs as *distinct* in a UNIQUE index, so a nullable `rootCommentServerId` would NOT enforce one-per-whole-post; hence whole-post is the non-null sentinel `rootCommentServerId = 0` (comment ids are positive), and reads map `0 → whole post`.
- **Date column convention:** follow the `*Record` Codable ISO-8601-text convention unless mirroring the outbox's epoch-`.double` columns — match whichever the copied helper uses (see the GRDB date gotcha in CLAUDE.md); pick one and be consistent. `nextCheckAt`/`fireAt` are compared in SQL `WHERE … <= now`, so binding must match storage.
- Records/importer/observations/writes follow the existing conventions (`Records/ReminderRecord.swift`, `ReminderWrites.swift`, `ReminderObservations.swift`/`ReminderQueries.swift`).

---

## 5. Services / architecture

### 5.1 `ReminderService` (per-account actor)

Mirrors the outbox actor pattern (durable per-account, `nextAttemptAt`-style due-query + `OutboxBackoff`). Responsibilities:
- **Create / toggle / remove** a reminder (upsert by unique key). For a time reminder: schedule a `UNCalendarNotificationTrigger` (or `UNTimeIntervalNotificationTrigger`) up front and store its `notificationRequestId`; removing cancels the pending request. For an activity reminder: seed `baselineCount`/`baselineAt` from the current count and set `nextCheckAt`.
- **Poll due activity reminders** (`pollDueReminders(asOf:)`): select `kind = activity AND nextCheckAt <= now`; for each, `getPost` (or `getComments` for a subtree), compute `new`, apply the §3 rule; on fire → post a local notification + set `unseen` + re-arm; always set the next `nextCheckAt = now + pollInterval`. Best-effort per item: a failed fetch (deleted/unreachable post) is logged, backs off, and after repeated failures marks the reminder `failed` (surfaced in the list) — never crashes the sweep.
- **Poll throttle:** `pollInterval` ≈ 30 min per follow (a followed target is not re-polled every 5-min tick). Centralized constant.

### 5.2 Notification layer (net-new — none exists today)

- `ReminderNotificationScheduler` / setup in `AppDelegate`: `UNUserNotificationCenter.current().delegate = …`; a just-in-time `requestAuthorization` on first reminder; a `PreferencesService` toggle ("Reminder notifications").
- `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` reads the routing URL from `response.notification.request.content.userInfo` and calls `AppCoordinator.shared.open(_:in:)`. `userNotificationCenter(_:willPresent:)` decides foreground presentation (banner while in-app is acceptable).
- Notification content is built from the denormalized reminder fields + the nested `URL.SpudInternalLink`.

### 5.3 Scheduling engines

- **Time reminders:** OS-scheduled — no polling. Reliable regardless of app state. Because the OS notification can fire while the app is closed, the record stays `scheduled` until reflected in-app: on launch/foreground `ReminderService` **reconciles** overdue time reminders (`kind = time AND fireAt <= now AND status = scheduled`) → mark `fired` + `unseen` (drives the badge). Tapping the notification (`didReceive`) also marks that reminder `fired`/seen. This also covers the notifications-denied case: the reminder still becomes `fired`/`unseen` in the Inbox segment the next time the app runs after `fireAt`.
- **Activity reminders (foreground):** a new sweep `pollDueReminders()` added to `SchedulerService.tick()` (the existing foreground 5-min `Timer`), reusing its per-account gating + reachability + diagnostics.
- **Activity reminders (background):** a net-new **`BGAppRefreshTask`** registered in `AppDelegate` (identifier e.g. `info.ddenis.Spud.reminderPoll`), added to `Info.plist` `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: [fetch]` (via `project.yml`; no paid entitlement). Its handler runs `pollDueReminders()` within the OS budget and reschedules itself. iOS budgets these opportunistically — this is the "best-effort" path the user accepted.
- **Diagnostics:** a new `.reminder` `DiagnosticLog` category records scheduled / fired / failed / poll-skipped, surfaced in About → Logs.

### 5.4 Reuse map (build on, don't reinvent)

- `postInteraction.lastKnownCommentCount` (written today, read nowhere) — a ready seam for baselines / cross-checks.
- `NewCommentState.compute` + `CommentCollapseState` — subtree new-comment delta.
- `PostRecord.numberOfComments` via `getPost` — canonical whole-post count.
- `OutboxService` due-query + `OutboxBackoff` — the durable `nextAttemptAt` pattern to mirror.
- `AppCoordinator.open` / `URL.SpudInternalLink` — notification-tap routing.
- `MuteDuration` — the duration-picker submenu template.
- Inbox scope/list/cell patterns + `UnreadCountService` badge mechanism — the Reminders segment + badge.
- `AccountView` list-screen pattern — an optional Account shortcut into the Reminders segment (nice-to-have).

---

## 6. Notifications, permissions, background — details & constraints

- **Permission:** requested just-in-time on the first reminder. Denied → in-app-only degradation (segment + badge; no push). A `PreferencesService` toggle lets the user disable reminder notifications without losing the in-app reminders.
- **Background budget:** `BGAppRefreshTask` cadence is OS-controlled; can be delayed hours or skipped if the app is rarely used. The foreground sweep covers the common "user opens the app" case. Poll cost is bounded by the ~30-min per-follow throttle and by only polling due follows.
- **Deleted/unreachable target:** fetch failure backs off; after N failures the reminder is marked `failed` and shown as such (removable), not silently dropped.
- **Logout / account switch:** an account's reminders are inert while it's not active; its scheduled OS notifications remain but tap-routing resolves within that account (edge — acceptable; may cancel on logout as a refinement).
- **Time zones / relative time:** presets computed against the current calendar; "Pick a time…" rejects past times.

---

## 7. Out of scope (YAGNI)

- Per-reminder threshold tuning (the §3 rule is fixed) — deliberately excluded per the design decision.
- Location-based reminders.
- Cross-device sync of reminders (no backend).
- Real-time push (no backend) — activity reminders are best-effort by construction.
- Editing the notification copy / rich notification actions (snooze, mark-read from the banner) — possible later.

---

## 8. Testing approach

- **Pure logic (unit, Swift Testing):** the §3 fire rule + re-arm math (table of `new`/`elapsed` → fire?/re-arm); preset date resolution (§2.4) incl. the "this evening already passed" case and past-time rejection; the subtree new-comment delta reuse; notification-content + deep-link `URL.SpudInternalLink` construction; the due-selection query (`nextCheckAt <= now`) and poll throttle.
- **Data layer (SpudDataKitTests):** `v35_reminder` round-trip; upsert-by-unique-key (one time + one activity per target; toggle removes); status/`unseen` transitions; badge-count query.
- **Service:** `ReminderService.pollDueReminders` against a stub transport (fire on ≥5 new; fallback on 24h; failure → backoff → `failed`), reusing the `LemmyService` stub-transport harness.
- **UI:** a snapshot of the Inbox Reminders segment (empty, pending, fired states) on the reference device; the "Remind Me…" menu wiring.
- Notification scheduling/permission are hard to unit-test — cover the content/URL construction purely and leave the `UNUserNotificationCenter` glue to on-device verification.

---

## 9. Suggested implementation phasing (for the plan)

Each phase is independently shippable/testable:

1. **Foundation + time reminders:** `v35_reminder` + records/writes/observations; `ReminderService` (create/toggle/remove); the notification layer (permission, delegate, tap-routing); time-preset resolution; the "Remind Me…" menu (whole post, time presets only); the Inbox **Reminders** segment (list + open + remove) reading the durable table; badge for fired-unseen.
2. **Activity follow (whole post):** the §3 rule + baseline seed/re-arm; `pollDueReminders` in `SchedulerService.tick()` (foreground); the "When there are new comments" menu item; activity notification content; diagnostics.
3. **Comment-subtree scope:** both triggers on a comment (subtree identity + `NewCommentState`/`CommentCollapseState` delta); the comment context-menu entry; scroll-to-subtree on tap.
4. **Background polling + polish:** `BGAppRefreshTask` registration + Info.plist/`project.yml`; badge blending with `UnreadCountService`; failure/`failed`-state UX; optional Account shortcut row; snapshot + docs.

---

## 10. Docs

New `docs/features/reminders.md` (PM-level, Given/When/Then Scenarios: set a time reminder from a post; set a "new comments" follow; follow a comment subtree; a reminder fires (notification + Inbox); notifications-denied degradation; remove a reminder). Update `docs/features/README.md` capability table + by-area map. Reconcile the Inbox/notifications docs.
