# Reminders

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — all four planned post-reminder phases (time-based "remind me
  later" reminders, a "When there are new comments" activity follow, a best-effort
  background poll, and account-teardown cleanup) plus a third follow type: a community
  "Notify About New Posts" follow, reachable from five surfaces.
- **Related:** [Inbox](inbox.md), [Instance meta communities](instance-meta-communities.md), [docs/superpowers/specs/2026-07-12-post-reminders-design.md](../superpowers/specs/2026-07-12-post-reminders-design.md), [docs/superpowers/plans/2026-07-12-post-reminders-phase1.md](../superpowers/plans/2026-07-12-post-reminders-phase1.md), [docs/superpowers/plans/2026-07-13-post-reminders-phase2.md](../superpowers/plans/2026-07-13-post-reminders-phase2.md), [docs/superpowers/plans/2026-07-13-post-reminders-phase3.md](../superpowers/plans/2026-07-13-post-reminders-phase3.md), [docs/superpowers/plans/2026-07-13-post-reminders-phase4.md](../superpowers/plans/2026-07-13-post-reminders-phase4.md), [docs/superpowers/specs/2026-07-19-community-new-posts-follow-design.md](../superpowers/specs/2026-07-19-community-new-posts-follow-design.md)

## What it does

A "Remind Me…" action on a post lets you schedule a one-shot local notification for a
chosen time — a few hours from now, this evening, tomorrow, or a custom pick. The same
menu also offers "When there are new comments" — a standing follow that watches the
post's discussion and notifies you once it's grown enough to be worth another look,
instead of a single fixed moment. A third kind of follow lives on the community itself
rather than a post: "Notify About New Posts" watches a whole community and notifies you
the moment it publishes anything new — useful for a low-traffic community like an
instance's own announcements, where waiting for "enough" new comments would mean never
hearing about it. Every reminder or follow you set also shows up in a dedicated
"Reminders" segment of the Inbox, whether or not it's fired yet, and a
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
- **Follow a single comment thread instead of the whole post.** The same "Remind Me…"
  submenu also appears on a comment's long-press context menu — same items, same copy,
  but every action now targets that comment's subtree (the comment and all of its
  descendants) rather than the whole post. A post can carry a whole-post reminder AND one
  or more thread-scoped reminders on different comments at once, each set, checkmarked,
  and cancelled independently. The submenu is omitted (not shown, not disabled) on a
  comment that isn't fully loaded yet (e.g. a "load more" placeholder).
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
  worth of activity. A thread-scoped follow applies the identical rule against that root
  comment's own descendant count instead of the post's total, and — like the whole-post
  case — counts **every** new descendant, including your own replies to the thread; it
  isn't limited to other people's comments.
- **A community "new posts" follow, from five entry points.** "Notify About New Posts"
  follows a whole community instead of a single post, so you hear about its very next
  post rather than its next comment. It's reachable from: the community screen's "•••"
  overflow menu and its header long-press context menu (grouped next to Subscribe and
  Favourite); a community result's long-press context menu in [Search](search.md); the
  bell button on a meta community's row in the Communities tab's "About `<instance>`"
  section (see [Instance meta communities](instance-meta-communities.md)); and a
  subscribed community's row context menu in the Communities tab. Like the activity
  follow, it's a single toggling action — choosing it follows, choosing it again
  unfollows. Confirmation feedback differs by surface: the community screen's
  overflow/header menu and a Search result's context menu show a toast ("You'll be
  notified of new posts." / "Stopped notifying."), while the Communities tab's meta-row
  bell and a subscribed community's row context menu instead give haptic feedback and
  flip the bell's fill state, with no toast. Every surface shares the same title and
  bell icon, filled while live.
- **A community follow fires on any new post — not the 5-or-24h smart rule.** Unlike the
  new-comments activity follow, a community follow notifies on **1 or more** new posts
  since it was last checked, full stop; there's no comment-count threshold or 24-hour
  fallback to wait out. This is deliberate: an activity follow's post already exists and
  is just accumulating discussion, so it's worth batching small updates, but an
  announcement-style community may post only rarely — holding back its one post a month
  until "enough" arrived would defeat the entire point of following it.
