# Locked posts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Indicate on post detail (and confirm on the post list) that a post is locked and that new comments are off, prevent starting a comment/reply on a locked post, and keep voting and comment-editing fully enabled.

**Architecture:** `isLocked` already flows end-to-end (GRDB `PostRecord.isLocked` since migration `v5`; on every observation row). A new pure `CommentLockPolicy` centralises the decision + copy. Post detail gains a `lock.fill` glyph in the header metadata (mirroring the feed) and a locked-comments notice embedded in the header cell below the body — both driven by `PostDetailHeaderViewModel.isLocked`, so they react to live mod lock/unlock. Reply affordances are hidden when locked, with a safety-net gate at the two composer choke points.

**Tech Stack:** UIKit, GRDB, Swift 6 / strict concurrency, Swift Testing (`SpudTests`), swift-snapshot-testing (`SpudSnapshotTests`). XcodeGen-generated project (`make project` after adding files).

## Global Constraints

- Default branch `main`; work is on `feat/locked-posts`. Conventional commits (`feat:`/`test:`/`docs:`), no emojis anywhere.
- No schema migration — `isLocked` already persisted (`v5`) and on every observation row (`PostDetailHeaderRow.isLocked`, `PostListRow.isLocked`).
- **Voting (post + comment), save/hide, share, and the moderator Lock/Unlock action must remain fully enabled** on a locked post. Only *new comment/reply creation* is blocked; **editing an existing comment is still allowed**.
- DRY copy: exactly one source of the strings "Comments are locked" / "New comments and replies are turned off. You can still vote." — `CommentLockPolicy`. No literal duplicates.
- Frameworks never import the app target; this feature is app-target only (`Spud/`).
- Adding new source files requires `make project` (XcodeGen) before building.
- Run `mint run swiftformat <changed paths>` before the final verify (never after a green verify).
- Build/test via the `make` targets (auto-resolve destination + plugin/macro skip flags). Reference snapshot device is iPhone 17 Pro / iOS 26.3.x.
- Reviewer/verify subagents in this shared checkout are **read-only on git** (no `stash`/`reset`/`checkout --`/file deletion).

---

### Task 1: `CommentLockPolicy` — policy + copy (pure, testable)

**Files:**
- Create: `Spud/Utils/CommentLockPolicy.swift`
- Test: `SpudTests/CommentLockPolicyTests.swift`

**Interfaces:**
- Produces:
  - `enum CommentLockPolicy` with:
    - `static func canComment(isPostLocked: Bool) -> Bool`
    - `static var title: String` → localized "Comments are locked"
    - `static var message: String` → localized "New comments and replies are turned off. You can still vote."
    - `static var shortStatus: String` → localized "Locked" (short label / VoiceOver)

- [ ] **Step 1: Write the failing tests**

```swift
// SpudTests/CommentLockPolicyTests.swift
import Testing
@testable import Spud

struct CommentLockPolicyTests {
    @Test func lockedPostCannotBeCommented() {
        #expect(CommentLockPolicy.canComment(isPostLocked: true) == false)
    }

    @Test func unlockedPostCanBeCommented() {
        #expect(CommentLockPolicy.canComment(isPostLocked: false) == true)
    }

    @Test func copyIsNonEmptyAndDistinct() {
        #expect(!CommentLockPolicy.title.isEmpty)
        #expect(!CommentLockPolicy.message.isEmpty)
        #expect(!CommentLockPolicy.shortStatus.isEmpty)
        #expect(CommentLockPolicy.title != CommentLockPolicy.message)
    }
}
```

- [ ] **Step 2: Run and verify it fails**

Run: `make test-only ONLY=SpudTests` (or `xcodebuild … -only-testing:SpudTests/CommentLockPolicyTests test`).
Expected: FAIL — `CommentLockPolicy` not found.

- [ ] **Step 3: Implement**

