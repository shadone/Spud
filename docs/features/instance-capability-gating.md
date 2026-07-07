# Instance capability gating

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — gates six features (person profiles, inbox, private messages, image upload, hide post, profile/settings save) plus one silent soft-degrade (server read-state sync); speaking Lemmy's v4 API itself is separate, unshipped future work (initiative Phase 5/6)
- **Related:** [Inbox](inbox.md), [Private messages](private-messages.md), [Person / user profile](person-profile.md), [Account Activity](account-activity.md), [Image upload](image-upload.md), [Edit your profile](profile-editing.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [Instance software detection](instance-software-detection.md), [Diagnostics logging](diagnostics-logging.md), [docs/superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md](../superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md), [docs/superpowers/plans/2026-07-07-lemmy-v4-phase1-capability-gating.md](../superpowers/plans/2026-07-07-lemmy-v4-phase1-capability-gating.md)

## What it does

Spud detects when a signed-in account's home instance is running Lemmy 1.0 and adapts
automatically: the handful of features that instance's transitional API doesn't yet serve
are explained instead of failing with a raw server error, while everything else — feeds,
posts, comments, communities, voting, saving — keeps working exactly as before. Detection
costs nothing extra: it reads the Lemmy version Spud already records (from NodeInfo before
login, and from every subsequent `getSite` response), and re-checks it live, so an instance
that upgrades mid-session degrades on its very next site refresh with no relaunch or
re-login required.

## Behavior and rules

- **Why Lemmy 1.0 needs this at all.** A 1.0 server keeps serving a partial, always-on v3
  compatibility shim so older clients like Spud keep working. That shim is missing exactly:
  person profiles, the replies/mentions inbox, all private-message operations, image
  upload, hiding a post, saving profile/settings, and server-side read-state sync. Spud
  speaks the v3 API today, so those specific endpoints — and only those — stop responding
  once an instance is on 1.0.
- **Where the version comes from.** `InstanceCapabilities` is derived on `PlatformProfile`
  from the instance's software and parsed version. The version itself comes from whichever
  of two sources has run most recently: NodeInfo's `software.version` (probed pre-login —
  see [Instance software detection](instance-software-detection.md)) or `SiteRecord.version`,
  which is recorded from **every** `getSite` import. The capability check reads the
  persisted version live on each access — it is never cached on a screen or view model —
  so a version change lands the moment it's next read, not just on next app launch.
- **Fail-open by default.** Only a positively parsed Lemmy version with major ≥ 1 gates
  anything. An instance still on 0.19.x, an instance whose version string is missing or
  unparseable (a fork with an unrecognized scheme, or a site row not yet imported), and any
  non-Lemmy software all resolve to every capability being available — mirroring instance
  software detection's own fail-open rule that a mis-gate (blocking something that actually
  works) is worse than an occasional raw server error slipping through.
- **Two presentation styles.** For anything a user could reasonably try to use —
  opening a person profile, opening the inbox, attaching an image, hiding a post, opening
  or saving profile edits, using a DM thread — the gate explains itself: an action sheet or
  a terminal empty state names the instance and says the feature "isn't available yet" and
  that "support is coming in an update." For background or preference-sync operations where
  a sheet would be noisy and the client already behaves correctly without the round-trip
  (the unread badge, the NSFW show/blur toggles, the default-sort preference, post
  read-state sync), the server push is skipped silently — nothing appears on screen, and
  the local behavior is entirely unaffected.
- **Backstop enforcement in the service layer.** Every gated `LemmyService` operation
  checks its own capability and throws `LemmyServiceError.unsupportedByInstance` before any
  network call, independent of whichever UI entry point called it. The mutation/content
  outboxes classify this error as a **permanent** failure (never retried — no amount of
  retrying can make an endpoint exist), and every block — both the throwing kind and the
  silent soft-degrades — records a `capability.blocked` event to the diagnostic log (see
  [Diagnostics logging](diagnostics-logging.md)).
- **Inbox and private messages are gated independently, even though Lemmy 1.0 currently
  blocks both together.** The inbox tab (replies, mentions, and messages together) is
  gated by one capability; sending or reading a DM thread and the inbox's compose button
  are gated by a separate one. They happen to flip together on today's Lemmy 1.0, but are
  modeled separately so a future server version that restores one without the other degrades
  correctly.
- **Federated content browsing is entirely unaffected.** Feeds, posts, comments,
  communities, search, and voting/saving all keep working regardless of the home instance's
  version — none of that surface reads a capability.

## Scenarios

### Home instance upgrades to Lemmy 1.0 mid-session

- **Given** I am signed in to an instance still on Lemmy 0.19, with the app open
- **When** the instance is upgraded to 1.0 and the next `getSite` refresh (a scheduler tick
  or a pull-to-refresh) imports the new version string
