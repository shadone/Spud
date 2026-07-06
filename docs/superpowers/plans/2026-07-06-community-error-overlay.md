# Community Feed Error/Empty Overlay Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The feed's full error and empty states never overlap the community header (or any future `tableHeaderView`): `PostListViewController` renders them into the table's `backgroundView` — below the header in z-order and top-inset to center in the below-header region — instead of the transparent VC-level `contentUnavailableConfiguration` overlay. Fixes the shipped bug where "Couldn't reach <host>" + Try again / Work offline rendered see-through on top of the community header.

**Root cause (verified):** the error surface is a transparent `UIContentUnavailableConfiguration` set via the VC-level `contentUnavailableConfiguration` (whole-view overlay). The prior fix eb76cc12 (`FeedFailurePresentation.decide(hasContent:)`) gates it on `!displayedRows.isEmpty` — posts only. In the Community screen the header is the feed table's `tableHeaderView` (`CommunityViewController.swift` `setScrollingHeaderView`, PostListViewController.swift:409-415), not a row, so "zero posts + populated header" routes to `.fullErrorSurface` and overlays the header. The `.empty` branch (PostListViewController.swift:1198-1206) has the identical latent bug. The in-repo precedent for this bug class is b7ecc4ce (`PersonViewController.updateContentUnavailable`, PersonViewController.swift:705-753): render `config.makeContentView()` into `tableView.backgroundView`. Exhaustive inventory (2026-07-06 scout): every other `contentUnavailableConfiguration` site app-wide (Inbox, DMThread, RecipientPicker, Search) has an empty table behind it — unaffected; Person is already fixed; `PostDetailCommentsFailedCell` is an opaque cell.

**Architecture (binding):** **State surfaces live in the table's `backgroundView`, never the VC-level overlay.** `PostListViewController` gets one private state-surface mechanism replacing all four `contentUnavailableConfiguration` sites (clears at :1193 and :1197, `.empty` set at :1206, `.failed` set at :1225):

