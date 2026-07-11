# Subscribe / unsubscribe

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Search](search.md), [Discover (Community Explorer)](discover.md), [Subscriptions sidebar](subscriptions-sidebar.md), [Voting](voting.md), [Saving](saving.md), [Drafts and Outbox](drafts-and-outbox.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Subscribe to a community to follow it, or unsubscribe to stop. The same toggle is reachable from the [Community screen](community-screen.md) header and context menu, a community row in [Search](search.md) results, [Discover](discover.md), and an instance's community list. Like voting and saving, a subscribe / unsubscribe is applied **optimistically** — the community's subscribed state and your subscriptions list update immediately in the local store — and is sent in the background through the same durable, per-account mutation outbox that handles vote / save / hide, which retries transient failures and rolls back permanent ones. Subscribing requires being signed in.

## Behavior and rules

- **Instant everywhere, via the durable outbox.** Tapping Subscribe or Unsubscribe writes the community's subscribed state and your followed-communities membership to the local database synchronously, in one transaction, before any network call. Every surface reading that state — the Community screen header, the Subscribed section of the [Communities tab](subscriptions-sidebar.md), and any other open row for the same community — reflects the change at once, the same instant the tap lands.
- **Pending is the honest optimistic state; Requested is the confirmed "awaiting approval" answer.** The moment you tap Subscribe, the button reads Pending: that's the truthful "not sent yet" state, not a guess at the outcome. Once the background send completes, the server's actual answer replaces it — Subscribed for a community anyone can join, or **Requested** for a Lemmy 1.0 community that gates joining behind moderator approval and hasn't decided yet. So Pending always means "queued, not sent"; Requested (an hourglass) means "sent, and the community's moderators are yet to approve your request". These are stored as distinct states, so the app can tell "queued" from "awaiting approval" rather than showing the same Pending for both. (Against an older v3 server, which cannot distinguish the two, an approval-gated request still surfaces as Pending.)
- **A denied request keeps Subscribe as the action, with a "Request declined" hint.** If a community's moderators deny your follow request (a Lemmy 1.0 outcome), the state is recorded distinctly as denied. The header button's primary action stays **Subscribe** so you can request again, but it carries a secondary **Request declined** line (and a matching VoiceOver label, "Subscribe. Your previous request was declined.") so the prior rejection is visible rather than looking identical to a community you never subscribed to.
- **Background send, with retry and rollback.** The change is sent in the background with automatic retry and backoff — it works offline, since the change is queued durably and survives an app relaunch before it sends. If the server permanently rejects it, the community and your subscriptions revert to their pre-tap state, and the shared "Couldn't update subscription" toast appears — the same failure toast used for a failed vote, save, or hide.
- **A server refresh in flight doesn't clobber an in-flight subscribe.** While a subscribe or unsubscribe is queued or sending, a server-driven refresh of that community (reopening its page, a full-account refresh) does not overwrite the optimistic state in either direction: an optimistic subscribe not yet reflected in the account's server-side follow list survives, and an optimistic unsubscribe still present there is not resurrected. The refresh's normal effect on that community resumes once the send's own authoritative answer lands.
- **Sign-in gate.** Subscribing is gated on being signed in. A signed-out attempt fires a warning haptic and shows a "Sign in to subscribe" alert before anything is written; the service also rejects a signed-out subscribe.
- **Toggle against current state.** The action resolves against the current subscribed state — tapping the control subscribes when not subscribed and unsubscribes when subscribed. There is no separate unsubscribe control; it is the same toggle. Toggling back to the original state before the queued change has sent cancels it outright — no network call is made.
- **Tap haptic on submit.** Submitting a subscribe / unsubscribe fires a tap haptic.
- **The Community screen and Communities tab are instant from the first tap; Search is instant only for a community already cached locally.** The Community screen (which fetches community info before showing the button) and the Communities tab (which only ever lists already-subscribed communities) always operate on a community that already has a local database row, so the durable optimistic write above — including the instant database-backed flip — applies the moment you tap, with no extra step. A [Search](search.md) result row may or may not have a local row yet: a community already cached (seen before in a feed or another screen) gets the same instant database flip; a community found only through this search still gets the row's own immediate flip and a durably queued send, but the database — and every other open surface for that community — only catches up once the send lands.
- **Discover and instance-browsing resolve the community first, then apply instantly.** These two list directory rows that may not yet be a known server community, so subscribing first resolves the row to a server community id (a brief network lookup — Discover shows a spinner on the row while it resolves; instance-browsing's Join button flips its own row immediately regardless, matching the rest of the app). Once resolved, the same instant, durable write applies as everywhere else. Both surfaces additionally keep their own pre-existing cell-local optimistic touch, redundant with (but no worse than) the database-driven flip above; a permanent failure on either surface rolls back through the same shared outbox mechanism and toast, not a bespoke per-row alert.

## Scenarios

### Subscribe from the community header

- **Given** a Community screen for a community I do not subscribe to, while signed in
- **When** I tap Subscribe in the header
- **Then** the button reads Pending immediately, before any network call
- **And** once the background send completes, the button and subscriber count update to the server's confirmed result (Subscribed, or Requested if the community requires moderator approval)

### Unsubscribe from the community header

- **Given** a Community screen for a community I subscribe to
- **When** I tap the Subscribed button (or choose Unsubscribe from the header context menu)
- **Then** the button reads Subscribe immediately, and the unsubscribe is sent in the background

### Subscribe from a search result

- **Given** a community row in search results showing Subscribe, while signed in
- **When** I tap Subscribe
- **Then** the button immediately reads Subscribed (or Pending) and the change is durably queued and sent

### An offline subscribe still applies immediately

- **Given** I am offline
- **When** I subscribe to (or unsubscribe from) a community that already has a local database row (the header, the Communities tab, or a search result for a community I've already seen elsewhere)
- **Then** the local state changes right away
- **And** the change is queued durably and sends automatically once I'm back online, surviving an app relaunch in the meantime
- **And** for a search result discovered only through this search (no cached local row yet), the row's own button still flips right away and the change is durably queued the same way — the database state simply catches up once the send goes through, rather than at tap time

### A permanent subscribe failure rolls back

- **Given** a subscribe or unsubscribe that the server permanently rejects
- **When** the background send exhausts its retries
- **Then** the community and my subscriptions revert to their state from before the tap, and a "Couldn't update subscription" toast appears

### Signed-out subscribe is blocked

- **Given** I am signed out
- **When** I tap Subscribe on a community (header, search row, Discover, or an instance's community list)
- **Then** a warning haptic fires and a "Sign in to subscribe" alert is shown, and nothing is written

### A community needing approval shows Requested

- **Given** a Lemmy 1.0 community that requires moderator approval to join
- **When** I subscribe and the background send completes
- **Then** the Community screen header shows Requested (an hourglass) — the server's own confirmed "awaiting approval" answer, distinct from the momentary just-tapped Pending
- **And** against an older v3 server that cannot distinguish the two, the header shows Pending instead

### A denied follow request shows Subscribe with a declined hint

- **Given** a community whose moderators denied my follow request
- **When** the Community screen reflects the server's answer
- **Then** the header button's primary action reads Subscribe again, so I can request to join once more
- **And** it shows a "Request declined" secondary line (conveyed to VoiceOver as "Subscribe. Your previous request was declined.") so the prior rejection is not hidden

## Not supported / out of scope

- No bulk subscribe / unsubscribe outside Discover's per-starter-pack "Subscribe to all" (see [Discover](discover.md)), and no "manage subscriptions" editor; the [Subscriptions sidebar](subscriptions-sidebar.md) lists communities but does not unsubscribe from a row.
- Approving or managing pending follow requests is a server-side action, not handled in the app.
- The durable retry / rollback queue mechanics are shared with vote / save / hide; see [Voting](voting.md), [Saving](saving.md), and [Drafts and Outbox](drafts-and-outbox.md) for the wider outbox story.
