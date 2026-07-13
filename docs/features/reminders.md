# Reminders

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — Phase 1 of a multi-phase design: time-based ("remind me later") reminders on a whole post only. A "when there are new comments" activity trigger and comment-subtree targeting are planned for later phases; see Not supported below.
- **Related:** [Inbox](inbox.md), [docs/superpowers/specs/2026-07-12-post-reminders-design.md](../superpowers/specs/2026-07-12-post-reminders-design.md), [docs/superpowers/plans/2026-07-12-post-reminders-phase1.md](../superpowers/plans/2026-07-12-post-reminders-phase1.md)

## What it does

A "Remind Me…" action on a post lets you schedule a one-shot local notification for a
chosen time — a few hours from now, this evening, tomorrow, or a custom pick. Every
reminder you set also shows up in a dedicated "Reminders" segment of the Inbox, whether
or not its notification has fired yet, and a fired-but-not-yet-seen reminder lights the
Inbox tab's badge, just like an unread reply or mention.

## Behavior and rules

- **Entry point.** "Remind Me…" appears in the post-detail "•••" overflow menu and the
  feed cell's long-press context menu, targeting the whole post. It's a flat list of
  time presets — In 3 hours, This evening, Tomorrow, In 2 days, In a week, Pick a
  time… — plus, when a reminder is already set on that post, a destructive "Cancel
  reminder" action. Choosing a preset or a picked time shows a brief confirmation toast
  ("Reminder set — Tomorrow"); cancelling shows "Reminder cleared."
- **Time presets resolve relative to now.** "This evening" means today at 18:00, unless
  it's already past ~17:00, in which case it falls back to three hours from now so the
  reminder never fires immediately or in the past. "Pick a time…" rejects any time that
  isn't strictly in the future.
- **One live reminder per post.** Setting a second reminder on a post you already have
  one on replaces it (new time, same reminder) rather than creating a second entry.
- **Reminders are local and durable, not a server feature.** Lemmy has no reminders API
  — the reminder lives entirely on-device (there's no reminders backend, so nothing
  syncs across your devices) and survives app relaunches. Because of this, the
  Reminders segment works even on an instance whose other Inbox features (replies,
  mentions, messages) are unavailable.
- **Delivery: a real OS notification, or in-app only.** The first time you set a
  reminder, Spud asks for notification permission. If you grant it, a reminder delivers
  a system notification at its scheduled time — title is the post's title, body names
  the community, and tapping it opens the post — even if Spud isn't running. If you
  deny (or later disable) notifications, reminders still work entirely in-app: they
  still appear in the Reminders segment and still light the tab badge once their time
  passes, they just don't push a system notification. Spud reconciles any reminder
  whose time has already passed to "fired" the next time the app launches or comes to
  the foreground, so this degrades gracefully — a reminder is never silently lost.
- **The Reminders segment.** A dedicated segment in the Inbox tab's segmented control
  (after Mentions), separate from Replies/Mentions/Messages so reminders never mix with
  Lemmy notifications. Each row shows the post's thumbnail, title, and
  `c/<community>@<instance>` handle, plus a status line: a relative countdown ("in 2
  days") while still scheduled, or "Tap to revisit" once fired. Fired-and-unseen rows
  sort first; the rest sort soonest-due first. Tapping a row opens the post. Swipe left
  to remove a reminder (cancels its notification too, if one was scheduled).
- **The badge only counts fired-and-unseen reminders.** A scheduled (not yet due)
  reminder never contributes to the badge — only a reminder that has fired and hasn't
  been seen in the Reminders segment yet. The reminder contribution is blended into the
  same Inbox tab badge total as unread replies/mentions/messages (see
  [Inbox](inbox.md)).
- **Opening the segment marks its fired reminders seen.** The moment you switch to the
  Reminders segment, every fired reminder is marked seen and the badge's reminder
  contribution drops — live, without needing a pull-to-refresh.

## Scenarios

### Set a time reminder from a post

- **Given** I am viewing a post
- **When** I choose "Remind Me…" → "Tomorrow" from the overflow menu
- **Then** a confirmation toast shows ("Reminder set — Tomorrow")
- **And** the post appears in the Inbox's Reminders segment, showing "in 1 day" (or
  similar, depending on the exact time) as its status

### A reminder fires

- **Given** I set a time reminder that has now come due
- **When** its scheduled time passes
- **Then** a system notification is delivered (if I granted notification permission) —
  title is the post's title, tapping it opens the post
- **And** the reminder's row in the Reminders segment now reads "Tap to revisit"
- **And** the Inbox tab badge increases to reflect the newly-fired, unseen reminder

### Opening the Reminders segment clears its badge contribution

- **Given** a fired reminder is contributing to the Inbox tab badge
- **When** I switch to the Reminders segment
- **Then** that reminder is marked seen and the badge's reminder contribution drops
  immediately

### Cancel a reminder

- **Given** a post has a live (not-yet-fired) reminder
- **When** I choose "Remind Me…" → "Cancel reminder", or swipe-to-remove its row in the
  Reminders segment
- **Then** a confirmation toast shows ("Reminder cleared.")
- **And** its scheduled system notification (if any) is cancelled
- **And** the row disappears from the Reminders segment

### Notifications denied — in-app degradation

- **Given** I denied (or later disabled) notification permission
- **When** I set a time reminder and its scheduled time passes
- **Then** no system notification is delivered
- **And** the reminder still appears fired in the Reminders segment and still
  contributes to the tab badge, the next time the app is open or foregrounded

## Not supported / out of scope

- **Activity ("when there are new comments") reminders** — following a post so it
  notifies you as new comments arrive is a later phase; today's "Remind Me…" menu is
  time presets only. (The foreground poll this later phase builds on already lands
  behind the scenes: like time reminders, it works whether you're signed in or just
  browsing signed out, and only checks while Spud is in the foreground — the menu
  item to actually set one is still to come.)
- **Comment-subtree reminders** — targeting a specific comment thread (rather than the
  whole post) is a later phase.
- **Background polling / `BGAppRefreshTask`** — not part of this phase; reminders are
  reconciled on launch and foreground, not via a background task.
- **Rescheduling a pending reminder in place** — to change a reminder's time, cancel it
  and set a new one; there's no "edit" affordance on an existing row yet.
- **Cross-device sync** — reminders are on-device only; there's no backend, so setting a
  reminder on one device doesn't create it on another.
