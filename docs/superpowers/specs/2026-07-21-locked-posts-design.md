# Locked posts — design spec

- **Date:** 2026-07-21
- **Status:** approved (autonomous), ready for plan
- **Branch:** `feat/locked-posts`

## Problem

A Lemmy/PieFed post can be **locked** (by a moderator/admin) to stop new discussion.
Spud already knows a post is locked (`PostRecord.isLocked`, persisted since migration
`v5`, surfaced on every observation row), and the **feed list already shows** a yellow
`lock.fill` glyph + VoiceOver "Locked". But:

1. **Post detail shows no locked indicator**, and gives the user no explanation for why
   commenting isn't working.
2. **Nothing gates commenting** — every reply entry point ignores `isLocked`, so a user
   can open the composer, type a reply, and only then have the server reject it
   (`LemmyErrorType::Locked`), which parks a failed item in the outbox. That's a poor,
   confusing experience.

## Server behavior (confirmed against the Lemmy Rust backend)

- **New comments/replies on a locked post are rejected** server-side with
  `LemmyErrorType::Locked`. Moderators/admins are exempt (they can reply without unlocking).
- **Voting on the post is still allowed** — no lock guard in the post-vote path.
- **Voting on existing comments is still allowed** — no lock guard in the comment-vote path.
- **Editing your existing comment is still allowed** — no lock guard in the comment-edit path.
- `locked` is a first-class `Post` field surfaced in `PostView.post.locked` across v3/v4/PieFed.

Reference clients agree: lemmy-ui disables the reply box but keeps vote buttons live;
jerboa shows a lock icon and defers rejection to the server.

## Goals

- Clearly indicate on **post detail** that a post is locked and that new comments are off,
  while making clear **voting still works**.
