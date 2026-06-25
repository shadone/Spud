# Design: Blur NSFW content + coherent NSFW handling

- **Date:** 2026-06-25
- **Status:** approved (brainstorming), pending implementation plan
- **Targets touched:** `Spud`, `SpudDataKit`, `SpudUIKit` (badge), tests, docs
- **Migration:** `v20_postNsfw` (next free number; `v19_favoritedCommunity` is taken)
- **No cross-repo change:** pinned LemmyKit 0.5.0 already exposes `saveUserSettings(blurNSFW:)` and `local_user.blur_nsfw`.

## Summary

Spud currently treats NSFW as binary **show/hide**, enforced server-side via the `show_nsfw`
request parameter on feed fetches (see `docs/features/nsfw-content.md`). There is no blur, and
the client never even records whether a post is NSFW. This feature adds a second, independent
axis — **blur** — and makes NSFW handling coherent across the app:

1. A new `blurNsfw` preference (default **on**), surfaced in **app settings** and the **Quick
   Switch** post-list config popover, mirroring the existing `show_nsfw` local-preference +
   server-sync pattern.
2. Actual blur-with-tap-to-reveal rendering of NSFW media on **post thumbnails**, the
   **post-detail header image**, and **community icons/banners**.
3. Discovery gating extended so NSFW communities (and NSFW posts) don't leak through the
   **global Search scene** or the **composer community picker** when `show_nsfw` is off — the
   gap that exists today (Discover already gates; those two surfaces don't).
4. A shared **NSFW badge**, a **disabled Blur toggle when Show is off**, and a one-time
   **age acknowledgment** the first time the user enables Show NSFW.

## Semantics: two independent axes

| Axis | Setting | Question it answers | Enforcement |
|---|---|---|---|
| Visibility | `show_nsfw` (existing) | Does NSFW appear at all? | Server-side feed filter; client-side discovery gating |
| Obscuring | `blur_nsfw` (new) | When NSFW is shown, is its media obscured until tapped? | Client-side render overlay |

- **Blur only has a visible effect when NSFW is shown.** If `show_nsfw` is off, NSFW never
  reaches a feed, so blur is a no-op. This is why the Blur toggle is **disabled when Show is
  off** (see UI section).
- **Default: blur ON.** Matches Lemmy's `blur_nsfw` default and the safe-by-default posture
  Apple's UGC guidelines (1.1.4 / 1.2) expect of a shipping app.
- **Gate discovery, not access.** NSFW communities are hidden from surfaces that *suggest*
  content (Search, pickers, Discover) when `show_nsfw` is off, but stay reachable by **deep
  link** and when **already subscribed**. Within a reachable NSFW community, content respects
  the blur setting.

## 1. Data layer — record that a post is NSFW

The client cannot blur what it doesn't know is NSFW, and `PostRecord` has no NSFW flag today
(NSFW was purely server-filtered).

- **Migration `v20_postNsfw`** (`AppDatabase+Migrations.swift`): add
  `isNsfw BOOLEAN NOT NULL DEFAULT 0` to the `post` table. Additive, no backfill needed
  (existing rows default to non-NSFW; a normal feed refresh re-imports the real value).
- **`PostRecord.isNsfw: Bool = false`** (`Records/Post.swift`) — new stored column, added to
  the struct, initializer, and persistence.
- **Importer** (`PostImporter` / `upsertPost` → `apply(view:)`): set
  `record.isNsfw = view.post.nsfw`. This is the single full-`PostView` import path that already
  refreshes post counters, so it covers feed `getPosts`, `getPost`, votes, and cross-posts.
- **`CommunityRecord.isNsfw` already exists** (`Records/Community.swift:24`, set by
  `CommunityImporter` from `model.nsfw`) — no community migration required.
- **`PostListRow`** (`PostListObservations.swift`): add `isNsfw: Bool`, computed in the SELECT
  as **`post.isNsfw OR community.isNsfw`** (the row already joins `community`). Posts in an
  NSFW community blur even if the individual post flag is unset.
- **Post detail** reads `PostRecord.isNsfw` (OR its community's `isNsfw`) directly.

## 2. Preference + server sync (clone of `show_nsfw`)

The existing `show_nsfw` sync is one-directional: the local `@UserDefaultsBacked` preference is
the source of truth, pushed to the server on the **frontpage feed only**; `AccountRecord.showNsfw`
is a cache that is written but never read back. Blur mirrors this exactly.

- **`PreferencesService.blurNsfw: Bool = true`** (`@UserDefaultsBacked key "blurNsfw"`) plus
  `blurNsfwStream: AsyncStream<Bool>` (`Services/Preferences/PreferencesService.swift`).
- **`AccountRecord.blurNsfw: Bool?`** cache field (`Records/Account.swift`); `AccountImporter`
  maps `local_user_view.local_user.blur_nsfw` onto it; add
  `setAccountBlurNsfw(_:forKeychainId:)` (sibling of `setAccountShowNsfw`).
- **`LemmyService.setBlurNsfw(_:)`** — clone of `setShowNsfw`: skip when signed out, call
  `api.saveUserSettings(blurNSFW:)`, then mirror to `AccountRecord`. Wrap errors in
  `LemmyServiceError`.

## 3. Rendering — blur overlay + tap-to-reveal (net-new)

**Chosen approach: a `UIVisualEffectView` overlay**, not Core Image processing. Rejected
alternative: baking a Gaussian blur into the `UIImage` (higher CPU, re-runs on cell reuse,
awkward reveal toggle). The overlay is GPU-cheap and revealing just hides it.

- **New component `NsfwBlurOverlayView`** (UIKit): a blur-material `UIVisualEffectView` sized
  over the host image view, with a centered `eye.slash` glyph + "Tap to reveal" label and a tap
  gesture. Exposes `isRevealed` and an `onReveal` callback. Accessibility: the overlay is an
  element with label "NSFW content, hidden" and a custom action "Reveal". Respects Reduce
  Transparency (fall back to an opaque fill) — no motion involved.
  Placement: `Spud/Scenes/Shared/` (app target; consumed by cells and the post-detail header).
- **Per-post reveal state is session-only.** The PostList data source holds a
  `Set<PostListRow.ID>` of revealed posts; the post-detail VC holds a single `Bool`. Tapping
  inserts the id / sets the bool and unblurs that one item. **Not persisted** — resets on
  relaunch.
- **`PostListPostCell`**: overlay the thumbnail when `blurNsfw && row.isNsfw && !revealed`.
  Configure reveal state at cell-config time (reused cells must re-read the set). Tapping the
  overlay does **not** open the post — it reveals; a second tap (or tapping the cell body)
  opens as normal.
- **`PostDetailHeaderCell`**: same overlay over the lead/header image.
- **Community art**: same overlay over NSFW community **icons/banners** in lists and on the
  community header (`community-screen`) when shown. Reuse `NsfwBlurOverlayView`. (Community art
  reveal can follow the post-list session-set pattern, keyed by community id; acceptable to keep
  community art always-blurred-when-NSFW in v1 if reveal-per-community proves fiddly — see Open
  questions.)
- **Toggling Blur is a pure re-render, not a refetch.** Unlike show/hide (which re-fetches
  because the server filters), flipping `blurNsfw` only re-applies the overlay to visible items.
  The frontpage observer also pushes `setBlurNsfw` to the server (frontpage-only, like
  `show_nsfw`, to avoid duplicate writes from multiple post lists).

## 4. Discovery gating — close the Search / picker gap

- **Already gated (no change):** Discover directory + its "search the network" fallback filter
  NSFW communities when `show_nsfw` is off and badge them when on
  (`DiscoverViewModel.swift:411,441`).
- **Global Search scene** (`Spud/Scenes/Search/`) has **no NSFW handling today** — NSFW posts
  and communities appear regardless of `show_nsfw`. Lemmy's search API has no server NSFW
  filter, so add a **client-side filter** in `SearchViewModel`: when `show_nsfw` is off, drop
  result rows whose community/post is NSFW (mirroring Discover). Observe `showNsfwStream` so an
  open Search re-filters live. NSFW results that *do* show (Show on) respect blur.
- **Composer community picker** (`CommunityPickerViewController`, reuses `LemmyService.search`
  with `.Communities`): apply the same client-side drop when `show_nsfw` is off. Deep-link /
  already-subscribed access is unaffected (those paths don't go through search).

## 5. Shared NSFW badge

Promote Discover's inline `nsfwBadge` (`DiscoverView.swift:400`) into a single reusable badge
(SwiftUI view in `SpudUIKit`, or a shared style if the consumers are UIKit) and use it
consistently on the **post cell**, **post detail header**, and **community header**, in addition
to Discover. One red "NSFW" pill, one definition.

## 6. Settings surfaces (both, as requested)

- **App settings** — `PreferencesPostMarkingAndHidingView`, NSFW section: add a **"Blur NSFW
  Content"** toggle under the existing "Show NSFW Content" row, with an explanatory footer.
  `PreferencesViewModel` gains `blurNsfw`, `updateBlurNsfw`, and `blurNsfwStream` observation
  (clone the `showNsfw` members).
- **Quick Switch popover** (the post-list config filter) — add a **"Blur NSFW"** toggle.
  `QuickSwitchViewModel` gains `blurNsfw` + `updateBlurNsfw`.
- **Disable Blur when Show is off.** In both surfaces, the Blur toggle is disabled (greyed) with
  a short footnote ("Only applies when NSFW content is shown") whenever `show_nsfw` is off, since
  blur is a no-op then.

## 7. Age acknowledgment on enabling Show NSFW

- **`PreferencesService.hasAcknowledgedNsfwAge: Bool = false`** (`@UserDefaultsBacked`).
- The first time the user attempts to turn **Show NSFW on** (from either settings or Quick
  Switch) and the flag is false, present a confirmation alert ("Show adult content? By
  continuing you confirm you are of legal age to view adult material.") with **Cancel** /
  **Show NSFW**. On confirm: set the flag and enable. On cancel: revert the toggle (leave
  `show_nsfw` off). Subsequent toggles skip the alert. Turning Show NSFW *off* never prompts.
- Logic lives at the view layer (both `PreferencesPostMarkingAndHidingView` and `QuickSwitchView`
  present the alert); shared copy via a localized string. This is a one-time gate, not a
  recurring nag.

## 8. Widget

Unchanged. The Home Screen widget always hides NSFW (no access to the in-app preference), so
blur never applies there.

## 9. Tests

- **SpudDataKitTests:** `v20` adds the `post.isNsfw` column; `PostImporter` maps
  `view.post.nsfw`; `PostListRow.isNsfw == post.isNsfw || community.isNsfw`; `setBlurNsfw` calls
  `saveUserSettings(blurNSFW:)` and mirrors `AccountRecord.blurNsfw` (fake api); signed-out
  `setBlurNsfw` is a no-op.
- **View-model unit tests:** `PreferencesViewModel.updateBlurNsfw` and
  `QuickSwitchViewModel.updateBlurNsfw` write the preference; Search/picker NSFW filtering drops
  NSFW rows when `show_nsfw` is off.
- **Snapshot tests** (device-pinned config; runnable on any sim per the newer pattern):
  post-list cell blurred vs revealed; post-detail header blurred; an NSFW community row blurred
  + badged.

## 10. Documentation

- **`docs/features/nsfw-content.md`**: remove the "no blur mode" out-of-scope line; document the
  blur axis, the two toggles, the disable-when-off rule, the age ack, the discovery gating now
  covering Search + composer picker, and community-art blur. Add scenarios for blur/reveal and
  for search gating.
- **`docs/features/README.md`**: update the capability table row and the "Feature coverage by
  area" map.
- Re-verify adjacent docs touched: `discover.md`, `post-thumbnails.md`, `community-screen.md`,
  `new-post.md`, `feeds-and-sorting.md`. No `.swift` links.

## Out of scope

- Blurring inline body images / gallery images / comment images (scope = thumbnails + post
  detail + community art).
- Per-community or per-feed blur overrides.
- Persisting reveal state across launches.
- Registration-flow `blur_nsfw` (registration sets `show_nsfw` only today).
- Any change to widget NSFW behavior.

## Open questions (for plan stage, non-blocking)

- Community-art reveal: per-community session reveal vs. always-blurred-when-NSFW in v1.
  Leaning per-community for consistency with posts, but acceptable to simplify if it complicates
  list-cell reuse.
- Whether the shared NSFW badge lives in `SpudUIKit` (if a UIKit consumer needs it) or stays a
  SwiftUI view; decide once the consuming cells are known.