```swift
// Spud/Utils/CommentLockPolicy.swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Single source of truth for whether a user may comment on a post, and for the
/// user-facing copy that explains a locked post. A locked post rejects new
/// comments/replies server-side (`LemmyErrorType::Locked`); voting on the post
/// and its comments, and editing your own comment, remain allowed. Centralised
/// here so every gate and every label reads the same rule and the same wording.
enum CommentLockPolicy {
    /// Whether a new comment or reply may be started. Editing an existing
    /// comment is a separate, always-allowed action and is NOT gated by this.
    static func canComment(isPostLocked: Bool) -> Bool {
        !isPostLocked
    }

    /// Title for the locked-comments notice / gate ("Comments are locked").
    static var title: String {
        NSLocalizedString(
            "Comments are locked",
            comment: "Title shown when a post is locked and cannot receive new comments."
        )
    }

    /// Explanatory subtitle: new comments are off, but voting still works.
    static var message: String {
        NSLocalizedString(
            "New comments and replies are turned off. You can still vote.",
            comment: "Explains that a locked post accepts no new comments but voting is still allowed."
        )
    }

    /// Short status word for compact labels and VoiceOver ("Locked").
    static var shortStatus: String {
        NSLocalizedString(
            "Locked",
            comment: "Short status label for a locked post."
        )
    }
}
```

- [ ] **Step 4: `make project` (new file), run tests, verify pass**

Run: `cd Spud && make project && make test-only ONLY=SpudTests`
Expected: `✔ Test run with N tests … passed` including `CommentLockPolicyTests`.

- [ ] **Step 5: Commit**

```bash
git add Spud/Utils/CommentLockPolicy.swift SpudTests/CommentLockPolicyTests.swift
git commit -m "feat: add CommentLockPolicy for locked-post commenting rule and copy"
```

---

### Task 2: Post detail locked indication (header glyph + notice)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift`
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift`
- Create: `Spud/Scenes/PostDetail/Content/Header/LockedCommentsNoticeView.swift` (only if no existing rounded-info component fits — check `PostStatusBadge`, `AuthorBadgeView`/`BadgeLabel`, and the feed state-surface view first)
- Test: `SpudSnapshotTests/PostDetailHeaderSnapshotTests.swift` (extend if it exists; else create following an existing header/cell snapshot test)

**Interfaces:**
- Consumes: `CommentLockPolicy` (Task 1); `PostStatusBadge.badges(for: PostDetailHeaderRow)` (existing); `PostDetailHeaderRow.isLocked` (existing).
- Produces (on `PostDetailHeaderViewModel`, names later tasks may reference):
  - `var isLocked: Bool` — from the header row.
  - `var contentStatusBadges: [PostStatusBadge]` — `PostStatusBadge.badges(for: row)`.

**Design contract:**
- Render the content-status glyph(s) in the detail header's metadata line exactly as `PostListPostViewModel` (see `PostListPostViewModel` ~L341-352 for the append pattern and ~L476 for the "Locked" VoiceOver append). Reuse `PostStatusBadge`; do not invent a second glyph mapping.
- Show a full-width locked notice **below the post body inside `PostDetailHeaderCell`** when `isLocked` (not a separate diffable section). Rounded `secondarySystemBackground` container, leading `lock.fill`, `CommentLockPolicy.title` (headline/subheadline weight) + `CommentLockPolicy.message` (secondary, footnote). Hidden (and contributing no height) when not locked. One combined accessibility element: label = "\(title). \(message)", no control trait.
- Must update live when a mod toggles lock/unlock — driven by the header row re-emit (the cell reconfigures from the VM). Do not cache `isLocked` outside the row.
- Follow the cell's existing body/subview construction and the `remeasureRowHeightsWithoutAnimation()` pattern already used for async header height changes (do not animate the notice appearing on reconfigure).

- [ ] **Step 1: Read the anchors**

Read `PostListPostViewModel` (metadata-badge append + "Locked" VoiceOver), `PostStatusBadge.swift`, `PostDetailHeaderViewModel.swift`, and `PostDetailHeaderCell.swift` (its metadata line construction, `makeBodyView`, `badgesStackView`, and how it reconfigures from the VM). Match those patterns.

- [ ] **Step 2: Add the snapshot test (failing / records new ref)**

Add a snapshot case rendering `PostDetailHeaderCell` (or the header VC in isolation, matching the existing header snapshot approach) for a locked post fixture, using the device-independent `.image(on: .deterministicPhone)` config where the file uses it. First run records the ref and fails.

Run (one class): `cd Spud && xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailHeaderSnapshotTests -destination "$(scripts/resolve-test-destination.sh --reference)" -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL (records missing ref).

