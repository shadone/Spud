# Subscribe / unsubscribe

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Community screen](community-screen.md), [Search](search.md), [Subscriptions sidebar](subscriptions-sidebar.md), [Voting](voting.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Subscribe to a community to follow it, or unsubscribe to stop. The same toggle is reachable from the [Community screen](community-screen.md) header and context menu and from a community row in [Search](search.md) results. A change is sent to the server, which then mirrors the confirmed community state back into the local database — so the subscriber count and your subscribed badge reflect what the server recorded. Subscribing requires being signed in.

## Behavior and rules

- **One service call, confirm-then-mirror.** Subscribing or unsubscribing calls the Lemmy follow endpoint first, then writes only the server's returned community view back into the local database. The persisted subscribed state and counts you see are the server's confirmed result, not a local guess.
- **Sign-in gate.** Subscribing is gated on being signed in. A signed-out attempt fires a warning haptic and shows a "Sign in to subscribe" alert before any call is made; the service also rejects a signed-out subscribe.
- **Toggle against current state.** The action resolves against the current subscribed state — tapping the control subscribes when not subscribed and unsubscribes when subscribed. There is no separate unsubscribe control; it is the same toggle.
- **Tap haptic on submit.** Submitting a subscribe / unsubscribe fires a tap haptic.
- **Failures surface an alert.** If the call fails, an error alert is shown.
- **Community screen reflects the mirror.** On the Community screen the header button is driven by the observed database state, so it flips to Subscribed / Subscribe (or shows Pending for a follow that needs approval) once the server's result is mirrored back — there is no optimistic flip before confirmation.
- **Search row flips optimistically.** A community row in search results flips its button to the new state the moment you tap it, then sends the call; on failure it reverts and shows an alert. This is the one place the toggle updates before the server confirms.
- **Discover's inline subscribe is optimistic.** Tapping Subscribe on a community in Discover flips the button immediately, in contrast to the confirm-then-mirror flow used on the community screen.
- **Pending state.** A community that requires approval to join can come back from the server as Pending; the Community screen header surfaces that as a distinct Pending button state.

## Scenarios

### Subscribe from the community header

- **Given** a Community screen for a community I do not subscribe to, while signed in
- **When** I tap Subscribe in the header
- **Then** the subscribe is sent to the server and, once its result is mirrored back, the button reads Subscribed and the subscriber count updates

### Unsubscribe from the community header

- **Given** a Community screen for a community I subscribe to
- **When** I tap the Subscribed button (or choose Unsubscribe from the header context menu)
- **Then** the unsubscribe is sent and the button returns to Subscribe once the server confirms

### Subscribe from a search result

- **Given** a community row in search results showing Subscribe, while signed in
- **When** I tap Subscribe
- **Then** the button immediately reads Subscribed and the call is sent
- **And** if it fails the button reverts to Subscribe and an error alert is shown

### Signed-out subscribe is blocked

- **Given** I am signed out
- **When** I tap Subscribe on a community (header or search row)
- **Then** a warning haptic fires and a "Sign in to subscribe" alert is shown, and no call is made

### A failed subscribe shows an alert

- **Given** the follow call fails (for example a network error)
- **When** I subscribe
- **Then** an error alert is shown

### A community needing approval shows Pending

- **Given** a community that requires approval to join
- **When** I subscribe and the server returns a pending follow
- **Then** the Community screen header shows a Pending state

## Not supported / out of scope

- The Community screen header does not flip optimistically — it updates only after the server's mirror lands. (The search row is the exception and flips immediately.)
- No bulk subscribe / unsubscribe, and no "manage subscriptions" editor; the [Subscriptions sidebar](subscriptions-sidebar.md) lists communities but does not unsubscribe from a row.
- Approving or managing pending follow requests is a server-side action, not handled in the app.
