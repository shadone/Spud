# App Shortcuts, Siri & Spotlight

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Widget](widget.md), [Feeds and sorting](feeds-and-sorting.md), [Search](search.md), [New post](new-post.md), [Inbox](inbox.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md)

## What it does

Spud exposes its core actions to the system as App Intents, so you can run them
from Siri, the Shortcuts app, the Action button, and Spotlight without opening the
app first. Five actions ship: Open Feed, Search Lemmy, New Post, Open Inbox, and
Open Community. Your subscribed communities are also indexed into Spotlight, so you
can search a community by name from the Home Screen and jump straight to it. Every
action runs against your current default account.

## Behavior and rules

- **Five App Intents.** Open Feed (All / Local / Subscribed / Moderator view, with
  an optional sort), Search Lemmy (with a query), New Post, Open Inbox, and Open
  Community. Each appears in the Shortcuts app and can be assigned to the Action
  button.
- **Siri phrases.** Each action carries spoken phrases — e.g. "Open Subscribed in
  Spud", "Search Spud", "New post in Spud", "Open my Spud inbox", "Open
  <community> in Spud". Running an action opens the app on that screen.
- **Open Community uses your subscriptions.** The community parameter is filled
  from the default account's subscribed communities, so Shortcuts shows a picker and
  Siri can match a community by name. Picking one opens that community.
- **Spotlight indexing.** Subscribed communities are indexed into system Spotlight
  (refreshed on launch and when the app returns to the foreground). A Spotlight hit
  opens the community in Spud.
- **Default account, signed-out fallback.** Actions use the current default
  account. While signed out, Open Feed maps Subscribed / Moderator view to All, and
  New Post opens the app and shows the in-app sign-in prompt.
- **Cold launch is handled.** An action invoked while the app is not running queues
  its navigation and replays it once the app's UI is ready, so the action still
  lands on the right screen.

## Scenarios

### Open a feed by voice

- **Given** Spud is installed with App Shortcuts available
- **When** I say "Open Subscribed in Spud" (or run the Open Feed shortcut)
- **Then** Spud opens on the Posts tab showing that feed

### Search from Siri or the Action button

- **Given** the Search Lemmy action
- **When** I run it and provide a query
- **Then** Spud opens the Search tab and runs that query

### Open a subscribed community

- **Given** I follow some communities on my default account
- **When** I run Open Community and pick (or say) one
- **Then** Spud opens that community

### Find a community in Spotlight

- **Given** my subscribed communities are indexed
- **When** I search a community's name in system Spotlight
- **Then** it appears as a result and opens in Spud when tapped

### New post while signed out

- **Given** the default account is signed out
- **When** I run New Post
- **Then** Spud opens and shows the sign-in prompt rather than the composer

## Not supported / out of scope

- **No background work.** Actions open the app; none run a task in the background or
  return results without opening Spud.
- **No post / user entities yet.** Only communities are modeled as an App Intent
  entity; there is no "open post" or "open user" intent (post URLs are handled by
  link handling instead).
- **Spotlight indexes communities only.** Posts, comments, and history are not
  indexed into Spotlight.
- **Account is fixed to the default.** Actions do not offer a per-run account
  picker; they use the current default account, like the widget.
- **The Home Screen widget keeps its own configuration intent** — unrelated to these
  app-action intents.
