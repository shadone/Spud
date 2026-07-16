# PieFed instances

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped — browse **and** sign in. Reading a PieFed instance works (feeds,
  communities, posts + comment trees, search, person profiles), and a signed-in account can
  vote, save, subscribe (follow), mark posts read, hide posts, comment (create / edit /
  delete), post (create / edit / delete), read the replies/mentions inbox, and send and read
  direct messages. A few account-management features are withheld on PieFed (image upload,
  server-side profile/settings save) and registration is web-only — see "Not supported".
- **Related:** [PieFed integration design](../superpowers/specs/2026-07-15-piefed-integration-design.md), [Instance software detection](instance-software-detection.md), [Instance browsing (open an instance in-app)](instance-browsing.md), [Instance capability gating](instance-capability-gating.md), [Sign-in gate on write actions](sign-in-gate.md), [Signed-out browsing](signed-out-browsing.md), [Search](search.md), [Person / user profile](person-profile.md), [Inbox](inbox.md), [Private messages](private-messages.md), [Session-expired re-login](session-reauth.md)

## What it does

[PieFed](https://join.piefed.social) is a threadiverse server, like Lemmy, but it exposes a
different HTTP API (`/api/alpha`) with differently-named fields and routes. Spud speaks that
dialect directly: when it detects (via NodeInfo) that an instance runs PieFed, it routes that
instance's requests through a dedicated PieFed dialect in its API layer, which translates
PieFed's responses into the same neutral shape Lemmy content uses. The rest of the app renders
a PieFed feed, community, post, profile, inbox, or DM thread with the same cells and screens it
uses for Lemmy — the user never sees the difference.

You can **browse** a PieFed instance signed-out, and you can **sign in** to a PieFed account and
interact with it: voting, saving, subscribing, commenting, posting, reading the inbox, and
messaging all work. PieFed logs in by **username** (not email), and its login response has no
2FA field. A small set of account-management capabilities that PieFed's API doesn't expose the
way Spud needs are withheld with an explanatory gate rather than a raw error (see below), and
creating a PieFed account is still done on the web.

## Behavior and rules

- **Detected, not configured.** Whether an instance is treated as PieFed comes from the same
  NodeInfo probe as [Instance software detection](instance-software-detection.md): a host whose
  `/.well-known/nodeinfo` reports `piefed` software is routed through the PieFed dialect. A host
  that hasn't been probed, or whose probe is inconclusive, is not treated as PieFed (Spud falls
  back to its Lemmy-version-based handling) — the same fail-open posture detection uses
  everywhere.
- **Login is username-based and routes through the dialect.** Signing in to a PieFed instance
  is allowed. The login pre-flight probes NodeInfo, which both confirms the software is PieFed
  and warms the software cache; the account's login request is then dispatched through the
  PieFed login route (`/api/alpha/user/login`, which takes a `username` + `password`, not
  Lemmy's `username_or_email`, and has no 2FA field). On success the account lands signed in
  and its own profile, subscriptions, and unread counts load like any Lemmy account.
- **Version numbers are not shared with Lemmy.** A PieFed version string (e.g. "1.7.5") is never
  interpreted on the Lemmy version scale. Detection of PieFed software takes precedence over any
  version parsing, so a PieFed instance is never mistaken for a particular Lemmy release.
- **Interactions that work signed in:** upvote / downvote / clear vote on posts (and comments),
  save / unsave, subscribe / unsubscribe (follow) a community, mark a post read (a real
  server round-trip now — see below), hide a post, create / edit / delete a comment, create /
  edit / delete a post, the replies and mentions inbox, unread counts, and direct messages
  (list, open a thread, send, and read). Each optimistic action drains through the same durable
  outboxes as Lemmy; a permanent server error rolls back a mutation or parks a content send,
  exactly as on Lemmy.
- **Reading a post marks it read on the server.** Opening a post pushes a mark-read round-trip
  to PieFed (`/api/alpha/post/mark_as_read`) in addition to the local read-state write. The
  Phase-1 seam that attempted this and logged an "unsupported" failure is closed — mark-read is
  a first-class PieFed operation now, and no error is logged when a post is opened.
- **Person profiles open.** Tapping a post or comment author, or a Search Users-scope result,
  opens the person's profile on a PieFed instance — the profile header and the person's posts
  and comments load through the PieFed dialect. (These are credential-free reads; the Phase-1
  dead-end where the profile screen showed "Couldn't load" or spun forever is gone.)
- **Browse surfaces that work signed-out:** the instance post feed (All / Local / etc. with the
  usual sorts), a community's screen (header + its feed), a post's detail with its full comment
  tree, person profiles, and Search — across all four scopes (posts, communities, users,
  comments) — all decoded through the shared neutral content types. Opening a community by its
  federation address (resolve-object) works too, so tapping "Visit c/…" from a PieFed post lands
  on that community.
- **Some account features are withheld with an explanation, not an error.** On a PieFed
  instance, image upload and server-side profile/settings save are held back by
  [Instance capability gating](instance-capability-gating.md) — the affordance stays visible and
  tapping it shows a short "isn't available yet" gate instead of a raw failure. Read state and
  local preferences still apply; only the *server push* of profile/settings is withheld. See
  "Not supported" for the full residual set.
- **Session expiry is handled.** When a PieFed session's token stops being accepted (its error
  body carries `not_logged_in` / `incorrect_login`), Spud recognizes it as an expired session
  and offers to re-log-in in place, the same as for Lemmy — a bare HTTP 403 (a WAF/CDN block) is
  deliberately not treated as expiry. See [Session-expired re-login](session-reauth.md).
