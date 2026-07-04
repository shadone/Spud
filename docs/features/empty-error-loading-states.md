# Empty, error, and loading states

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Feed loading and pagination](feed-loading.md), [Search](search.md), [Inbox](inbox.md), [Person / user profile](person-profile.md), [Removed and unavailable posts](removed-unavailable-content.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Across its scenes Spud shows designed states for the moments before, instead of, or against content. An empty scene shows a centered placeholder with a symbol, a title, and a message rather than a blank screen; a scene that is still loading shows an activity indicator; and a failure shows either an error placeholder in place of the content or a one-button alert. These use the system's content-unavailable presentation, so the empty, loading, and error states share a consistent look across the feed, Search, Inbox, direct-message threads, and profiles.

## Behavior and rules

- **System content-unavailable presentation.** Empty and inline-error states are built on the system `UIContentUnavailableConfiguration` (a SwiftUI `ContentUnavailableView` on the one SwiftUI screen, the blocked-users list). Each state supplies a symbol, a title, and a secondary message; styling — typography, secondary-label color, centered layout — comes from the system, so the states match across scenes without a bespoke component.
- **Empty states are scene-specific in copy.** The feed shows "No posts" (or "No saved posts yet" on the saved feed); Search shows a "Search posts, communities, and people" prompt before you type and a no-results state quoting your query; Inbox shows a per-scope empty for replies, mentions, and messages; a direct-message thread and a profile each have their own empty copy. The mechanism is shared; the words are not.
- **Empty states do not flash during loading.** An empty placeholder is shown only once a first result has arrived and the scene is genuinely empty with nothing in flight, so it never appears briefly before content loads. (For the feed, see [Feed loading and pagination](feed-loading.md).)
- **Loading indicators.** While a list pages, a footer row with an activity indicator appears beneath the content and is removed when the page arrives (the feed footer spinner, documented in [Feed loading and pagination](feed-loading.md)). Scenes that route to a screen while its content loads — post detail, a person profile, a community — show a full-screen activity indicator until the content is ready, then swap in the loaded screen. Individual scenes (composer, account, registration) show inline spinners for in-flight work.
- **Feed error states with retry.** When the feed's initial load fails, it renders a designed inline error state classified as **Offline**, **Unreachable**, or **Malformed** (documented in [Feed loading and pagination](feed-loading.md)). Each state shows a symbol, title, and message, with one or two action buttons for retry, working offline, or copying diagnostics. The state persists until the user retries or connectivity returns (triggering automatic retry).
- **Errors as inline state or as an alert in other scenes.** Search and Inbox render a designed inline error state — a warning-triangle symbol with a short "couldn't load" message — in place of the missing content. Write actions and many fetch failures instead present a single-OK-button alert with a human-readable message, kept consistent through a shared error-alert helper so call sites report failures the same way.
- **Sign-in states.** Where a scene needs an account — the Inbox — a signed-out placeholder ("Sign in to use your inbox") stands in for the content rather than an empty list.

## Scenarios

### An empty list shows a designed placeholder

- **Given** a scene whose results are empty (an empty feed, no search results, or an empty inbox scope)
- **When** the scene settles with nothing in flight
- **Then** a centered symbol, title, and message are shown in place of the list

### The empty placeholder does not flash before content

- **Given** a scene that is still loading its first results
- **When** the load is in flight
- **Then** no empty placeholder is shown until the load finishes and the scene is genuinely empty

### A screen shows a spinner while it loads

- **Given** I open a post, a profile, or a community that has not loaded yet
- **When** the screen appears
- **Then** a full-screen activity indicator is shown until the content is ready
- **And** the loaded screen replaces it

### The feed shows a designed error state with retry on initial load failure

- **Surfaces:** `iphone`, `ipad`
- **Given** I open a feed that encounters an offline, unreachable, or malformed response on its first load
- **When** the failure is reported
- **Then** the list shows an inline Offline / Unreachable / Malformed state with a symbol, title, and message
- **And** action buttons offer to retry, work offline, or copy diagnostics
- **And** if the failure was offline, the feed retries automatically once connectivity returns

### Search and Inbox show an inline error state

- **Surfaces:** `iphone`, `ipad`
- **Given** a failed load in Search or Inbox
- **When** the failure is reported
- **Then** a warning-triangle symbol with a short "couldn't load" message is shown in place of the content

### A write failure shows an alert

- **Given** an action like voting, replying, or posting that fails
- **When** the failure is reported
- **Then** a single-OK-button alert with a human-readable message is presented

### The signed-out inbox shows a sign-in prompt

- **Given** I am browsing signed out
- **When** I open the Inbox
- **Then** a "Sign in to use your inbox" placeholder is shown instead of an empty list

## Not supported / out of scope

- **No custom empty-state component.** The states are the system content-unavailable presentation configured per scene, not a bespoke Spud view; there is no shared empty-state class to theme. They are not wired to the app's design tokens beyond the symbols passed in.
- **No retry button on empty states or Search/Inbox errors.** Empty placeholders and Search/Inbox inline-error states carry a symbol, title, and message but no action button; recovery is by retrying the action (for example pull-to-refresh where a scene offers it), not by tapping the placeholder. (The feed error state is an exception — it does include retry, work offline, and copy-diagnostics buttons.)
- **Errors are not silently swallowed but are not always inline.** Many fetch failures log and surface as an alert rather than an inline error state; the feed renders a designed inline error with buttons, while Search and Inbox render simpler inline errors without buttons. Posts that are no longer found on the server (`couldnt_find_post`) are handled separately — see [Removed and unavailable posts](removed-unavailable-content.md).