- **Then** the next time a gated screen is opened or a gated action is attempted, it shows
  its explanatory state — no relaunch, re-login, or manual refresh of the gating itself is
  needed

### Fresh login to a Lemmy 1.0 instance

- **Given** I log in to (or start browsing) an instance already on Lemmy 1.0
- **When** the account's `getSite` info is fetched and imported
- **Then** the gated features described below show their explanatory state from that point
  on, and everything else works normally

### Home instance still on Lemmy 0.19 — nothing changes

- **Given** my home instance's persisted version is 0.19.x
- **When** I use any part of the app, including the six gated features
- **Then** nothing is gated — every feature behaves exactly as it did before this feature
  shipped

### Instance version is unknown or unparseable — fails open

- **Given** the home instance's version hasn't been imported yet, or its version string
  doesn't parse as a leading integer (e.g. an unfamiliar fork's version scheme)
- **When** any capability is checked
- **Then** every capability resolves to available and nothing is gated — the same
  behavior as before this feature existed

### Inbox is gated with an explanatory state

- **Given** my home instance is on Lemmy 1.0
- **When** I open the Inbox tab
- **Then** the tab stays reachable but shows "Inbox isn't available yet" for every scope
  (Replies, Mentions, and Messages alike), naming the instance and noting support is coming
- **And** the mark-all-read button and the new-message compose button are both hidden

### Opening a person profile is gated; Activity falls back to local-only

- **Given** my home instance is on Lemmy 1.0
- **When** I open someone's profile (from a search result, a mention, or a post/comment
  attribution)
- **Then** a terminal "Profiles aren't available yet" state is shown instead of the profile
  header and content
- **And** my own Account Activity timeline still shows everything Spud tracks locally
  (votes, saves, reads, hides) but omits authored posts and comments, since fetching those
  requires the same gated person-content endpoint

### Attaching an image to a new post is gated

- **Given** my home instance is on Lemmy 1.0
- **When** I tap "Attach image" in the new-post composer
- **Then** an action sheet explains that image upload isn't available yet on this instance
- **And** the attach button remains visible and enabled — tapping it again shows the same
  explanation rather than the button disappearing

### Hiding a post from the feed is gated

- **Given** my home instance is on Lemmy 1.0
- **When** I choose "Hide" from a post's context menu
- **Then** an action sheet explains that hiding posts isn't available yet on this instance,
  and the post is not hidden
- **And** marking posts read and the local "Hide Read Posts" view filter (see
  [Marking posts read and hiding read posts](mark-read-and-hiding.md)) are unaffected — only
  the server-backed explicit hide is gated

### Editing your profile is gated

- **Given** my home instance is on Lemmy 1.0
- **When** I tap my profile header on the Account tab to open Edit Profile
- **Then** an action sheet explains that profile editing isn't available yet, instead of the
  editor opening

### A private-message thread is gated

- **Given** my home instance is on Lemmy 1.0
- **When** I open an existing DM thread, or try to start a new one
- **Then** the thread shows a gated explanatory state and its compose input is disabled
- **And** attempting to send from a thread that was already open when the instance upgraded
  is also rejected with an explanatory alert — never silently dropped or queued

### Soft degrades apply silently, without gating UI

- **Given** my home instance is on Lemmy 1.0
- **When** I toggle "Show NSFW Content" or NSFW blur, change my default post sort, or the
  app checks for unread inbox items, or a post is marked read
- **Then** each preference still applies locally exactly as it always has (feed filtering,
  blur rendering, sort order, local read tracking), the unread badge simply reads zero, and
  no sheet, alert, or error appears — the corresponding server push is skipped quietly

### A blocked operation is recorded to the diagnostic log

- **Given** my home instance is on Lemmy 1.0 and I trigger any gated action, or a silent
  soft-degrade skips its server push
- **When** I later open Settings → About → Logs → Event Log
- **Then** a `capability.blocked` event is present, naming the blocked capability and the
  instance — visible even though nothing was shown on screen at the time for a soft-degrade

## Not supported / out of scope

- **Speaking Lemmy's v4 API is not implemented here.** This feature only detects the
  version gap and explains around it; actually adopting the v4 API (cursors, new inbox
  shape, image-first-class upload, and so on) is separate future work — see the initiative
  design doc's Phase 5/6.
- **No manual override.** There is no setting to force-enable a gated feature. The gate
  lifts automatically once Spud speaks the instance's newer API, or if the instance is
  rolled back to 0.19.
- **Not a software-compatibility gate.** Blocking a non-Lemmy home connection outright is a
  separate, earlier feature — see [Instance software detection](instance-software-detection.md).
  This feature only concerns version gaps *within* Lemmy.
- **Federated/remote content browsing is never gated.** Reading feeds, posts, comments, and
  communities — including ones hosted on a Lemmy 1.0 instance you don't have a home account
  on — is unaffected; gating only applies to your own home-instance account's write/profile
  operations.