- **One notification per check, naming the count.** If a check finds several new posts
  at once (Spud was away for a while, or the community had a burst), they're still
  batched into a single notification — "3 new posts · c/name@instance" — not one per
  post. If the newest-posts page fetched during the check turned out to be entirely new
  posts (the community outpaced what a single page can show), the count reads with a
  "+", e.g. "10+ new posts · c/name@instance", since there may be more beyond what was
  fetched.
- **The watermark is best-effort, not exact.** Following a community records "now" as
  its watermark with no network round trip, so the follow is instant; the first poll's
  server-confirmed newest-post timestamp then re-arms the watermark precisely, which
  self-corrects for the device clock being off. Two edge cases are accepted as
  known/best-effort rather than fixed: a device clock running ahead of the server's can
  miss a post published inside that skew window right after you follow, and a post that
  federates in late with an older `published` timestamp than when it actually arrived
  never fires (the watermark has already moved past it).
- **Muting pauses a follow; unmuting fires the backlog as one batch.** A muted
  community's posts are already being kept out of your feeds, so the poll skips checking
  it for new posts entirely while muted — no notification, and the watermark stays
  where it was. Unmuting resumes checks, and the very next poll sees everything the
  community posted while muted as new (since the watermark never moved) and fires it as
  a single batched notification, same as any other multi-post check.
- **Blocking a community removes its follow.** Blocking is an explicit "never show me
  this again" — so blocking a community you're notify-following also removes that
  follow, the same as if you'd unfollowed it yourself. Unblocking later does not restore
  it; follow it again if you want it back.
- **Subscribing and notify-following are fully independent.** A community follow has
  nothing to do with your Subscribed feed — you can notify-follow a community you don't
  subscribe to (the usual case for an announcements community you just want a heads-up
  from), subscribe without following, or both. See [Subscribe / unsubscribe](subscribe-unsubscribe.md).
- **Works signed out, same as activity follows.** A community follow is local and
  per-account (including the signed-out "browsing" account), so it works while browsing
  anonymously — including from the Communities tab's meta-row bell, which is available
  signed in or out.
- **Checked by a foreground poll, not push.** There's no reminders backend, so nothing
  can push a "new comments" event to your device. Instead, while Spud is in the
  foreground, a periodic sweep (piggybacking on the existing 5-minute scheduler tick)
  re-checks each followed post's comment count — throttled to at most once per ~30
  minutes per post — and applies the rule above. This means a burst of comments is
  noticed on a delay (the next foreground check), not instantly. Works whether you're
  signed in or just browsing signed out — the poll doesn't require an account. A
  community follow is checked by the same sweep, at the same ~30-minute per-item
  throttle, against the community's newest posts instead of a post's comment count.