- Keep the existing **post-list** locked indicator (already shipped) — verify, don't rebuild.
- **Prevent** the user from starting a comment/reply on a locked post (don't offer a dead
  action; don't let a doomed send hit the outbox).
- Leave **voting** (post and comment) and **editing your own comment** fully enabled.
- React to **live** moderator lock/unlock (the moderation menu can toggle lock while the
  screen is open) with no manual refresh.

## Non-goals

- No change to the moderator Lock/Unlock action itself (already shipped — see
  `moderation-actions.md`).
- **Comment-level locking** (a newer v4 concept where an individual comment subtree is
  locked) is out of scope; we gate on the **post** being locked only. Noted as out-of-scope.
- No special-casing for moderators/admins in the client: when a post is locked, Spud hides
  the reply affordances for everyone. A moderator unlocks the post first (existing
  moderation menu), then replies. This matches lemmy-ui's default and avoids relying on
  client-side mod-status detection for a write path the server independently enforces.

## Design

### 1. One source of truth for the policy + copy (DRY)

Add a tiny, pure, unit-testable helper (app target, `Spud/Scenes/Shared/` or
`Spud/Utils/`), e.g. `CommentLockPolicy`:

- `static func canComment(isPostLocked: Bool) -> Bool` → `!isPostLocked`.
- Localized copy constants used by every surface so the wording never drifts:
  - `title` = "Comments are locked"
  - `message` = "New comments and replies are turned off. You can still vote."
  - `shortVoiceOver` = "Locked"

Every gate and every piece of UI copy below reads from this one helper. No literal
"Comments are locked" string is duplicated across files.

### 2. Post detail indication

Both driven by `PostDetailHeaderViewModel.isLocked` (already carries `isLocked` via
`PostDetailHeaderRow`), so both update automatically when a mod toggles lock/unlock (the
header row re-emits).

- **At-a-glance glyph (parity with the feed):** render
  `PostStatusBadge.badges(for: PostDetailHeaderRow)` in the detail header's metadata line,
  exactly as the feed already does in `PostListPostViewModel`. This shows the yellow
  `lock.fill` (and, for free, the existing removed/deleted/featured glyphs the detail header
  currently omits). Include the status in the header's accessibility so VoiceOver announces
  "Locked" (mirror `PostListPostViewModel`'s existing VoiceOver treatment).

- **Explanatory notice:** a clear, full-width notice at the post→comments boundary. Embed it
  in `PostDetailHeaderCell` **below the post body** (not a separate diffable section — keeps
  it reacting to live lock toggles with no datasource surgery), shown only when
  `isLocked`. A rounded, `secondarySystemBackground` info row: a `lock.fill` leading symbol,
  `CommentLockPolicy.title` as the title, `CommentLockPolicy.message` as the subtitle. One
  combined accessibility element reading title + message; not an interactive control.

  Reuse an existing padded/rounded container style if one exists (the author-badge
  `BadgeLabel` / `makeAuthorBadgeView` style, or the feed's state-surface styling); prefer
  reuse over a bespoke view. Extract a small `LockedCommentsNoticeView` if no existing
  component fits cleanly.

### 3. Gate commenting (hide affordances + safety-net at the choke points)

**Hide the reply affordances when the post is locked** so no dead action is offered:

- Detail overflow-menu "Add comment" (`PostDetailViewController+OverflowMenu`) — omit when locked.
- Detail comment-row **swipe** `.reply` — omit when locked.
- Detail comment-row **context-menu** "Reply" — omit when locked.
- Feed post **swipe** `.reply` (`PostListViewController`) — omit when `row.isLocked`.
- Feed/Search post **context-menu** "Reply" (`PostContextMenuBuilder`) — omit when locked
  (thread `isLocked` into the builder's input; `PostListRow.isLocked` is available).

**Safety-net at the two composer choke points** (covers any path we missed, and future
callers): if the post is locked, do not present the composer; instead show a lightweight,
non-blocking explanation (`CommentLockPolicy.title` — reuse the existing alert/toast
pattern the signed-out gate uses). Gate:

- `PostDetailViewController.presentComposer(target:)` — **only** for new-comment / reply
  targets (`.postReply`, `.commentReply`). **Do NOT block edit targets**
  (`.commentEdit` / post-edit) or the failed-item Edit path — editing an existing comment is
  allowed on a locked post server-side, and the failed-reply "Edit" flow just edits unsent
  text. Gate by inspecting the composer `target`.
- `PostListViewController.replyToPost(serverPostId:)` — block when the row is locked.

**Do not touch** voting affordances (post or comment), save/hide, share, or the moderation
Lock/Unlock action.

### 4. Post list

Already satisfied (yellow `lock.fill` glyph + "Locked" VoiceOver via `PostStatusBadge` in
`PostListPostViewModel`). Verify it renders; make no change unless a defect is found.

## Accessibility

- Detail header announces "Locked" as part of its status (mirroring the feed).
- The locked notice is one VoiceOver element reading title + message; static, not a control.
- Vote buttons keep their labels/traits (unchanged) — a VoiceOver user can still vote.
- Dynamic Type: the notice uses text styles and wraps; the glyph scales with the metadata line.

## Testing

- **Unit (`SpudTests`):**
  - `CommentLockPolicy.canComment` — locked → false, unlocked → true.
  - `PostStatusBadge` includes `lock.fill`/`.systemYellow` when `isLocked` (confirm existing
    coverage; add for the `PostDetailHeaderRow` overload if missing).
  - Affordance/gating decision surfaced as testable pure logic (the policy + any
    view-model computed flag), asserting: locked ⇒ reply affordances suppressed and
    `presentComposer` no-ops for reply targets; **edit target still allowed**; voting flag
    unaffected. (UIKit VCs aren't directly unit-tested — assert the decision function.)
- **Snapshot (`SpudSnapshotTests`, iPhone 17 Pro / iOS 26.3.x reference):**
  - `PostDetailHeaderCell` with `isLocked = true` — glyph in metadata + notice below body.
    Prefer the device-independent `.image(on: .deterministicPhone)` config. Record the new
    ref one class at a time; `git add` only the explicit new ref.
- **Manual/on-device (owed, note in the plan):** open the example locked post
  (`https://discuss.tchncs.de/post/64347319`) and confirm: notice + glyph show, reply
  affordances are gone, upvote/downvote on the post and on comments still work, and a mod
  unlock makes the reply affordances reappear live.

## Documentation

- New `docs/features/locked-posts.md` (behavior + rules + Given/When/Then scenarios +
  out-of-scope for comment-level lock and the mod-unlock-to-reply path).
- Cross-link from `replying.md` (add a rule: replying is unavailable on a locked post),
  `post-detail-and-comments.md` (detail shows the locked indicator), and
  `moderation-actions.md` (Lock stops new comments — link the user-facing effect).
- Update `README.md` capability table **and** the "Feature coverage by area" map.

## Files (from exploration; anchors, not a contract)

- Read `isLocked`: `PostDetailHeaderRow.isLocked`, `PostListRow.isLocked` (already present).
- `Spud/Scenes/Shared/PostStatusBadge.swift` — already maps `isLocked` (no change needed).
- `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift` + `PostDetailHeaderCell.swift`
  — add glyph to metadata + locked notice below body.
- `Spud/Scenes/PostList/PostListPostViewModel.swift` — reference for the glyph + VoiceOver pattern.
- `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — `presentComposer(target:)`,
  comment swipe `.reply`, comment context-menu "Reply".
- `Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift` — "Add comment".
- `Spud/Scenes/PostList/PostListViewController.swift` — `replyToPost`, feed swipe `.reply`.
- `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift` — feed/Search reply action.
- New: `CommentLockPolicy` (policy + copy) and, if needed, `LockedCommentsNoticeView`.