- [ ] **Step 3: Implement VM + cell + notice**

Add `isLocked` / `contentStatusBadges` to the VM; render glyph in metadata + VoiceOver "Locked" (via `CommentLockPolicy.shortStatus`); add the locked notice to the cell (extract `LockedCommentsNoticeView` if no existing component fits). `make project` if a file was added.

- [ ] **Step 4: Re-run the snapshot, verify pass; then full snapshot plan sanity**

Re-run the single class (Step 2 command): Expected PASS. Then confirm no unrelated ref drift for adjacent header snapshots.

- [ ] **Step 5: Commit**

```bash
# add only the explicit new/changed refs + sources
git add Spud/Scenes/PostDetail/Content/Header/ SpudSnapshotTests/PostDetailHeaderSnapshotTests.swift SpudSnapshotTests/__Snapshots__/PostDetailHeaderSnapshotTests/<new-ref>.png
git commit -m "feat: show locked indicator and notice on post detail"
```

---

### Task 3: Gate commenting — hide reply affordances + choke-point safety nets

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (`presentComposer(target:)`; comment-row swipe `.reply`; comment-row context-menu "Reply")
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift` (overflow "Add comment")
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (`replyToPost(serverPostId:)`; feed swipe `.reply`)
- Modify: `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift` (feed/Search reply action) — thread `isLocked` into its input
- Test: `SpudTests/PostContextMenuBuilderTests.swift` (extend if present) and/or `CommentLockPolicyTests` for any surfaced decision

**Interfaces:**
- Consumes: `CommentLockPolicy.canComment(isPostLocked:)` (Task 1); `PostDetailHeaderViewModel.isLocked` (Task 2); `PostListRow.isLocked`.

**Design contract:**
- **Hide (omit) the reply affordance** — do not merely disable — everywhere below when the post is locked (`!CommentLockPolicy.canComment(isPostLocked:)`):
  - Detail overflow "Add comment"; detail comment swipe `.reply`; detail comment context-menu "Reply"; feed swipe `.reply`; feed/Search context-menu reply.
- **Safety-net at the composer choke points** (present nothing; show the existing signed-out-style alert/toast with `CommentLockPolicy.title`, then return):
  - `PostDetailViewController.presentComposer(target:)` — gate **only** `.postReply` / `.commentReply` targets. Inspect the `target`; **do not** gate edit targets (`.commentEdit` / post edit) or the failed-item Edit path.
  - `PostListViewController.replyToPost(serverPostId:)` — gate when the row is locked.
- `PostContextMenuBuilder` must receive `isLocked` via its existing input model (add the field if absent; `PostListRow.isLocked` and search rows already carry it) and omit the reply `UIAction` when locked. Keep every other action (vote/save/hide/share/open/moderation) unchanged.
- **Do not touch** vote/save/hide/share affordances or the moderation Lock/Unlock action.

- [ ] **Step 1: Read the anchors**

Read each modification site listed in Files and the `PostContextMenuBuilder` input struct + its existing unit test. Confirm how the signed-out gate presents its alert/toast (reuse that exact presentation for the locked message).

- [ ] **Step 2: Add/extend the failing unit test**

If `PostContextMenuBuilder` builds a `UIMenu` from a pure input, assert the built menu **contains** a reply action when `isLocked == false` and **omits** it when `isLocked == true`, all other actions unchanged. (Follow the existing builder-test pattern.)

Run: `cd Spud && make test-only ONLY=SpudTests`
Expected: FAIL (builder doesn't yet honour `isLocked`).

- [ ] **Step 3: Implement the gates**

Apply the hide + safety-net changes above. Route all reply-affordance suppression and both choke-point gates through `CommentLockPolicy`.

- [ ] **Step 4: Run tests, verify pass**

Run: `cd Spud && make test-only ONLY=SpudTests`
Expected: PASS (builder omits reply when locked; edit/vote paths unaffected).

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/PostDetail/Content/PostDetailViewController.swift Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Utils/ContextMenus/PostContextMenuBuilder.swift SpudTests/PostContextMenuBuilderTests.swift
git commit -m "feat: block commenting on locked posts while keeping voting enabled"
```