- **Best-effort background delivery.** Beyond the foreground poll, Spud also asks iOS to
  occasionally wake it in the background (a `BGAppRefreshTask`) to run the exact same
  check, so a follow can still notify you even while Spud is closed. This is honestly
  opportunistic, not a guarantee: iOS decides if and when it actually runs — it requires
  Background App Refresh to be enabled for Spud (Settings app → General → Background App
  Refresh), and even then the OS can delay it by hours, or skip it entirely, based on
  your usage patterns and battery state. The foreground poll above remains the reliable
  path whenever Spud is open; treat the background wake-up as a bonus catch-up, not
  something to rely on for time-sensitive follows.
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
- **Removing or logging out of an account cancels its reminders.** Reminders and
  follows are per-account. Logging out of a signed-in account, or removing any account
  (signed-in or signed-out) from the account list, deletes every one of that account's
  reminders and follows and cancels their scheduled OS notifications, so nothing keeps
  firing for an account that's no longer in the app.
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
  Lemmy notifications. Time reminders, activity follows, and community follows all
  appear side by side as separate rows (a post following both a time reminder and an
  activity follow shows up twice, and a thread-scoped follow is its own additional row).
  A post-scoped row (time or activity) shows the post's thumbnail, title, and
  `c/<community>@<instance>` handle; a community-follow row shows the community's icon,
  its title, and the same `c/<community>@<instance>` handle. Each row's status line text
  depends on its kind and scope: a whole-post time reminder shows a relative countdown
  ("in 2 days") while still scheduled, or "Tap to revisit" once fired — a thread-scoped
  time reminder reads identically, since the countdown itself doesn't depend on scope. A
  whole-post activity follow shows "Watching for new comments" while live, or "New
  comments · tap to catch up" once the rule fires; a thread-scoped one instead shows
  "Watching a thread for new replies" while live, or "New replies · tap to catch up" once
  fired, so a followed thread is never mistaken for a followed whole post in the same
  list. A community follow shows "Watching for new posts" while live, or "New posts · tap
  to catch up" once fired (no live count on any fired row — see
  [Not supported](#not-supported--out-of-scope)). Fired-and-unseen rows sort first; the
  rest sort soonest-due first. Tapping a row opens its target — a post-scoped reminder
  opens the post (a thread-scoped one scrolled to, and briefly highlighting, that
  comment, same as opening a comment permalink), and a community-follow row opens the
  community screen. Swipe left to remove a reminder or follow (cancels its notification
  too, if one was scheduled).
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

### Follow a single comment thread

- **Given** I am viewing a post and long-press a comment that has 4 replies so far
- **When** I choose "Remind Me…" → "When there are new comments" from the comment's
  context menu
- **Then** a confirmation toast shows ("You'll be notified of new comments.")
- **And** the follow's baseline is set to 4 (that comment's current descendant count) —
  only replies to the thread posted after this point count toward the notify rule
- **And** the post also appears in the Inbox's Reminders segment as a separate row,
  showing "Watching a thread for new replies" as its status
- **And** the whole post itself can still independently carry its own "When there are new
  comments" follow (or not) — following the thread doesn't touch it

### A thread follow fires and opens scrolled to the comment

- **Given** I'm following a comment thread (baseline 4 replies) and the smart rule's
  threshold is met
- **When** the poll re-checks that comment's descendant count
- **Then** a system notification is delivered (if granted), and the reminder's row in the
  Reminders segment reads "New replies · tap to catch up"
- **And** tapping the notification (or the Reminders-segment row) opens the post scrolled
  to, and briefly highlighting, that comment — not just the top of the post
- **And** the baseline re-arms to the descendant count at fire time

### A comment thread can also get a time reminder

- **Given** I am viewing a post and long-press a comment
- **When** I choose "Remind Me…" → "Tomorrow" from the comment's context menu
- **Then** a confirmation toast shows ("Reminder set — Tomorrow"), and when it fires,
  tapping it opens the post scrolled to that comment (not the whole-post behavior of
  opening at the top)

### Follow a community from its overflow menu

