# Subscribe / unsubscribe

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Search](search.md), [Discover (Community Explorer)](discover.md), [Subscriptions sidebar](subscriptions-sidebar.md), [Voting](voting.md), [Saving](saving.md), [Drafts and Outbox](drafts-and-outbox.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Subscribe to a community to follow it, or unsubscribe to stop. The same toggle is reachable from the [Community screen](community-screen.md) header and context menu, a community row in [Search](search.md) results, [Discover](discover.md), and an instance's community list. Like voting and saving, a subscribe / unsubscribe is applied **optimistically** — the community's subscribed state and your subscriptions list update immediately in the local store — and is sent in the background through the same durable, per-account mutation outbox that handles vote / save / hide, which retries transient failures and rolls back permanent ones. Subscribing requires being signed in.

## Behavior and rules

- **Instant everywhere, via the durable outbox.** Tapping Subscribe or Unsubscribe writes the community's subscribed state and your followed-communities membership to the local database synchronously, in one transaction, before any network call. Every surface reading that state — the Community screen header, the Subscribed section of the [Communities tab](subscriptions-sidebar.md), and any other open row for the same community — reflects the change at once, the same instant the tap lands.
- **Pending is the honest optimistic state — and sometimes the real server answer.** The moment you tap Subscribe, the button reads Pending: that's the truthful "not sent yet" state, not a guess at the outcome. Once the background send completes, the server's actual answer replaces it — Subscribed for a community anyone can join, or Pending again for one that gates joining behind moderator approval. So a Pending button right after a tap always just means "queued"; a Pending button that's still showing once the send has gone through means the community requires approval.
- **Background send, with retry and rollback.** The change is sent in the background with automatic retry and backoff — it works offline, since the change is queued durably and survives an app relaunch before it sends. If the server permanently rejects it, the community and your subscriptions revert to their pre-tap state, and the shared "Couldn't update subscription" toast appears — the same failure toast used for a failed vote, save, or hide.
- **A server refresh in flight doesn't clobber an in-flight subscribe.** While a subscribe or unsubscribe is queued or sending, a server-driven refresh of that community (reopening its page, a full-account refresh) does not overwrite the optimistic state in either direction: an optimistic subscribe not yet reflected in the account's server-side follow list survives, and an optimistic unsubscribe still present there is not resurrected. The refresh's normal effect on that community resumes once the send's own authoritative answer lands.
- **Sign-in gate.** Subscribing is gated on being signed in. A signed-out attempt fires a warning haptic and shows a "Sign in to subscribe" alert before anything is written; the service also rejects a signed-out subscribe.
- **Toggle against current state.** The action resolves against the current subscribed state — tapping the control subscribes when not subscribed and unsubscribes when subscribed. There is no separate unsubscribe control; it is the same toggle. Toggling back to the original state before the queued change has sent cancels it outright — no network call is made.
- **Tap haptic on submit.** Submitting a subscribe / unsubscribe fires a tap haptic.
- **The Community screen, Search, and Communities tab are instant from the first tap.** These surfaces already know the community's server id, so the durable optimistic write above applies the moment you tap, with no extra step.
- **Discover and instance-browsing resolve the community first, then apply instantly.** These two list directory rows that may not yet be a known server community, so subscribing first resolves the row to a server community id (a brief network lookup — Discover shows a spinner on the row while it resolves; instance-browsing's Join button flips its own row immediately regardless, matching the rest of the app). Once resolved, the same instant, durable write applies as everywhere else. Both surfaces additionally keep their own pre-existing cell-local optimistic touch, redundant with (but no worse than) the database-driven flip above; a permanent failure on either surface rolls back through the same shared outbox mechanism and toast, not a bespoke per-row alert.

## Scenarios

### Subscribe from the community header

- **Given** a Community screen for a community I do not subscribe to, while signed in
- **When** I tap Subscribe in the header
- **Then** the button reads Pending immediately, before any network call
- **And** once the background send completes, the button and subscriber count update to the server's confirmed result (Subscribed, or Pending again if the community requires approval)

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
- **When** I subscribe to (or unsubscribe from) a community whose server id is already known (header, search, or the Communities tab)
- **Then** the local state changes right away
- **And** the change is queued durably and sends automatically once I'm back online, surviving an app relaunch in the meantime

### A permanent subscribe failure rolls back

- **Given** a subscribe or unsubscribe that the server permanently rejects
- **When** the background send exhausts its retries
- **Then** the community and my subscriptions revert to their state from before the tap, and a "Couldn't update subscription" toast appears

### Signed-out subscribe is blocked

- **Given** I am signed out
- **When** I tap Subscribe on a community (header, search row, Discover, or an instance's community list)
- **Then** a warning haptic fires and a "Sign in to subscribe" alert is shown, and nothing is written

### A community needing approval shows Pending

- **Given** a community that requires approval to join
- **When** I subscribe and the background send completes
- **Then** the Community screen header keeps showing Pending — the server's own confirmed answer, not the momentary just-tapped state

## Not supported / out of scope

- No bulk subscribe / unsubscribe outside Discover's per-starter-pack "Subscribe to all" (see [Discover](discover.md)), and no "manage subscriptions" editor; the [Subscriptions sidebar](subscriptions-sidebar.md) lists communities but does not unsubscribe from a row.
- Approving or managing pending follow requests is a server-side action, not handled in the app.
- The durable retry / rollback queue mechanics are shared with vote / save / hide; see [Voting](voting.md), [Saving](saving.md), and [Drafts and Outbox](drafts-and-outbox.md) for the wider outbox story.