---

### Task 4: Documentation

**Files:**
- Create: `docs/features/locked-posts.md`
- Modify: `docs/features/replying.md` (add a rule + link), `docs/features/post-detail-and-comments.md` (locked indicator note + link), `docs/features/moderation-actions.md` (link the user-facing effect of Lock), `docs/features/README.md` (capability table **and** "Feature coverage by area" map)

**Design contract:**
- `locked-posts.md` follows `_TEMPLATE.md`: Surfaces `iphone, ipad`; Status `shipped`; Related links to `replying.md`, `post-detail-and-comments.md`, `moderation-actions.md`, `voting.md`. No `.swift` links.
- Document: locked indicator (glyph on feed + detail, notice on detail); commenting blocked (affordances hidden + composer gate); **voting and comment-editing remain enabled**; live update on mod unlock. Given/When/Then scenarios for: seeing the locked notice on detail, feed locked glyph, reply affordances absent when locked, voting still works when locked, and mod unlock re-enables replying. Out-of-scope: comment-level locking; the mod-unlock-to-reply path (no client mod bypass).
- Keep `replying.md`'s Status honest — add the locked rule to "Behavior and rules" and a "Not supported / out of scope" note (can't reply on a locked post).

- [ ] **Step 1: Write `docs/features/locked-posts.md`** per the template + contract above.
- [ ] **Step 2: Add the rule + cross-links** to `replying.md`, `post-detail-and-comments.md`, `moderation-actions.md`.
- [ ] **Step 3: Update `README.md`** capability table row + "Feature coverage by area" map entry (both sections).
- [ ] **Step 4: Commit**

```bash
git add docs/features/locked-posts.md docs/features/replying.md docs/features/post-detail-and-comments.md docs/features/moderation-actions.md docs/features/README.md
git commit -m "docs: document locked posts"
```

---

## Final verification (after all tasks)

- [ ] `mint run swiftformat <all changed source paths>`; re-stage if it rewrote anything.
- [ ] `make test` (full unit plan) green; `make snapshot` green on the reference device (only the new locked-header ref changed).
- [ ] Broad review subagent over the whole `main..feat/locked-posts` diff (read-only git).
- [ ] Manual on-device check (owed): example locked post `https://discuss.tchncs.de/post/64347319` — notice + glyph show, reply affordances gone, post/comment voting works, mod unlock re-enables reply live.

## Self-review notes (author)

- Spec coverage: detail glyph + notice (Task 2), feed already done (verified in Task 2 read/Task 3 feed swipe), gating all 5 affordances + 2 choke points (Task 3), voting/edit preserved (constraints + Task 3 contract), docs (Task 4). No gaps.
- No placeholders; concrete code for Task 1, concrete contracts + anchors for UIKit tasks (implementers have repo access and must match existing patterns).
- Type consistency: `CommentLockPolicy.canComment(isPostLocked:)`, `.title`, `.message`, `.shortStatus`; `PostDetailHeaderViewModel.isLocked` / `.contentStatusBadges` used consistently across Tasks 2-3.
