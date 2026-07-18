# Fun stats (usage odometer)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Account Activity](account-activity.md) (the per-account Summary dashboard —
  Fun Stats is device-wide, account-free, and a separate screen from Summary's stat tiles
  and heatmap), [Diagnostics logging](diagnostics-logging.md)

## What it does

Fun Stats is a playful, device-wide usage odometer reachable from Preferences > About >
Fun Stats: a hero "distance scrolled" figure with a real-world landmark comparison
("That is 2.4x the height of Burj Khalifa"), plus tiles and rows for taps, posts read and
seen, images viewed, links opened, sessions, time in app, streaks, most active hour, votes
cast, comments and posts written, pull-to-refreshes, and searches run. Everything is
collected and stored locally on the device only, is not tied to any signed-in account, and
never leaves the device.

## Behavior and rules

- 13 counters are recorded, each bucketed into a `(local day, local hour)` row and
  accumulated by upsert: scroll distance, taps, pull-to-refreshes, posts opened, posts
  seen, images viewed, links opened, sessions, time in app (foreground seconds), votes
  cast, comments posted, posts posted, and searches run. Lifetime totals are the sum
  across all buckets; two streak lengths and the most-active hour are derived from the
  same bucketed data at read time, not stored separately.
- Streaks are counted over distinct active days: the current streak tolerates no activity
  yet today (a run ending today or yesterday still counts as "current," so opening the app
  first thing in the morning doesn't read as a broken streak); the longest streak is the
  best run anywhere in the device's history. The screen's "Longest streak" tile shows the
  longest streak.
- Most-active-hour is computed only from event-shaped counters (excluding time-in-app),
  so long foreground sessions don't drown out which hour actually has the most activity.
- Scroll distance converts points to a real-world distance using a fixed, deliberately
  fun-not-science constant of 1 point = 1/163 inch, displayed as "42 m" below 1 km and
  "12.3 km" at or above it. The landmark comparison line picks the single largest landmark
  already passed (Eiffel Tower, Burj Khalifa, Mount Everest, the Mariana Trench, the
  Karman line, the ISS orbit altitude) and phrases it as a multiple of that landmark; no
  line appears until scrolling has passed the smallest landmark.
- A new session is counted when the app becomes active more than 5 minutes after it last
  left the foreground; time in app accumulates the elapsed foreground time each time the
  app resigns active.
- "Taps" counts every completed touch anywhere in the app, including the lift at the end
  of a drag, not just discrete tap gestures.
- Scroll distance is tracked on 5 scrolling scenes (the post list, post detail, Inbox, a
  direct-message thread, and Account Activity) and reported in 1,000-point batches rather
  than per scroll event. Rubber-band overshoot at either end of a scroll view contributes
  nothing, and a single jump larger than one viewport height (a programmatic scroll-to-top
  or position restore) is treated as a resync, not user-driven distance.
- Votes (post and comment), comments posted, and posts posted are each counted once per
  user action, at the moment the action is dispatched (including while offline, where the
  action is queued for later delivery) — a later network retry of the same queued action
  never double-counts it. Editing an existing post does not count as a new post.
- A network search counts once per search dispatched to the server; the client-side
  instance-directory filter (which never contacts the network) does not count as a search.
- Collection can be turned off from Preferences > Privacy ("Collect Fun Stats", on by
  default). Turning it off stops recording new activity immediately; any counters already
  recorded stay on the device and remain visible on the Fun Stats screen. Turning it back
  on resumes recording without touching what's already there.
- "Reset Stats," reached from the screen's overflow menu, is a destructive action gated
  behind a confirmation dialog. Once confirmed it erases every recorded counter; if a
  background flush of just-recorded activity was already in flight when Reset Stats was
  tapped, the reset always wins and that activity is discarded too.
- Recording is best-effort: recent activity is buffered in memory and periodically written
  to the database, and a write failure silently drops the buffered increments rather than
  surfacing an error or otherwise affecting the app.
- There is no backfill: every counter starts at zero the moment this feature first ships
  on a device, regardless of how long the app was used before.

## Scenarios

### First visit shows the empty state

- **Given** I have never used the app since this feature shipped (no fun stats have been
  recorded yet)
- **When** I open Preferences > About > Fun Stats
- **Then** the hero distance reads "0 m" with no landmark comparison
- **And** every tile shows zero
- **And** the footer reads "Counting starts today" instead of a "Counting since" date

### Scrolling accumulates distance and unlocks a landmark comparison

- **Given** I am on the Fun Stats screen with some existing scroll distance recorded
- **When** I scroll through feeds, post detail, Inbox, DM threads, and Account Activity
  enough that my lifetime scroll distance passes the height of the Eiffel Tower (330 m)
- **Then** the hero card shows the accumulated distance in meters or kilometers
- **And** a landmark comparison line appears below it (e.g. "That is 1.2x the height of
  the Eiffel Tower")

### Disabling the collection toggle freezes counters

- **Given** Fun Stats has recorded some activity and "Collect Fun Stats" is on in
  Preferences > Privacy
- **When** I turn "Collect Fun Stats" off
- **Then** further scrolling, tapping, and other tracked activity no longer changes any
  counter
- **And** the counters already on the Fun Stats screen remain exactly as they were,
  unchanged

### Reset clears everything after confirmation

- **Given** the Fun Stats screen shows nonzero counters
- **When** I tap the overflow menu, tap "Reset Stats," and confirm the destructive dialog
- **Then** every counter on the screen returns to zero
- **And** the footer reverts to "Counting starts today"

### Streak shown after consecutive days of use

- **Given** I have opened the app and generated some tracked activity on each of several
  consecutive days, up to and including today
- **When** I open the Fun Stats screen
- **Then** the "Longest streak" tile shows the number of consecutive days as "N days" (or
  "1 day" for a single day)

## Not supported / out of scope

- No sharing or Share-as-Image card for Fun Stats.
- No per-account breakdown — Fun Stats is a single device-wide odometer, not scoped to any
  signed-in account, and is unaffected by switching or signing out of accounts.
- No recaps, summaries, or notifications built on top of the collected data.
- No sync between devices — the data behind Fun Stats never leaves the device it was
  recorded on.
- The Home Screen widget and the "Open in Spud" share extension do not record any
  activity into Fun Stats; only activity inside the main app is counted.
