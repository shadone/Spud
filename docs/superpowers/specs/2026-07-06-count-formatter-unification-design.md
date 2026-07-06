# Count-formatter unification — design

Date: 2026-07-06
Status: Approved — ready for implementation plan
Scope: app (`Spud`), `SpudDataKit`, `SpudUtilKit`, `SpudWidgetExtension`. Display-string formatting only.

Supersedes §8 ("Count-formatter style unification") of
`docs/superpowers/specs/2026-07-05-follow-ups.md`, and widens it: the audit
named 4 formatters; a full sweep found **7** display formatters (it missed
`UpvotesFormatter` — duplicated across the app AND the widget — and
`DiscoverView.compact`).

## Problem

Seven divergent implementations format the same idea (a compact count) in
inconsistent styles:

| Formatter | Home | Style |
|---|---|---|
| `CompactCount` | app `Spud/Utils/Formatters/` | `312` / `1.2K` / `32K` / `1.2M` (K+M, decimal trimmed) |
| `CommentsFormatter` | `SpudDataKit/Utils/Formatters/` (public) | K-only, always 1 decimal (`1.2K`, `32.0K`, `1000.0K`) |
| `UpvotesFormatter` (app copy) | app `Spud/Utils/Formatters/` | byte-identical to `CommentsFormatter` |
| `UpvotesFormatter` (widget copy) | `SpudWidget/` | byte-identical duplicate |
| `SummaryHeatmapCardView.formatCount` | app (inline, private) | K+M, always 1 decimal |
| `DiscoverView.compact` | app (inline, static) | `%.0fK` (no decimal) / `%.1fM` |
| `.number.notation(.compactName)` ×2 | app (`SearchResults`, `SiteListSiteViewModel`) | locale-aware (varies by device locale) |

The same subscriber/comment/vote/member count renders differently depending on
which screen shows it (`32.0K` vs `32K` vs `32,0 K`), and `UpvotesFormatter`
exists as two identical copies because the widget could not reach the app's.

## Goal

One `public enum CountFormatter` in **SpudUtilKit** (the lowest, pure-Foundation
layer, reachable by every target), rendering the **CompactCount style**:

- Values `< 1000` (and all negatives): verbatim (`312`, `0`, `-5`, `-5000`).
- `1000 ..< 1_000_000`: divide by 1000, suffix `K`.
- `>= 1_000_000`: divide by 1_000_000, suffix `M`.
- Decimal is dropped when the abbreviated value is a whole number **or** `>= 100`
  (so `5K`, `32K`, `312K`, `1M`; but `1.2K`, `1.2M`). One decimal otherwise.

This is `CompactCount`'s existing algorithm, moved verbatim — chosen (over
`CommentsFormatter`'s K-only style and the locale-aware `.compactName`) for being
the most polished and deterministic (locale-independent, snapshot-stable).

### The formatter

`SpudUtilKit/.../Formatters/CountFormatter.swift`:

```swift
public enum CountFormatter {
    /// Compact count for display: "312", "1.2K", "32K", "1.2M". Drops the
    /// decimal for whole values or when the abbreviated value is >= 100.
    /// Values below 1000 and all negatives render verbatim.
    public static func string(_ value: Int64) -> String {
        let n = Double(value)
        switch value {
        case 1_000_000...: return trim(n / 1_000_000) + "M"
        case 1000...: return trim(n / 1000) + "K"
        default: return "\(value)"
        }
    }

    private static func trim(_ value: Double) -> String {
        if value >= 100 || value == value.rounded() {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}
```

`Int` callers pass `Int64(x)`.

## Layer wiring

- `SpudUtilKit` is imported by `Spud`, `SpudDataKit`, and `SpudUIKit` already, so
  the app and `SummaryObservations` (SpudDataKit) reach `CountFormatter` directly.
- The **`SpudWidgetExtension` target does not depend on `SpudUtilKit`** (it imports
  only `SpudDataKit` + `SpudUIKit`). Add `- target: SpudUtilKit` to that target's
  `dependencies` in `project.yml`, add `import SpudUtilKit` to the widget files
  that format counts, and run `make project` (XcodeGen regenerates the gitignored
  `.xcodeproj`). This is the move that lets the widget's duplicate
  `UpvotesFormatter` be deleted.

## Retire & migrate

Every call site below switches to `CountFormatter.string(_:)`; the listed
formatter files/inline functions are deleted.

