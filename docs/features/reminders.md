# Reminders

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — Phases 1-2 of a multi-phase design: time-based ("remind me later") reminders, and a whole-post "When there are new comments" activity follow, both on a whole post only. Comment-subtree targeting and background polling are planned for later phases; see Not supported below.
- **Related:** [Inbox](inbox.md), [docs/superpowers/specs/2026-07-12-post-reminders-design.md](../superpowers/specs/2026-07-12-post-reminders-design.md), [docs/superpowers/plans/2026-07-12-post-reminders-phase1.md](../superpowers/plans/2026-07-12-post-reminders-phase1.md), [docs/superpowers/plans/2026-07-13-post-reminders-phase2.md](../superpowers/plans/2026-07-13-post-reminders-phase2.md)

## What it does

A "Remind Me…" action on a post lets you schedule a one-shot local notification for a
chosen time — a few hours from now, this evening, tomorrow, or a custom pick. The same
menu also offers "When there are new comments" — a standing follow that watches the
post's discussion and notifies you once it's grown enough to be worth another look,
instead of a single fixed moment. Every reminder or follow you set also shows up in a
dedicated "Reminders" segment of the Inbox, whether or not it's fired yet, and a
fired-but-not-yet-seen one lights the Inbox tab's badge, just like an unread reply or
mention.

## Behavior and rules

- **Entry point.** "Remind Me…" appears in the post-detail "•••" overflow menu and the
  feed cell's long-press context menu, targeting the whole post. It's a flat list of
  time presets — In 3 hours, This evening, Tomorrow, In 2 days, In a week, Pick a
  time… — followed by "When there are new comments", then, when a time reminder is
  already set on that post, a destructive "Cancel reminder" action. Choosing a preset or
  a picked time shows a brief confirmation toast ("Reminder set — Tomorrow"); cancelling
  shows "Reminder cleared."
- **"When there are new comments" is a self-toggling follow, independent of time
  reminders.** Unlike the time presets, it's a single menu item that checkmarks when live
  and toggles on tap — choosing it follows the post ("You'll be notified of new
  comments."); choosing it again while already following unfollows it ("Stopped
  following."). A post can carry a time reminder and an activity follow at once; each is
  set/cancelled independently and neither affects the other's row in the Reminders
  segment.
- **The smart rule for "new enough to notify."** Following a post baselines its current
  comment count. From then on, a fired notification requires either **5 or more** new
  comments since the last check (or since following, for the first fire), **or** at least
  **1** new comment that's been sitting unnotified for **24 hours** — whichever comes
  first. Zero new comments never fires. Once it fires, the count re-baselines from the
  comment total at that moment, so the next notification again needs a fresh 5-or-24h's
  worth of activity.
- **Checked by a foreground poll, not push.** There's no reminders backend, so nothing
  can push a "new comments" event to your device. Instead, while Spud is in the
  foreground, a periodic sweep (piggybacking on the existing 5-minute scheduler tick)
  re-checks each followed post's comment count — throttled to at most once per ~30
  minutes per post — and applies the rule above. This means a burst of comments is
  noticed on a delay (the next foreground check), not instantly, and a followed post is
  never checked at all while Spud is fully quit or backgrounded for a long stretch; it
  catches up the next time you open the app. Works whether you're signed in or just
  browsing signed out — the poll doesn't require an account.
- **Time presets resolve relative to now.** "This evening" means today at 18:00, unless
  it's already past ~17:00, in which case it falls back to three hours from now so the
  reminder never fires immediately or in the past. "Pick a time…" rejects any time that
  isn't strictly in the future.
- **One live reminder per post, per kind.** Setting a second time reminder on a post you
  already have one on replaces it (new time, same reminder) rather than creating a second
  entry; the activity follow is a separate kind with its own single live-or-not state, so
  it's never affected by a time reminder being set or cancelled, and vice versa.
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
  Lemmy notifications. Time reminders and activity follows appear side by side as
  separate rows (a post following both shows up twice). Each row shows the post's
  thumbnail, title, and `c/<community>@<instance>` handle, plus a status line whose text
  depends on the kind: a time reminder shows a relative countdown ("in 2 days") while
  still scheduled, or "Tap to revisit" once fired; an activity follow shows "Watching for
  new comments" while live, or "New comments · tap to catch up" once the rule fires (no
  live count on the row — see [Not supported](#not-supported--out-of-scope)).
  Fired-and-unseen rows sort first; the rest sort soonest-due first. Tapping a row opens
  the post. Swipe left to remove a reminder or follow (cancels its notification too, if
  one was scheduled).
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

### Follow a post's comments

- **Given** I am viewing a post with 12 comments
- **When** I choose "Remind Me…" → "When there are new comments"
- **Then** a confirmation toast shows ("You'll be notified of new comments.")
- **And** the menu item now shows a checkmark
- **And** the post appears in the Inbox's Reminders segment, showing "Watching for new
  comments" as its status
- **And** the follow's baseline comment count is set to 12 (today's count) — only
  comments posted after this point count toward the notify rule

### The poll fires on the smart rule

- **Given** I'm following a post's comments (baseline 12) and Spud is in the foreground
- **When** a periodic check finds the comment count has reached 17 (5 new) — or finds it
  at 13 (1 new) after the follow has sat unnotified for 24 hours — whichever happens
  first
- **Then** a system notification is delivered (if I granted notification permission),
  naming the post and community
- **And** the reminder's row in the Reminders segment now reads "New comments · tap to
  catch up"
- **And** the Inbox tab badge increases to reflect the newly-fired, unseen follow
- **And** the baseline re-arms to the count at fire time, so the next notification again
  needs a fresh 5-or-24h's worth of activity

### Unfollow a post's comments

- **Given** a post has a live "When there are new comments" follow
- **When** I choose "Remind Me…" → "When there are new comments" again (its checkmark is
  showing), or swipe-to-remove its row in the Reminders segment
- **Then** a confirmation toast shows ("Stopped following.")
- **And** the menu item's checkmark clears
- **And** the row disappears from the Reminders segment, and no further checks happen for
  that post

### Following works while signed out

- **Given** I am browsing signed out (no account)
- **When** I follow a post's comments
- **Then** the follow is created and polled exactly as it would be for a signed-in
  account — activity follows don't require sign-in

## Not supported / out of scope

- **Comment-subtree reminders** — targeting a specific comment thread (rather than the
  whole post) is a later phase.
- **Background polling / `BGAppRefreshTask`** — the activity follow's poll only runs
  while Spud is in the foreground (piggybacking on the existing 5-minute scheduler tick);
  there's no background task, so a post's comment count is only ever re-checked the next
  time the app is opened or foregrounded, not while it's quit or backgrounded. This is a
  best-effort, honestly-limited notification, not a guaranteed real-time one — treat it
  as "Spud will catch you up the next time you open it," not "you'll be notified the
  moment it happens."
- **A live new-comment count on the Reminders-segment row.** A fired activity follow's
  row just reads "New comments · tap to catch up" — it doesn't say how many, unlike the
  push notification's body, which does.
- **Rescheduling a pending reminder in place** — to change a reminder's time, cancel it
  and set a new one; there's no "edit" affordance on an existing row yet.
- **Cross-device sync** — reminders are on-device only; there's no backend, so setting a
  reminder (or follow) on one device doesn't create it on another.
