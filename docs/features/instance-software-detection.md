# Instance software detection

- **Surfaces:** `iphone`, `ipad`
- **Status:** partial — bare-instance link signpost (probing link taps for non-Lemmy hosts) deferred
- **Related:** [Login](login.md), [Registration](registration.md), [Instance picker](instance-picker.md), [Instance browsing (open an instance in-app)](instance-browsing.md)

## What it does

Before letting you log in or register on an instance, Spud probes the instance's NodeInfo
(`/.well-known/nodeinfo`) to determine what server software it runs. If the instance runs
non-Lemmy software — PieFed, Mbin, Mastodon, and others — the attempt is blocked with an
action sheet that names the software, explains it is not yet supported, and offers an
"Open in Safari" shortcut. Lemmy instances proceed normally. When the probe fails or is
blocked (for example, by a WAF), Spud fails open and lets the login or registration flow
continue exactly as before. The instance-detail screen also shows a small badge with the
detected software name when one is known.

## Behavior and rules

- **Pre-flight on login and register only.** NodeInfo is probed before the login or
  registration network call is sent, blocking the attempt when non-Lemmy software is
  detected. The probe runs only on explicit home-connection engagement — login, register,
  and opening an instance's detail screen — never during feed browsing, pagination, or
  community-list rendering.
- **Fail-open on undetermined software.** When the NodeInfo probe fails (network error,
  timeout, WAF block, or an unrecognized response body), the software is considered
  undetermined and the flow continues as if no detection had occurred. This preserves
  the pre-existing behavior for instances that restrict metadata endpoints.
- **Block sheet for non-Lemmy software.** When the detected software is not Lemmy, an
  action sheet appears with the message "<Software> isn't supported yet — <host> runs
  <Software>. Spud can only connect to Lemmy instances right now." Two actions are
  offered: "Open in Safari" (opens the instance's root URL in the browser) and "Cancel"
  (dismisses and returns to the previous screen).
- **Federated browsing from an existing Lemmy account is unaffected.** Browsing a PieFed
  or Mbin community while signed in to a Lemmy account is not affected: all federation
  traffic routes through the user's Lemmy home instance. Detection only blocks making a
  non-Lemmy instance a home connection (login or register).
- **Result caching.** NodeInfo responses are cached with a multi-day TTL, so repeat
  engagements on the same host — opening its instance-detail screen multiple times, then
  attempting login — do not repeat the network round-trip.
- **Instance-detail badge.** When the detected software name is known, the instance-detail
  screen displays a small badge showing that name. When the result is undetermined, no
  badge is shown and the screen renders as before.

## Scenarios

### Log in to a non-Lemmy host — blocked

- **Given** I have chosen an instance whose NodeInfo reveals it runs PieFed (or another
  non-Lemmy platform)
- **When** I attempt to log in
- **Then** an action sheet appears: "PieFed isn't supported yet — <host> runs PieFed.
  Spud can only connect to Lemmy instances right now."
- **And** I can tap "Open in Safari" to open the instance in the browser, or "Cancel" to
  dismiss and return without logging in

### Register on a non-Lemmy host — blocked

- **Given** I have chosen an instance whose NodeInfo reveals it runs non-Lemmy software
- **When** I attempt to register
- **Then** the same unsupported-software action sheet appears, blocking the attempt and
  offering "Open in Safari" and "Cancel"

### Log in to a Lemmy host — proceeds normally

- **Given** I have chosen a Lemmy instance
- **When** the pre-flight runs
- **Then** the NodeInfo probe confirms Lemmy software and the login screen and flow continue
  as normal

### Register on a Lemmy host — proceeds normally

- **Given** I have chosen a Lemmy instance
- **When** the pre-flight runs
- **Then** registration proceeds as normal

### NodeInfo probe fails or is WAF-blocked — fail-open

- **Given** I have chosen an instance whose NodeInfo endpoint is unreachable, returns an
  error, or is silently blocked
- **When** the pre-flight runs
- **Then** the software is considered undetermined, the probe is silently ignored, and the
  login or registration flow continues exactly as before

### Open an instance's detail screen — software badge shown

- **Given** I open an instance's detail screen and NodeInfo detection returns a known
  software name
- **When** the screen loads
- **Then** a small badge displaying the software name (for example, "PieFed") is shown on
  the instance-detail screen

### Open an instance's detail screen — no badge when undetermined

- **Given** I open an instance's detail screen and the NodeInfo probe is inconclusive
  (network failure, unrecognized response, or blocked endpoint)
- **When** the screen loads
- **Then** no software badge is shown; the screen renders as if no detection had occurred

### Privacy: probes only on explicit engagement

- **Given** I am browsing feeds, a community list, or any other feed surface
- **When** posts or community rows from a PieFed or Mbin instance appear in the list
- **Then** no NodeInfo probe is made for that instance — probes are restricted to login,
  register, and explicitly opening an instance's detail screen

### Federated browsing from a Lemmy account is unaffected

- **Given** I am signed in to a Lemmy instance and I open a community hosted on a
  PieFed instance
- **When** I browse posts or read content in that community
- **Then** Spud makes no home-connection attempt to PieFed and no block sheet appears;
  all federation traffic routes through my Lemmy home instance as usual

## Not supported / out of scope

- **Bare-instance link signpost.** Tapping an instance link in post or comment body text,
  or a community-header chip, does not trigger a NodeInfo probe. Probing along the
  general link-tap path would touch arbitrary external URLs and would violate the privacy
  boundary. Only login, register, and the explicit instance-detail screen opener
  pre-flight NodeInfo. A better-scoped candidate (the Search paste-to-open path) is
  deferred.
- **Actually speaking non-Lemmy APIs.** Detection is awareness only. Spud does not
  implement PieFed, Mbin, or Mastodon API clients; this feature blocks a home-connection
  attempt to those instances rather than silently failing later.
- **Signed-out "visit instance" guarding.** The anonymous-browse bootstrap path is not
  pre-flighted in this release.
- **Version gaps within Lemmy itself.** This feature only distinguishes Lemmy from
  non-Lemmy software; it does not gate anything based on *which* Lemmy version a home
  connection runs. A Lemmy 1.0 home instance is let through here and instead has specific
  features gated by [Instance capability gating](instance-capability-gating.md).
