# App Shortcuts, Siri & Spotlight

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Widget](widget.md), [Feeds and sorting](feeds-and-sorting.md), [Search](search.md), [New post](new-post.md), [Inbox](inbox.md), [Saving](saving.md), [Accounts and switching](accounts-and-switching.md), [Subscribe / unsubscribe](subscribe-unsubscribe.md), [NSFW content visibility and blur](nsfw-content.md)

## What it does

Spud exposes its core actions to the system as App Intents, so you can run them
from Siri, the Shortcuts app, the Action button, and Spotlight without opening the
app first. Seven actions ship: Open Feed, Search Lemmy, New Post, Open Inbox,
Open Community, Open Saved, and Switch Account. Your subscribed communities and your
saved / recently-viewed posts are also indexed into Spotlight, so you can find them
by name from the Home Screen and jump straight in. Most actions run against your
current default account; Switch Account changes which account that is.

## Behavior and rules

- **Seven App Intents.** Open Feed (All / Local / Subscribed / Moderator view, with
  an optional sort), Search Lemmy (with a query), New Post, Open Inbox, Open
  Community, Open Saved (the saved-posts feed), and Switch Account (changes the
  default account). Each appears in the Shortcuts app and can be assigned to the
  Action button.
- **Siri phrases.** Each action carries spoken phrases — e.g. "Open Subscribed in
  Spud", "Search Spud", "New post in Spud", "Open my Spud inbox", "Open
  <community> in Spud", "Open Saved in Spud", "Switch Spud account". Running an
  action opens the app on that screen (or applies the switch).
- **Open Community uses your subscriptions.** The community parameter is filled
  from the default account's subscribed communities, so Shortcuts shows a picker and
  Siri can match a community by name. Picking one opens that community.
- **Switch Account picks from your accounts.** The account parameter is filled from
  the accounts you've added; running it makes the chosen account the default.
- **Spotlight indexing (two indexers).** Subscribed communities are indexed via
  `CommunitySpotlightIndexer`, and your saved + recently-viewed (history) posts are
  indexed via `ContentSpotlightIndexer` (domain `"content"`). Both refresh on launch
  and when the app returns to the foreground. A Spotlight hit opens the community or
  post in Spud.
- **The content index excludes NSFW posts, unconditionally.** A saved or
  recently-opened post whose own flag or community's flag is NSFW is never
  written into the content Spotlight index — this holds even when Show NSFW is
  on. Because each reindex deletes the whole `content` domain before re-adding
  the current item set, a post that becomes NSFW after being indexed (or was
  indexed before this exclusion shipped) drops out on the next reindex rather
  than lingering. See [nsfw-content.md](nsfw-content.md) for the equivalent rule
  on the per-post Handoff/Spotlight/Siri continuation activity.
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

- **Given** I subscribe to some communities on my default account
- **When** I run Open Community and pick (or say) one
- **Then** Spud opens that community

### Open the saved feed

- **Given** the Open Saved action
- **When** I run it
- **Then** Spud opens the saved-posts feed

### Switch the active account

- **Given** I have more than one account added
- **When** I run Switch Account and pick one
- **Then** that account becomes the default

### Find a community or saved post in Spotlight

- **Given** my subscribed communities and saved / history posts are indexed
- **When** I search a name in system Spotlight
- **Then** the matching community or post appears and opens in Spud when tapped

### NSFW posts never appear in the content Spotlight index

- **Given** a post is saved or recently opened, and it (or its community) is NSFW
- **When** the content Spotlight index is rebuilt (launch or foreground)
- **Then** that post is not indexed, so it cannot be found via system Spotlight
  search — regardless of the Show NSFW preference

### New post while signed out

- **Given** the default account is signed out
- **When** I run New Post
- **Then** Spud opens and shows the sign-in prompt rather than the composer

## Not supported / out of scope

- **No background work.** Actions open the app (or switch the account); none run a
  task in the background or return results without opening Spud.
- **No post / user *entity* picker.** Communities and accounts are modeled as App
  Intent entities; there is no "open post" or "open user" intent picker (post URLs
  are handled by link handling, and posts reach Spotlight via the content indexer).
- **Spotlight does not index comments.** Communities and saved / history posts are
  indexed; comments are not.
- **Most actions use the default account.** Only Switch Account changes it; the
  other actions don't offer a per-run account picker (they run against the current
  default, like the widget).
- **The Home Screen widget keeps its own configuration intent** — unrelated to these
  app-action intents.