- A container `UIView` hosted as `tableView.backgroundView`, holding the `UIContentUnavailableView` (`config.makeContentView()`) constrained to the container's edges EXCEPT top, which is pinned at the scrolling header's height — mirroring the skeleton's existing `syncSkeletonHeaderInset()` concept (PostListViewController.swift:1076-1081) so the surface centers within the *below-header* region, not the full bounds (a bounds-centered surface hides under a taller-than-half header; Person accepted that residual, we do better here). Header height 0 when no `scrollingHeaderView` — plain feeds center exactly as before.
- The skeleton ALREADY uses the `backgroundView` slot (`showLoadingSkeleton` :1069-1072, `hideLoadingSkeleton` :1084-1086, both `===`-guarded). The states are mutually exclusive; the new surface's set/clear must be symmetric with the skeleton's guards so neither clobbers the other (state transitions: content/loading → clear surface; `.empty`/`.failed` → `hideLoadingSkeleton()` then install surface).
- `contentUnavailableConfiguration` stays permanently nil (delete the assignments; a comment on the mechanism points to this plan's invariant and the Person precedent).
- Button actions ride the same `UIContentUnavailableConfiguration` (`buttonProperties.primaryAction`) rendered by `UIContentUnavailableView` — same view class the VC-level presentation uses; `makeErrorConfiguration(for:)` (:1233-1253) is reused untouched.
- `FeedFailurePresentation.decide(hasContent:)` and the posts→toast invariant are UNCHANGED — this plan changes only WHERE the full surface renders when the list is empty.

**Tech Stack:** UIKit (`UIContentUnavailableConfiguration`/`UIContentUnavailableView`), Swift Testing (SpudTests), swift-snapshot-testing (XCTest target).

## Global Constraints

- Verify per task: `make build` + `make test-only ONLY=SpudTests`. Snapshot gate per Task 2 (env-dependent — see its STOP).
- Zero behavior change outside the fix: posts-on-screen failures still toast (existing `FeedFailurePresentationTests` untouched and green); plain feeds (Posts tab, Subscriptions, Account) keep a visually centered surface (no header → inset 0).
- `mint run swiftformat <changed files>` before each commit; explicit-path staging only (worktree carries 440 cosmetic-M annex refs — never `git add -A`). Conventional commits; push is user-gated.
- No emojis. Three-tier docs discipline applies (Task 3).
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/community-error-overlay`, branch `worktree-community-error-overlay` off main 1eadfb86.

---

### Task 1: Move feed error/empty surfaces into the table backgroundView

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` — the four `contentUnavailableConfiguration` sites (:1193, :1197, :1206, :1225) + a new private state-surface helper per the binding architecture (container + `makeContentView()`, top inset = `scrollingHeaderView?.frame.height ?? 0`, kept in sync where `syncSkeletonHeaderInset()` is synced; skeleton-symmetric guards).
- Test: `SpudTests/PostListStateSurfaceTests.swift` (new) — structural regression tests on the REAL `PostListViewController`.

**Structural tests (required assertions):**
1. Empty rows + a `setScrollingHeaderView` header installed + `.failed` state delivered → `contentUnavailableConfiguration == nil` AND the table's `backgroundView` hosts a `UIContentUnavailableView` whose top inset equals the header height.
2. Same for `.empty`.
3. Transition back to content (or loading) clears the surface; skeleton show/hide still works (its `===` guard untouched — assert skeleton install then state-surface install then skeleton reinstall doesn't leak the wrong view).
4. No header (plain feed) → surface installs with inset 0.

Construct the VC with the SpudTests fake-dependency pattern (`FakeDependencies`/`*Dependencies` doubles exist in SpudTests; `PostListViewModel` has in-memory-DB fixtures from the postlist-vm work). Drive the state through the VM's public state (preferred) or, if the update path is private, raise the minimal member(s) to `internal` for `@testable` — mirroring how other VC tests in SpudTests reach internals.

**STOP conditions:** (a) if driving `.failed`/`.empty` through the real VM requires more than seeding the in-memory DB + invoking existing VM/VC entry points — i.e. you find yourself adding production seams beyond `private`→`internal` visibility raises — report before building scaffolding; (b) if `UIContentUnavailableView` turns out not to render the config's buttons/actions when hosted manually (verify visually via the snapshot in Task 2 or a quick view-hierarchy dump), report — the fallback design (opaque `config.background` on the overlay) is a product-visible change the human must approve.

- [ ] Steps: RED structural tests → implement → GREEN (incl. `FeedFailurePresentationTests` + all existing PostList tests untouched) → `make build` + `make test-only ONLY=SpudTests` → swiftformat → commit `fix: render feed error/empty states below the scrolling header, not over it` (explicit paths).

### Task 2: Snapshot regression — error surface below the community header

**Files:**
- Create: `SpudSnapshotTests/FeedStateSurfaceSnapshotTests.swift` — mirrors `PersonContentUnavailableSnapshotTests` (the b7ecc4ce precedent: standalone table + fake community-style header + the REAL `makeErrorConfiguration`-shaped config rendered through the new surface mechanism), light+dark. Must use a header TALLER than half the table height in at least one case — that pins the top-inset improvement (bounds-centered rendering would hide the surface; the ref must show it fully visible below the header).
- Refs: record on the reference sim via focused `xcodebuild ... -only-testing:SpudSnapshotTests/FeedStateSurfaceSnapshotTests` (first run records+fails, rerun verifies); `git annex`-tracked — stage ONLY the new refs explicitly.

**Env verdict (probed 2026-07-06 evening, before dispatch): RED.** The host snapshot drift (spec §5) persists — 12/19 failures across `LoadingStatesSnapshotTests` + `PersonContentUnavailableSnapshotTests`, all on text-bearing refs (`test_errorUnreachable_*`, `test_errorState_messageBelowHeader_*`), while pure-geometry tests (`test_skeleton*`, `test_errorState_contentDoesNotOverlapHeader`) pass. Therefore: do NOT record pixel refs. Instead (a) write the pixel snapshot test bodies but guard them with a skip + `// Refs deliberately not recorded: host snapshot drift 2026-07-06, spec §5; record when make snapshot is green again` so they self-document; (b) the ENFORCEABLE regression lock is a non-pixel geometry test mirroring `PersonContentUnavailableSnapshotTests.test_errorState_contentDoesNotOverlapHeader` (which passes despite the drift): lay out the surface with a header taller than half the table height and assert the `UIContentUnavailableView`'s frame sits entirely below the header's maxY. If even the geometry test proves environment-sensitive, stop and report.

- [ ] Steps: write test → record refs (env permitting) → verify rerun green → `make test-only ONLY=SpudTests` still green → swiftformat → commit `test: snapshot the feed error surface below a scrolling header` (explicit refs staged by name).

### Task 3: Docs + final review + merge

- [ ] Docs (three-tier discipline): `docs/features/feed-loading.md` — extend the line-21 invariant from "never overlap on-screen posts" to never overlapping ANY on-screen content including a scrolling header, and describe the backgroundView placement; `docs/features/community-screen.md` — add the error/empty-below-header rule next to the existing skeleton-inset rule (line ~14); `docs/features/empty-error-loading-states.md` — note the two placement mechanisms (VC-level overlay only for screens with nothing behind it; backgroundView for header-bearing tables) and update the Scenarios accordingly; re-verify `docs/features/person-profile.md` still reads correctly (Person keeps its shipped bounds-centered variant; note the tall-header centering residual there as a known limitation if the doc claims otherwise). README capability table/by-area map only if status lines change (this is a fix within existing capabilities — verify, don't assume).
- [ ] Commit `docs: feed error/empty states render below scrolling headers`.
- [ ] Whole-branch review (fresh reviewer, most capable model): risk list = state-machine transitions between skeleton/surface/content in the shared `backgroundView` slot, refresh-control interplay, button action wiring through `makeContentView()`, header-height sync points, test assertions not vacuous, no snapshot-ref noise staged.
- [ ] ONE fix agent for findings; re-run gates.
- [ ] Merge protocol (workspace CLAUDE.md): `git fetch`, re-check `main..worktree-community-error-overlay` + shared-checkout dirt overlap RIGHT BEFORE merging, `git annex restage` first if merging in the shared checkout, `--no-ff`. Push only on the user's explicit word.
