# Instance browsing (open an instance in-app)

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Discover (Community Explorer)](discover.md), [Instance picker](instance-picker.md), [Community screen](community-screen.md), [Search](search.md), [Person / user profile](person-profile.md), [External link handling](external-link-handling.md), [Instance software detection](instance-software-detection.md)

## What it does

Tapping an instance name anywhere in the app — the source-instance chip in a community header, an instance link in post or comment body text, the instance suggestion when you paste a server address into Search, or an instance link on a person's profile — opens that instance's in-app screen (banner, description, sidebar, stats, admins, and its communities). Instances in the bundled Lemmy Explorer directory open instantly. An instance that is *not* in the directory is resolved on the spot: Spud probes the server's `/api/v3/site`, and if it answers like a Lemmy server — which includes PieFed, since PieFed speaks the same `/api/v3` API — the instance opens in-app just like a directory one. Only servers that don't speak the Lemmy API (or are unreachable) fall back to opening in the browser. The communities list comes from the bundled directory when available; when the directory has none for that host — most notably a synthesized remote/PieFed instance — Spud fetches the instance's own communities live via `/api/v3/community/list` so the list isn't empty.

## Behavior and rules

- **One path for every instance tap.** Community header chip, body-text instance links, Search paste-to-open, and person-profile instance links all route through the same open-instance flow, so they behave identically.
- **Directory hit opens immediately.** When the host is in the bundled Explorer directory, the in-app instance screen opens straight away from the cached directory record — no network call.
- **Unknown host is resolved by a single probe.** When the host is not in the directory, Spud shows a brief spinner and fetches the server's `/api/v3/site` once. A valid response is both the compatibility test and the data source: the screen's identity, description, sidebar, stats (total users, active users this month and half-year, communities, posts, comments), version, and admins are all read from that one response.
- **PieFed and other Lemmy-API-compatible servers open in-app.** Because the probe is the Lemmy site endpoint, any server that implements it — Lemmy itself, PieFed, and other compatible software — opens in-app. There is no separate per-software allowlist; answering `/api/v3/site` is the test.
- **Non-compatible or unreachable hosts fall back to the browser.** If the probe fails (the server isn't Lemmy-API-compatible, times out, or is unreachable), the spinner is dismissed and the host opens in the system browser instead, exactly as before.
- **Communities are fetched live when the directory has none.** The screen first shows the bundled directory's communities for the host. When that snapshot is empty — which is always the case for a synthesized remote/PieFed instance, and for any directory instance with nothing seeded — Spud fetches the instance's own communities live from `/api/v3/community/list` (local listing, top-subscribed first, up to 50) through the same signed-out browsing account used for the site probe, and the rows appear once they load. The live fetch never overwrites a populated directory list. A non-Lemmy or unreachable host simply leaves the list empty rather than failing the screen.
- **The curated directory is never modified.** A resolved unknown instance is held in a session-only, in-memory cache, kept entirely separate from the bundled Explorer directory table that Discover and the instance list read. The curated directory's contents and ranking are unchanged; a synthesized instance never leaks into those surfaces. The live-fetched communities are transient render rows, not mirrored into the directory or the persistent feed.
- **Repeat taps in the same session are instant.** Once an unknown host has been resolved, tapping it again that session reopens its screen from the session cache with no second network round-trip. The cache is not persisted; relaunching the app re-probes on the next tap.
- **Link classification is unchanged.** Deciding whether a tapped link is a Lemmy reference at all (and prefilling login) still uses the directory's known-instance check; only the act of *opening* an instance screen now probes. A normal link tap never triggers a network probe.
- **A deeper "before you commit" detail is one tap further.** The in-app instance screen's health/trust card pushes a richer instance-detail screen (uptime, software version, signups, federation) — the same screen used by the [instance picker](instance-picker.md) before you add an account. Its software badge and Signups row prefer live NodeInfo metadata over the directory snapshot when a probe has resolved, fail-open otherwise; see [Instance software detection](instance-software-detection.md) for the detection and copy rules.

## Scenarios

### Open a directory instance from a community header

- **Given** I am viewing a community whose source instance is in the bundled directory
- **When** I tap the source-instance chip in the header
- **Then** the in-app instance screen opens immediately, showing the instance's banner, stats, admins, and communities

### Open an unknown but Lemmy-API-compatible instance in-app

- **Given** I tap an instance name (e.g. a PieFed instance such as `fedinsfw.app`) that is not in the bundled directory
- **When** the tap is registered
- **Then** a brief spinner shows while Spud probes the server's `/api/v3/site`
- **And** because the server answers like a Lemmy server, the in-app instance screen opens with that instance's name, description, sidebar, stats, and admins

### A synthesized instance shows its communities fetched live

- **Given** I opened an instance that is not in the bundled directory (e.g. a PieFed instance such as `fedinsfw.app`), so the directory has no communities for it
- **When** the screen loads
- **Then** Spud fetches the instance's own communities live from `/api/v3/community/list`
- **And** the community list populates with those rows instead of staying empty

### A non-compatible or unreachable host opens in the browser

- **Given** I tap an instance name whose server does not speak the Lemmy `/api/v3` API, or is unreachable
- **When** the probe fails or times out
- **Then** the spinner is dismissed
- **And** the host opens in the browser instead

### A resolved instance reopens instantly later in the session

- **Given** I already opened an unknown instance in-app earlier this session
- **When** I tap that same instance again
- **Then** its in-app screen opens immediately from the session cache, with no second network request

## Not supported / out of scope

- **Live community list is a single unpaged page.** When the directory has no communities for a host, Spud fetches one page of the instance's own local communities (top-subscribed first, up to 50) — enough to populate the screen, but not a full, paginated browse of every community on the instance. The live rows carry only the fields `/api/v3/community/list` returns (name, title, description, icon, counts, published date); they are not de-duplicated across servers the way the directory's rows are. If the live fetch fails (non-Lemmy server, timeout, unreachable) the list stays empty; the header, description, sidebar, stats, and admins still render from the site probe.
- **No persistence of resolved instances.** Resolved unknown instances live only in memory for the session; they are never written to the curated directory and do not survive a relaunch.
- **The `/api/v3/site` probe is a compatibility check, not a software classifier.** It only checks that the server answers the Lemmy site endpoint. Software classification, the version-bearing badge, and the live Signups override on the instance-detail screen ("before you commit", reached by tapping the health card) all come from a separate, fail-open NodeInfo detection layer; see [instance-software-detection.md](instance-software-detection.md).
- **Directory ranking and contents are untouched.** This feature does not add, remove, or re-rank anything in the bundled Explorer directory or Discover.
