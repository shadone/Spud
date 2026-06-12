# Search

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Subscribe / unsubscribe](subscribe-unsubscribe.md), [Community screen](community-screen.md), [Person / user profile](person-profile.md), [Post detail and comments](post-detail-and-comments.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Search the connected instance for posts, communities, users, or comments. A scope control in the search bar picks which kind you are looking for, and typing runs a debounced query that returns one list at a time. Results render as feed-style rows: a post row, a community row with an inline Subscribe button, a user row, or a comment-with-context row. Tapping a result opens the corresponding screen — Post detail, the Community screen, or the Person profile. Search is its own tab, reachable on both iPhone and iPad.

## Behavior and rules

- **Four scopes.** The search bar's scope buttons are Posts, Communities, Users, and Comments. The active scope decides both which Lemmy search type is requested and which result list is shown.
- **Debounced typing.** Each keystroke schedules the search after a short debounce (about 300 ms); a new keystroke cancels the pending one, so fast typing only ever keeps one request alive. Tapping Search on the keyboard, or changing scope, runs the active query immediately with no debounce.
- **One request at a time.** Every new query or scope change cancels the previous in-flight request before starting the next, so a stale response can never overwrite a newer one.
- **Empty query resets.** Clearing the field (or entering only whitespace) returns the screen to its initial prompt and discards any results.
- **Single page of results.** A search returns one page (up to roughly 30 results) sorted by top-of-all-time across the All listing. There is no pagination or infinite scroll on search results.
- **Designed states.** The screen shows an initial prompt before any query, a spinner while a query is in flight, a no-results state that quotes the term that returned nothing, and an error state if the request fails.
- **Inline subscribe from community results.** A community result row carries a Subscribe / Subscribed button. Tapping it subscribes or unsubscribes in place without leaving search (see Scenarios and [Subscribe / unsubscribe](subscribe-unsubscribe.md)).
- **Tapping a result navigates.** A post or comment result opens the post in Post detail; a community result opens the [Community screen](community-screen.md); a user result opens the [Person profile](person-profile.md).
- **Keyboard dismisses on scroll.** Dragging the results list dismisses the keyboard.

## Scenarios

### Search for posts

- **Given** the Search tab with the Posts scope selected
- **When** I type a query and pause
- **Then** after a short debounce the query runs and matching post rows appear
- **And** each row shows the title with a community / score / comment-count subtitle and an optional thumbnail

### Switch scope re-runs the query

- **Given** a query that has returned post results
- **When** I tap the Communities scope
- **Then** the same query runs immediately against communities and the community rows replace the post rows

### Subscribe to a community from a result

- **Given** a community result row showing Subscribe while I am signed in
- **When** I tap Subscribe on that row
- **Then** the button immediately reads Subscribed and the subscription is sent to the server
- **And** if the call fails the button reverts to Subscribe and an error alert is shown

### Signed-out subscribe is gated

- **Given** I am browsing search signed out
- **When** I tap Subscribe on a community result
- **Then** a "Sign in to subscribe" alert is shown and no call is made

### Tapping a result opens its screen

- **Given** any result row
- **When** I tap it
- **Then** a post or comment opens the post in Post detail, a community opens the Community screen, and a user opens the Person profile

### No results quotes the term

- **Given** a query that matches nothing for the active scope
- **When** the response arrives empty
- **Then** a no-results state is shown quoting the searched term

### A failed search shows an error state

- **Given** the search request fails
- **When** the error returns
- **Then** an error state with a retry message is shown and an alert is surfaced

## Not supported / out of scope

- No pagination on results — search returns a single page; there is no infinite scroll or "load more".
- The result sort and listing type are fixed (top-of-all-time, All); there is no in-screen sort or listing picker for search.
- Only community results expose an inline subscribe action; post, user, and comment rows do not.
- No search history, suggestions, or recent-search list.