1. **`CompactCount`** (app) — sites: `InstanceHealthStyle`, `OnboardingHomeBaseViewController`. Delete the file. *(No output change — identical style.)*
2. **`CommentsFormatter`** (SpudDataKit, `public`) — sites: `PersonViewModel` (posts, comments), `CommunityViewModel` (subscribers, posts, usersActiveWeek/Month), `IconValueFormatter` (comments), `SummaryObservations` (posts, comments, saved, votes, communities, read), `SpudWidget` `PostView`/`PostViewSmall`/`PostAccessoryRectangularView` (comments). Delete the file.
3. **`UpvotesFormatter`** — BOTH copies (`Spud/Utils/Formatters/` + `SpudWidget/`). Sites: `PostDetailCommentViewModel` (score), `IconValueFormatter` (votes/score), `SpudWidget` `PostView`/`PostViewSmall`/`PostAccessoryInlineView`/`PostAccessoryRectangularView` (score). Delete both files.
4. **`SummaryHeatmapCardView.formatCount`** (inline `private func`, takes `Int`) — replace the one call with `CountFormatter.string(Int64(total))`; delete the function.
5. **`DiscoverView.compact`** (inline `static func(Int64)`) — replace its call site(s) with `CountFormatter.string(_:)`; delete the function.
6. **`.compactName`** — `SearchResults.membersText` (`usersTotal.formatted(.number.notation(.compactName))` → `CountFormatter.string(Int64(usersTotal))`), `SiteListSiteViewModel.abbreviatedCount(_ value: Int64)` (replace body with `CountFormatter.string(value)`; keep or inline the wrapper as the implementer sees fit).

**Keep unchanged:** `InstanceHealthStyle`'s `—` empty-value wrapper — it renders
`—` for the empty case and otherwise wraps the formatter; only the inner
formatter call changes. Its `—` semantics are a non-goal.

## Behavioral impact & snapshots

Because most call sites currently render K-only-one-decimal (`CommentsFormatter`,
`UpvotesFormatter`) or their own near-variants, the **rendered output changes**
for values that abbreviate differently under the new trimmed K+M style:

- whole thousands: `5.0K` → `5K`
- `>= 100_000`: `312.0K` → `312K`
- `>= 1_000_000`: `1000.0K` → `1.2M`
- `DiscoverView`: `1K` (no decimal) → `1.2K`
- `.compactName` sites: locale output → fixed `1.2K`

Small / non-round counts below 100K (e.g. `1234 → "1.2K"`) are **byte-identical**
across old and new, so most post-list / comment-cell snapshots do not move.

**Snapshot re-record approach** (mirrors the 2026-07-06 compact-markdown task):
after the migration compiles, run the affected snapshot suites in **verify**
mode; for each failing reference, confirm the diff is the formatter change (a
`git stash`-control run of the migration commit if a failure looks unrelated to
distinguish it from pre-existing annex/runtime drift), then re-record **only**
those references, one class at a time, on the reference sim (iPhone 17 Pro /
iOS 26.3.x). Candidate suites: PostList cells, PostDetail (comment score),
Community, Person, Activity (Summary + Heatmap), Discover, Search results,
SiteList / InstanceDetail, and any widget snapshots. `git add` only the explicit
refs that changed.

## Testing

- New `SpudUtilKitTests` suite (Swift Testing — `struct`, `@Test`, `#expect`;
  `import Foundation` for the type) locking `CountFormatter.string(_:)` at the
  boundaries: `999→"999"`, `1000→"1K"`, `1234→"1.2K"`, `5000→"5K"`,
  `32000→"32K"`, `100_000→"100K"`, `312_000→"312K"`, `1_000_000→"1M"`,
  `1_250_000→"1.2M"`, `0→"0"`, `-5→"-5"`, `-5000→"-5000"`.
- Any existing tests of the retired formatters (`CompactCount`,
  `CommentsFormatter`, `UpvotesFormatter`, …) are migrated to `CountFormatter` or
  deleted so no test references a deleted symbol.
- Build the app **and** the widget scheme (`SpudWidgetExtension`) — the widget's
  new `SpudUtilKit` import + dependency must compile.

## Non-goals

- No change to `InstanceHealthStyle`'s `—` empty-value wrapper.
- No change to timing/timestamp math that matched the `/ 1000` sweep but is not a
  count (`ExplorerDTO` ms→s timestamp, `RequestRetry` attoseconds).
- No locale-aware / user-configurable formatting (the fixed style is deliberate).
- No change to which counts are shown or where — only how they are formatted.

## Documentation

Count formatting is an internal helper, not a user-facing capability with its own
`docs/features/` page, so no feature-doc change is required. If any feature doc
quotes a specific formatted count string that this change alters, reconcile it;
otherwise no docs update.
