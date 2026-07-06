# Accent Snapshot Determinism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make snapshot renders independent of the sim's persisted accent preference, then re-record the 25 affected tests' refs under the pinned default — restoring the suite to 258/258 on clean sims.

**Architecture:** `ThemeManager.shared` (SpudUIKit/Theme/ThemeManager.swift) holds `accent: AccentColor = .lemmy`; the snapshot HOST app's `MainWindow.applyAccent` overwrites it at launch from the host's `UserDefaults.standard` accent pref (outside the ephemeral-store isolation, which covers only fixture `PreferencesService`s). Affected renders read the accent via `ThemeManager.currentAccentColor` (vote tints in `GeneralAppearance`) and window/root `tintColor` cascade (the `tv-pattern` template placeholder). Fix at the ThemeManager level: a `SnapshotDeterminism.pinAccent()` helper that `ThemeManager.shared.setAccent(.lemmy)` in setUp; on-screen (`FixedSafeAreaWindow`) captures also pin the window `tintColor`.

## Global Constraints

- The evidence base: 25 tests / 47 assertions fail identically on plain main and any branch, on a clean-install sim (list: the failure sets saved during Phase 2's parity check — regenerate via a full run's xcresult if needed). Affected classes observed: PostDetailHeader (image variants), Toast, MediaUI, MediaViewerCentering, MediaComponents, PostUnavailable, PendingPost, LinkPreview, HeaderInlineImage, PostDetailComment (image tests), plus Account*/Activity* app-level screens seen in earlier runs.
- Annex re-record ceremony (SpudSnapshotTests/CLAUDE.md) is authoritative: one class at a time; delete failing refs -> record run -> verify run; NO restage between; `git add` exact ref paths only; count with `find`.
- Worktree hygiene: pointer sweep before any run (content-grep, contentlocation cp — the CLAUDE.md recipe); stale-app uninstall before the first run; reboot the sim if timeout cascades appear; `pgrep -x xcodebuild` for contention checks (NOT ps|grep).
- Re-records happen ONLY for tests in the evidence set (or tests that fail with a provable accent-only delta — the tint shift visual signature). Anything failing differently: STOP and report.
- `git branch --show-current` == `worktree-accent-determinism` before commits. Never cd into the shared main checkout.

---

### Task 1: Pin the accent + re-record the affected refs

**Files:**
- Modify: `SpudSnapshotTests/SnapshotDeterminism.swift` — add a `@MainActor static func pinAccent()` (calls `ThemeManager.shared.setAccent(.lemmy)`; doc comment explaining the leak: host-app launch reads the sim's persisted accent; import SpudUIKit if needed). If `FixedSafeAreaWindow` setup lives here, also pin `window.tintColor = AccentColor.lemmy.color` for on-screen captures.
- Modify: every AFFECTED snapshot class's `setUp`/test preamble to call `SnapshotDeterminism.pinAccent()` (match each class's existing setup idiom — XCTest `setUp()` override). If a class already pins a tint explicitly (PostListPostCellSnapshotTests' lemmyTeal), leave it — it is already deterministic.
- Re-record: the failing refs per class, ceremony per Global Constraints.

**Procedure:**
- [ ] Step 1: Baseline run (`make snapshot` after pointer sweep + app uninstall) — capture the failing list from the xcresult; it must match the 25-test evidence set (± none; deviations = STOP).
- [ ] Step 2: Implement `pinAccent()` + wire into the affected classes. `make project` if files added (none expected), build.
- [ ] Step 3: Re-run the affected classes WITHOUT re-recording: tests whose refs were recorded under DEFAULT accent now pass (pin made them deterministic); tests recorded under the dirty accent still fail (expected). Record the split in the report.
- [ ] Step 4: Re-record the still-failing refs class-by-class (ceremony). Commit per class-batch: `test: re-record <class> refs under pinned default accent`.
- [ ] Step 5: Full `make snapshot` twice back-to-back: 258/258 both runs, byte-stable (no working-tree PNG changes after the second run).
- [ ] Step 6: `make test-only ONLY=SpudTests` (no unit regressions from the SnapshotDeterminism change — it's snapshot-target-only, expect trivially green) + SwiftFormat changed Swift paths; commit the pin: `test: pin ThemeManager accent in snapshot setup (SnapshotDeterminism.pinAccent)`.

---

### Task 2: Docs + verify + merge (controller)

- [ ] Update the follow-ups spec section 5 second addendum: accent leak FIXED (pin + re-records); remaining section-5 scope (runtime-pinned trim, injectable ThemeManager store as the deeper fix) unchanged.
- [ ] SpudSnapshotTests/CLAUDE.md: one bullet — accent is pinned via `SnapshotDeterminism.pinAccent()` in snapshot setUps; new snapshot classes MUST call it (or pin a tint explicitly); the leak mechanism one-liner.
- [ ] Whole-branch review (fresh reviewer): pin coverage completeness (every affected class), re-record justification per ref (accent-only deltas), ceremony compliance from the report.
- [ ] Merge --no-ff into main (advance/cleanliness checks; the treadmill rule: if main moved, integrate first and re-verify the suite once), push (authorized), cleanup worktree/branch, memory update.