- **Federated PieFed content in a Lemmy feed is unchanged.** Seeing a PieFed community or post
  that federates into your Lemmy home instance never depended on this feature and still works
  through your Lemmy account.
- **PieFed-native extras decode harmlessly.** Fields PieFed adds that have no Lemmy equivalent
  (reactions, flair, topics, post type, and similar) are ignored during decoding rather than
  causing a failure; they are not surfaced as features yet (Phase 3).

## Scenarios

### Sign in to a PieFed instance

- **Given** I choose a PieFed instance and enter my username and password
- **When** I tap "Log in"
- **Then** the pre-flight confirms the instance runs PieFed, the login is dispatched through the
  PieFed login route, and I land signed in — my Account screen shows my PieFed username and my
  authed feed loads

### Vote, save, and subscribe on a PieFed instance

- **Given** I am signed in to a PieFed instance and viewing a post
- **When** I upvote it, then downvote it, then clear my vote, and separately save it and
  subscribe to its community
- **Then** each action updates optimistically and persists — the vote survives a re-fetch of the
  post, the saved state sticks, and the community shows as subscribed on the community screen and
  in the Communities tab

### Comment on a PieFed post

- **Given** I am signed in to a PieFed instance and viewing a post
- **When** I add a comment (and later edit and delete it)
- **Then** the comment is created on the server and appears in the post's comment tree, and my
  edit and delete are reflected the same way they are on Lemmy

### Create a post on a PieFed instance

- **Given** I am signed in to a PieFed instance and viewing a community I can post to
- **When** I compose a new post (and later edit and delete it)
- **Then** the post is created in that community and appears in its feed, and my edit and delete
  are reflected

### Open a post and it is marked read on the server

- **Given** I am signed in to a PieFed instance
- **When** I open a post
- **Then** the post is marked read locally and a mark-read round-trip is sent to PieFed with no
  error (no "unsupported" failure is logged)

### Inbox and direct messages on a PieFed instance

- **Given** I am signed in to a PieFed instance
- **When** I open the Inbox
- **Then** the Replies and Mentions segments load without error (empty when there is nothing),
  and in Messages I can open a conversation, send a message, and see it appear in the thread

### Open a person profile on a PieFed instance

- **Given** I am browsing or signed in to a PieFed instance
- **When** I tap a post or comment author, or open a Search Users-scope result
- **Then** the Person profile screen loads that person's PieFed profile, posts, and comments

### Image upload is gated on a PieFed instance

- **Given** I am composing a new post on a PieFed instance
- **When** I tap "Attach image"
- **Then** a short "Image upload isn't available yet" gate appears instead of the photo picker —
  the rest of the composer still works

### Editing your profile is gated on a PieFed instance

- **Given** I am signed in to a PieFed instance
- **When** I tap "Edit profile" on the Account screen
- **Then** a short "Profile editing isn't available yet" gate appears — Spud does not push
  server-side profile/settings changes to PieFed yet; my local preferences still apply

### Registering on a PieFed instance routes to the web

- **Given** I choose a PieFed instance and try to register
- **When** the pre-flight runs
- **Then** the attempt is routed to the browser rather than handled in-app — PieFed account
  creation is web-only (logging in with an existing account works in-app)

### Dialect is chosen from detected software

- **Given** an instance whose NodeInfo reports it runs PieFed
- **When** Spud builds the connection used to read or act on it
- **Then** requests dispatch through the PieFed dialect (PieFed's `/api/alpha`), regardless of
  the instance's reported version string

## Not supported / out of scope

- **Creating a PieFed account in-app.** Registration (and any password-reset / email flow) is
  web-only: the register pre-flight routes to the browser. Logging in with an existing account
  works in-app.
- **Image upload.** Attaching an image to a post (or uploading an avatar/banner) is withheld on
  PieFed and shows the capability gate. Posting text and links works.
- **Server-side profile / settings save.** Editing your PieFed profile and pushing account
  settings to the server is withheld and shows the capability gate. Local preferences (sort,
  appearance, and the like) still apply on-device.
- **Account content lists driven by server flags.** The account's server-side Saved / liked /
  hidden / read *lists* are not surfaced for PieFed in this release (individual save / vote /
  hide actions do work).
- **Blocks.** Blocking a person is not wired for PieFed yet.
- **Per-message DM read receipts.** Opening a DM thread reads it locally, but PieFed has no
  per-message "mark this message read" round-trip in this release (the reply/mention inbox does
  mark read). Whether "mark all as read" also clears received private messages on PieFed is
  unconfirmed against a live account.
- **PieFed-native features.** PieFed differentiators such as emoji reactions, flair, topics,
  custom feeds, and mark-comment-as-answer are not surfaced. They decode without error but are
  Phase 3, opportunistic work.
- **Other non-Lemmy platforms.** This feature adds PieFed only. Mbin, Mastodon, and other
  software are still detected and blocked at login/registration, and are not browsable
  (see [Instance software detection](instance-software-detection.md)).
