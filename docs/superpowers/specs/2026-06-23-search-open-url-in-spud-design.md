# Search: open a pasted Lemmy URL in Spud

Date: 2026-06-23

## Overview

When the Search field contains a full Lemmy URL (to a post, comment, community,
user, or instance), Spud surfaces an "Open in Spud" row at the top of the search
results. Tapping it navigates to that object using the app's existing internal
routing (including federated resolution for objects on instances the user isn't
signed in to). Searching the literal URL text is meaningless, so when a URL is
detected the normal text-search network call is skipped.

This builds on the existing link-handling stack (`LemmyURLParser`,
`URL.SpudInternalLink`, `AppCoordinator.open(_:in:)`, `resolveObject`); see
`2026-06-17-open-in-spud-link-handling-design.md`.

## Goals

- Detect a pasted/typed Lemmy URL in the search field and offer to open it.
- Cover posts, comments, communities, users, and instances.
- Work for objects on instances not in Spud's Explorer directory (federated),
  not just known instances.
- Reuse existing navigation/resolution; add no new routing.

## Non-goals

- No paste-event interception — detection is content-based (fires on typing a
  URL too).
- No new resolve-time UI beyond what tapping an existing internal link already
  shows (loading/error handling is whatever `AppCoordinator.open` already does).
- No change to `LemmyURLParser.classify`'s contract (it is also used by
  PostDetail link tapping, where the known-instance gate must stay).

## Detection — `SearchURLDetector`

A new pure type (`Spud/Scenes/Search/SearchURLDetector.swift`):

```swift
struct SearchURLSuggestion {
    enum Kind { case post, comment, community, user, instance }
    let kind: Kind
    let link: URL.SpudInternalLink   // ready to encode + open
    let displayURL: String           // shown in the row (host + path)
}

enum SearchURLDetector {
    static func detect(query: String, isKnownInstance: (String) -> Bool) -> SearchURLSuggestion?
}
```

Logic:

1. Trim the query. Parse as a URL; require an `http`/`https` scheme and a host.
   Otherwise return `nil`.
2. Try `LemmyURLParser.classify(url:isKnownInstance:)`. If it returns a
   `SpudInternalLink`, map it to a `Kind` (`.instance` → instance,
   `.post`/`.community`/`.person` → matching kind, `.objectAtURL` → infer from
   path) and return the suggestion. This covers known instances and mentions.
3. Fallback for unknown hosts: if the path is Lemmy-shaped — `/post/<numeric>`,
   `/comment/<numeric>`, `/c/<name>`(optionally `@instance`), `/u/<name>` —
   build `.objectAtURL(url:)` (or `.community(name:instance:)` for `/c`) and the
   `Kind` from the path segment. Return the suggestion.
4. Bare host with no path on an unknown instance, or any non-Lemmy shape →
   `nil` (we cannot tell a bare domain is Lemmy unless it's known).

No network call: the kind comes from the path/classification. Federated
resolution happens later, on tap.

## View model — `SearchViewModel`

- Add `private(set) var urlSuggestion: SearchURLSuggestion?` (observable).
- In `queryChanged(_:)`, set `urlSuggestion = SearchURLDetector.detect(query:,
  isKnownInstance:)` synchronously (no debounce — the row should appear
  instantly). `isKnownInstance` uses the same Explorer lookup the rest of the
  app uses (`appDatabase.explorerInstanceSync(baseurl:)`), called off-main if
  needed, matching how `classify` is gated elsewhere.
- When `urlSuggestion != nil`, skip scheduling the text search
  (`scheduleSearch`) — there is nothing useful to search for. Editing the query
  back to a non-URL clears `urlSuggestion` and resumes normal search.

## UI — `SearchViewController`

- Add a new top section to the diffable data source (e.g. `Section.openURL`)
  containing a single row when `urlSuggestion != nil`, ordered above the
  post/community/user/comment sections.
- New cell `SearchOpenURLCell`: leading `↗`/SF Symbol, primary label
  "Open {kind} in Spud" (kind localized: Post / Comment / Community / User /
  Instance), secondary label = `displayURL`, disclosure chevron.
- Bind the section to `viewModel.urlSuggestion` via the existing observation
  stream the screen already uses.

## Navigation on tap

In `tableView(_:didSelectRowAt:)`, for the open-URL row:

- Encode `suggestion.link` (`URL.SpudInternalLink`) to the
  `info.ddenis.spud://internal/...` URL and call
  `AppCoordinator.open(_:in: window)`.
- That routes known post/community/user directly; `.objectAtURL` flows through
  `resolveAndDisplay` → `lemmyService.resolveObject(query:)` (federated),
  opening the parent post for `/comment` URLs.
- No new navigation code; reuses the coordinator end to end.

## Edge cases

- Plain text query → `nil`, normal search.
- `mailto:`/`spud-markdown:`/non-http scheme → `nil`.
- Trailing slash / query string / fragment on a Lemmy path → still detected
  (path-segment match ignores trailing `?`/`#`).
- Non-Lemmy URL with a coincidental `/post/123` path on an unknown host → row is
  offered by design; tapping resolves via `resolveObject` and fails gracefully
  with the existing error handling.

## Testing

- Swift Testing unit tests for `SearchURLDetector.detect`:
  - known-instance post / comment / community / user / bare instance
  - unknown-host `/post/123`, `/comment/123`, `/c/name`, `/c/name@inst`,
    `/u/name`
  - bare unknown host → nil; plain text → nil; non-http scheme → nil
  - kind mapping correctness
- One snapshot test of `SearchViewController` showing the "Open in Spud" row for
  a representative URL (inject a view model with a fixed `urlSuggestion`).

## Files

- New: `Spud/Scenes/Search/SearchURLDetector.swift`,
  `Spud/Scenes/Search/Cells/SearchOpenURLCell.swift`, detector unit-test file,
  snapshot test.
- Edit: `SearchViewModel.swift` (urlSuggestion + skip-search),
  `SearchViewController.swift` (section + cell + tap routing).
- `make project` after adding files (XcodeGen).
