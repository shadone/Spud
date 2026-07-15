# PieFed instances

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — browse-only (Phase 1). Reading a PieFed instance works; logging in and every write/interaction (vote, save, subscribe, comment, post, private messages, inbox) is Phase 2 and not shipped yet.
- **Related:** [PieFed integration design](../superpowers/specs/2026-07-15-piefed-integration-design.md), [Instance software detection](instance-software-detection.md), [Instance browsing (open an instance in-app)](instance-browsing.md), [Instance capability gating](instance-capability-gating.md), [Sign-in gate on write actions](sign-in-gate.md), [Signed-out browsing](signed-out-browsing.md), [Search](search.md), [Person / user profile](person-profile.md)

## What it does

[PieFed](https://join.piefed.social) is a threadiverse server, like Lemmy, but it exposes a
different HTTP API (`/api/alpha`) with differently-named fields. Spud can now **browse** a
PieFed instance directly — its feeds, communities, individual posts with their comment
trees, and search — not just see PieFed content that federates into a Lemmy instance.

When Spud detects (via NodeInfo) that an instance runs PieFed, it routes that instance's
reads through a dedicated PieFed dialect in its API layer, which translates PieFed's
responses into the same neutral shape Lemmy content uses. The rest of the app renders a
PieFed feed, community, post, or search result with the same cells and screens it uses for
Lemmy — the user never sees the difference.

This is browse-only for now. You cannot yet log in to a PieFed instance, and the
interactive actions (voting, saving, subscribing, commenting, posting, messaging) are not
available on a PieFed instance in this release — they are the next phase of the work.

## Behavior and rules

- **Detected, not configured.** Whether an instance is treated as PieFed comes from the
  same NodeInfo probe as [Instance software detection](instance-software-detection.md): a
  host whose `/.well-known/nodeinfo` reports `piefed` software is routed through the PieFed
  dialect. A host that hasn't been probed, or whose probe is inconclusive, is not treated
  as PieFed (Spud falls back to its Lemmy-version-based handling) — the same fail-open
  posture detection uses everywhere.
- **Version numbers are not shared with Lemmy.** A PieFed version string (e.g. "1.7.5")
  is never interpreted on the Lemmy version scale. Detection of PieFed software takes
  precedence over any version parsing, so a PieFed instance is never mistaken for a
  particular Lemmy release.
- **Browse surfaces that work:** the instance post feed (All / Local / etc. with the usual
  sorts), a community's screen (header + its feed), a post's detail with its full comment
  tree, and Search — across all four scopes (posts, communities, users, comments) — all
  decoded through the shared neutral content types. Opening a community by its federation
  address (resolve-object) works too, so tapping "Visit c/…" from a PieFed post lands on
  that community. **Opening a person profile does not** — from an author tap or a Search
  Users-scope result alike — see "Not supported" below.
- **Browsing a PieFed instance does not require an account.** The signed-out browse path
  routes to the PieFed dialect exactly as a signed-out Lemmy browse routes to Lemmy. No
  credentials are needed and none are requested.
- **Interaction attempts hit the standard sign-in gate.** Because PieFed browsing is
  always signed-out in this release, tapping any write action — vote, save, reply,
  subscribe, report, compose — presents the same pre-emptive "Sign in to `<action>`"
  sheet (with a warning haptic) that signed-out Lemmy browsing shows, before anything
  dialect-specific runs; no request is sent and no error appears. See
  [Sign-in gate on write actions](sign-in-gate.md). (The gate's Log in path then runs
  into the PieFed login block below — Phase 2 lifts that.)
- **Read tracking stays local on PieFed.** Marking a post read as you open it is a local
  action; the optional server "mark read" round-trip has no PieFed implementation yet.
  That round-trip is currently NOT withheld by the capability-gating mechanism
  ([Instance capability gating](instance-capability-gating.md) reports everything
  available for PieFed in Phase 1) — the call is attempted, the PieFed dialect rejects it
  as unsupported, and the failure is logged without any user-facing alert. A known
  Phase-1 seam: the PieFed capability gap set arrives in Phase 2. Nothing about this is
  visible in the UI.
- **Login and registration remain blocked.** The NodeInfo pre-flight still stops a
  login/registration attempt to a PieFed home instance with the "isn't supported yet"
  sheet (see [Instance software detection](instance-software-detection.md)); authenticated
  PieFed support is Phase 2.
- **Federated PieFed content in a Lemmy feed is unchanged.** Seeing a PieFed community or
  post that federates into your Lemmy home instance never depended on this feature and
  still works through your Lemmy account. This feature is specifically about making a
  PieFed instance itself something Spud can read.
- **PieFed-native extras decode harmlessly.** Fields PieFed adds that have no Lemmy
  equivalent (reactions, flair, topics, post type, and similar) are ignored during
  decoding rather than causing a failure; they are not surfaced as features yet.

## Scenarios

### Browse a PieFed instance's feed

- **Given** I open (browse) an instance that runs PieFed, without an account
- **When** the Posts feed loads
- **Then** the instance's posts render in the normal feed — titles, community handles,
  scores, comment counts, timestamps, and thumbnails — exactly as a Lemmy feed would

### Open a community on a PieFed instance

- **Given** I am browsing a PieFed instance
- **When** I open one of its communities (for example, via a post's "Visit c/…" action)
- **Then** the community screen renders with its header (name, handle, subscriber/post
  stats, banner/icon) and its post feed

### Open a post and read its comments

- **Given** I am browsing a PieFed instance
- **When** I tap a post
- **Then** the post detail renders (title, body, author attribution, score, comment count)
  and its comment tree loads and renders below it

### Search a PieFed instance

- **Given** I am browsing a PieFed instance
- **When** I search from the Search tab
- **Then** results render across the federated scopes (posts, communities, users,
  comments) using the same result cells as a Lemmy search

### Opening a person profile does not work

- **Given** I am browsing a PieFed instance
- **When** I tap a post or comment author, or open a result from Search's Users scope
- **Then** the Person profile screen never loads that person's PieFed data — tapping an
  author (whose row is already known locally from the post/comment) shows a generic
  "Couldn't load" error with a "pull to refresh" hint that cannot succeed, while opening a
  Search Users-scope result (whose person isn't known locally yet) instead leaves the screen
  on its loading spinner indefinitely, with no error shown at all
- **And** no PieFed-specific message appears either way — the underlying calls
  (`personDetails`/`personContent`) are Phase-2 endpoints with no PieFed implementation yet,
  and the existing instance-capability-gating mechanism doesn't catch this because it fails
  open for non-Lemmy software

### Dialect is chosen from detected software

- **Given** an instance whose NodeInfo reports it runs PieFed
- **When** Spud builds the connection used to read it
- **Then** reads dispatch through the PieFed dialect (PieFed's `/api/alpha`), regardless of
  the instance's reported version string

### A sparse PieFed instance still renders

- **Given** a small self-hosted PieFed instance with only a handful of posts
- **When** I browse its feed
- **Then** the feed and site load without error and show whatever content exists

### Tapping vote (or any write action) shows the sign-in gate

- **Given** I am browsing a PieFed instance (always signed-out in this release)
- **When** I tap upvote on a post (or save, reply, subscribe, report, or compose)
- **Then** the standard "Sign in to vote" (or matching "Sign in to …") sheet appears with
  a warning haptic, offering Create account / Log in / Not now
- **And** no request is sent to the instance and no error is shown

### Logging in to a PieFed instance is still blocked

- **Given** I choose a PieFed instance and attempt to log in or register
- **When** the pre-flight runs
- **Then** the "PieFed isn't supported yet" sheet appears and the attempt is blocked
  (browsing is available; authenticating is not, in this release)

## Not supported / out of scope

- **Opening a person profile.** Tapping a post/comment author, or a result in Search's
  Users scope, pushes the Person profile screen, but its underlying fetch
  (`personDetails`/`personContent`) is a Phase-2, auth-shaped endpoint with no PieFed
  implementation yet. From an author tap — where the person's row is usually already known
  locally, mirrored from the post/comment — the profile screen loads and then shows a
  generic "Couldn't load" error with a "pull to refresh" hint that cannot succeed. From a
  Search Users-scope result — where the person typically isn't known locally yet — the
  screen instead sits on its loading spinner indefinitely, with no error shown at all; the
  fetch failure is only logged, never surfaced. Search's Users scope itself still returns
  real PieFed results (see the Behavior bullet above) — only opening one is broken. This
  isn't caught by [Instance capability gating](instance-capability-gating.md), which fails
  open for non-Lemmy software rather than withholding the feature.
- **Logging in / registering on a PieFed instance.** Authenticated PieFed support —
  including the different login field and error format PieFed uses — is Phase 2.
- **Every interaction on a PieFed instance.** Voting, saving, subscribing, hiding,
  commenting, posting, editing, reporting, moderation, private messages, the inbox, and
  notifications are not available on a PieFed instance in this release; they require auth
  and are Phase 2. Attempting one shows the standard sign-in gate (see the behavior
  bullet and scenario above), never a PieFed-specific error.
- **PieFed-native features.** PieFed differentiators such as emoji reactions, flair,
  topics, custom feeds, and mark-comment-as-answer are not surfaced. They decode without
  error but are Phase 3, opportunistic work.
- **Other non-Lemmy platforms.** This feature adds PieFed only. Mbin, Mastodon, and other
  software are still detected and blocked at login/registration, not browsable
  (see [Instance software detection](instance-software-detection.md)).