- **Given** I am viewing a community
- **When** I choose "Notify About New Posts" from the "•••" overflow menu (or the
  header's long-press context menu)
- **Then** a confirmation toast shows ("You'll be notified of new posts.")
- **And** the menu item now shows a checkmark and a filled bell
- **And** the community appears in the Inbox's Reminders segment, showing "Watching for
  new posts" as its status
- **And** the follow's watermark is set to now — only posts published after this point
  count toward the next notification

### Follow a community from a meta-row bell

- **Given** I open the Communities tab and my home instance's "About `<instance>`"
  section is showing a meta community
- **When** I tap the bell button on that community's row
- **Then** the follow is created exactly as it would be from the community screen, and
  the bell fills to show it's live
- **And** this works whether I'm signed in or browsing signed out

### The poll fires on a single new post

- **Given** I'm following a community's new posts (watermark set at the last check) and
  Spud is in the foreground
- **When** a periodic check finds even a single post published after the watermark
- **Then** a system notification is delivered (if I granted notification permission),
  titled with the community's name and reading "1 new post · c/name@instance"
- **And** tapping it opens the community screen
- **And** the reminder's row in the Reminders segment now reads "New posts · tap to
  catch up"
- **And** the watermark re-arms to that post's published time, so the next notification
  again needs at least one more new post

### A muted community's backlog fires as one batch after unmute

- **Given** I'm following a community's new posts, and I mute that community while it
  publishes several new posts
- **When** I unmute it and the next periodic check runs
- **Then** none of those posts triggered a notification while muted (the poll skipped
  the community entirely, and the watermark didn't move)
- **And** the check after unmuting sees all of them as new at once and delivers a single
  batched notification naming the total count, not one per post

### Swipe-remove a community follow from the Inbox

- **Given** a community has a live "Notify About New Posts" follow, showing in the
  Reminders segment
- **When** I swipe left on its row and tap Remove
- **Then** the row disappears immediately, with no confirmation toast — same as
  swipe-removing any other reminder kind
- **And** no further checks happen for that community

### Toggle off a community follow from where you followed it

- **Given** a community has a live "Notify About New Posts" follow
- **When** I toggle "Notify About New Posts" off again from the community screen or a
  Search result's context menu
- **Then** a confirmation toast shows ("Stopped notifying.")
- **When** I instead toggle it off from its bell in the Communities tab (meta-row bell or
  a subscribed row's context menu)
- **Then** the bell empties and a haptic confirms the change, with no toast
- **And** either way, the row disappears from the Reminders segment and no further
  checks happen for that community

### Blocking a community removes its notify follow

- **Given** a community has a live "Notify About New Posts" follow
- **When** I block that community (from the community screen or a Search result) and
  confirm
- **Then** the community is blocked as normal
- **And** its notify follow is also removed, so a community I've explicitly asked never
  to see again can't keep notifying me

### Removing an account cancels its reminders

- **Given** a signed-in account has a scheduled time reminder and an active "When there
  are new comments" follow
- **When** I log out of that account, or remove it from the account list
- **Then** both are deleted, and the time reminder's scheduled OS notification is
  cancelled, so nothing fires for that account afterward — the same teardown also
  deletes any community follows on that account

## Not supported / out of scope

- **Guaranteed background delivery.** The `BGAppRefreshTask` background poll is
  opportunistic, not a guaranteed real-time one — iOS can delay or skip it, and it
  requires Background App Refresh to be enabled. Treat it as "Spud will try to catch you
  up even when closed," not "you'll be notified the moment it happens"; the foreground
  poll remains the only reliably-timed path.
- **A live new-comment (or new-post) count on the Reminders-segment row.** A fired
  activity or community follow's row just reads "New comments · tap to catch up" / "New
  posts · tap to catch up" — it doesn't say how many, unlike the push notification's
  body, which does.
- **A live post title (or any post content) in a community follow's notification.** The
  notification body names only a count and the community handle — "3 new posts ·
  c/name@instance" — never the new post's title, text, or thumbnail. This is
  deliberate, not a missing feature: the poll only reads publish timestamps, never post
  content, so nothing — including a title that might itself be NSFW or otherwise
  sensitive — can leak into a notification you might see on a lock screen.
- **Community follows from Discover.** A Discover row can be an unresolved directory
  entry with no home-instance server id yet (only a `resolve_object` round trip would
  get one), so "Notify About New Posts" isn't offered there — consistent with Discover's
  context menu already omitting Favourite for the same reason. Follow the community from
  the community screen, Search, or the Communities tab instead once it resolves.
- **Rescheduling a pending reminder in place** — to change a reminder's time, cancel it
  and set a new one; there's no "edit" affordance on an existing row yet.
- **Cross-device sync** — reminders are on-device only; there's no backend, so setting a
  reminder (or follow) on one device doesn't create it on another.
- **A thread follow's refresh is bounded, not exhaustive, on newer (v4) servers.** The
  poll refreshes a comment-subtree follow's count by paging through the post's comment
  listing until it finds the followed root comment, capped at a fixed number of pages.
  On a v3 server this never matters — its comment listing always comes back as one
  complete response. On a v4 server, a root comment that sorts past that page cap (an
  unusually deep position in a very large, very active thread) won't be found that
  check, so its count silently falls back to the last-known value instead of the live
  one — same effect as a single failed refresh: never a false notification, only a
  possible delay in a true one.
