# Test-Suite Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two named reliability debts from the 2026-07-06/07 arcs are closed: (1) every `.image(size:traits:)`-style snapshot capture is immune to sim-level Dynamic Type pollution (the `medium`-drift incident) by routing all per-file `traits()` helpers through `SnapshotDeterminism.contentSizeTrait` — with ALL existing refs byte-identical; (2) the `PostDetailHeaderDegradedImageTests` / `PostDetailHeaderImageReuseTests` parallel-load flake (three sightings in one day: full-plan runs fail, isolated runs pass) is root-caused and hardened. Plus one micro-hygiene item: `SplitTabResolverTests`' fixture builds `PreferencesService()` on `.standard` against the repo's own `ephemeral()` rule.

**Background (verified):** the 2026-07-06 "host renderer drift" was the shared sim's Dynamic Type at `medium` — `.image(size:traits:)` captures inherit the sim's setting; device-config captures (`deterministicPhone` etc.) are immune because swift-snapshot-testing hardcodes `.medium` into their traits (verified in package source; forcing `.large` there BREAKS existing refs — do NOT touch the device-config family). `SnapshotDeterminism.contentSizeTrait` (SnapshotDeterminism.swift:110) exists and is used by `FeedStateSurfaceSnapshotTests`; ~28 files build traits via `UITraitCollection(traitsFrom:` and most lack the pin. The suite is currently 261/261 green with the sim at the default `large`, so pinning `.large` must be byte-identical everywhere — any ref that changes under the pin is a STOP, not a re-record.

## Global Constraints

- ZERO snapshot refs re-recorded or changed. The traits retrofit's gate is the full `make snapshot` staying 261/261 with zero ref-file modifications (`git status` on `__Snapshots__` shows only the pre-existing cosmetic annex noise — check by count, 442).
- Do NOT touch `ViewImageConfig.deterministicPhone` / `deterministicIPadLandscape` or any `.image(on:)` device-config usage (library-pinned `.medium`, immune, and refs depend on it).
- Verify per task: `make build` + the relevant `make test-only` target; snapshot gate per Task 1. `mint run swiftformat <changed files>`; explicit-path staging (442 cosmetic-M annex refs — never `git add -A`). Conventional commits; push user-gated; no emojis.
- The shared main checkout carries another agent's uncommitted edits to root `CLAUDE.md` and `SpudSnapshotTests/CLAUDE.md` — this branch must NOT touch either file (the pending sim-Dynamic-Type gotcha bullet for SpudSnapshotTests/CLAUDE.md stays parked; do not add it here).
- Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/test-hardening`, branch `worktree-test-hardening` off main 9ef81e03.
- Sim courtesy: `pgrep -x xcodebuild` before every test invocation; wait in a sleep-60 loop (another investigation may hold the sim early in this branch's life).

---

### Task 1: Route all size+traits snapshot captures through contentSizeTrait

**Files:**
- Modify: every `SpudSnapshotTests/*.swift` (and `SpudMarkdownKitSnapshotTests/*.swift` if applicable — check whether that target has its own traits helpers and whether it can see `SnapshotDeterminism`; if it can't, replicate the single-line trait locally with a comment) whose per-file `traits(...)`/inline `UITraitCollection(traitsFrom: [...])` builds capture traits WITHOUT `preferredContentSizeCategory` — add `SnapshotDeterminism.contentSizeTrait` to the `traitsFrom:` array. Files already pinning content size (e.g. Summary/Activity/DiagnosticLog per the 2026-07-06 grep) are left byte-identical unless they hand-roll `UITraitCollection(preferredContentSizeCategory:)` — those switch to the shared constant (identical value, DRY).
- No test-logic changes, no new tests: this task is a pure determinism retrofit.

**Method:** inventory first (`grep -rn "UITraitCollection(traitsFrom:" SpudSnapshotTests/ SpudMarkdownKitSnapshotTests/`), classify each hit (already-pinned / needs-pin / device-config-DO-NOT-TOUCH), and record the classification table in your report. Then edit, then gate.

**Gate (the whole point):** full `make snapshot` = 261/261 AND zero `__Snapshots__` content changes. If ANY ref fails under the pin: STOP, report which file/ref — that ref was recorded under non-default Dynamic Type and the human decides (do not re-record).

- [ ] Steps: inventory → edits → `make build` + full `make snapshot` (261/261, no ref changes) → swiftformat → commit `test: pin content size in all size+traits snapshot captures` (explicit paths).

### Task 2: Root-cause and harden the header-image flaky suites (+ micro-hygiene)

**Files:**
- Investigate then modify: `SpudTests/PostDetailHeaderDegradedImageTests.swift`, `SpudTests/PostDetailHeaderImageReuseTests.swift` (both `@MainActor struct` with async image-loading tests; symptom: under full-target parallel load, expectations like `cell.postImageView.image != nil` / failure-plate visibility fail; always green in isolation — observed 3× on 2026-07-06/07: `fullResSucceeds_showsNeitherPlateNorPill`, `fullResFailsWithoutThumbnail_showsPlateNotPill`, `voteReconfigure_keepsLoadedImage`).
- Modify: `SpudTests/SplitTabResolverTests.swift` — its `FakeDependencies` builds `PreferencesService()` on `.standard`; switch to `PreferencesService.ephemeral()` per the repo rule (SpudTests/EphemeralPreferences.swift).

**Method (Phase 1 before any fix):** read both suites' waiting/polling mechanics (how they await the async image pipeline — Task.sleep polling? yield loops?) and identify WHY parallel suite load starves them (main-actor contention vs a fixed timeout too short under load vs a shared fixture). Pick the matching fix, in preference order: (a) condition-based waiting with a generous deadline (replace fixed sleeps/iteration caps — the repo precedent is bounded sleep-polling "await until rendered or fail loudly"); (b) deterministic synchronous image-loader stubs that remove the async hop entirely where the test doesn't need real asynchrony; (c) `@Suite(.serialized)` ONLY if the starvation is genuinely inter-test main-actor contention that correct waiting cannot absorb — document why if chosen. Blanket-serializing without diagnosis is not acceptable.

**Gate:** the two suites green in isolation AND in 3 consecutive full `make test-only ONLY=SpudTests` runs (the flake reproduced roughly every other full run — 3 clean consecutive full-target runs is the acceptance evidence; note each run's result in the report).

- [ ] Steps: diagnose (report the mechanism with file:line) → RED-ish evidence if the mechanism permits (e.g. demonstrate the starvation with a tightened deadline) → fix → 3× full-target gate + `make build` → swiftformat → commit `test: harden header-image suites against parallel-load starvation` (+ the SplitTabResolver ephemeral change in the same commit or a separate `test:` commit, implementer's call).

### Task 3: SpudUITests environment hardening (added 2026-07-07 after the PersonProfile investigation)

**Background:** the three `test_PersonProfile_*` failures were environmental, NOT a main regression (they pass 3/3 at HEAD and at 11f948cb on clean runs). Two hardening items fell out of the investigation:

**Files:**
- Modify: `SpudUITests/SpudUITests.swift` — add `XCUIDevice.shared.orientation = .portrait` to the suite's `setUpWithError` (mirror `NodeInfoBlockUITests.swift:32`'s line + comment: device orientation is simulator-hardware state that survives across runs; the suite currently restores portrait only in `tearDown` (:106), so the FIRST test of a run inherits whatever orientation the sim was left in — reproduced: landscape makes the attribution link sit under the floating tab bar, `creatorLink.tap()` at :344 fails "not hittable").
- Modify: `SpudUITests/user-31989.json` — the 2023-era fixture cannot decode as `GetPersonDetailsResponse` under LemmyKit 0.5.1 (verified against generated Types.swift): `person_view` lacks required `is_admin`; each of `posts[]` lacks `banned_from_community`/`creator_is_moderator`/`creator_is_admin`/`hidden`; each of `comments[]` lacks `banned_from_community`/`creator_is_moderator`/`creator_is_admin`. Masked today only because the feed import pre-seeds person 31989 so the DB path bypasses the fetch; any future test hitting the loading path hangs at "Loading..." forever. Patch the missing required fields (values consistent with the fixture's existing data; follow the repo gotcha about cross-checking required fields).

**Gate:** the three `test_PersonProfile_*` tests + `test_PostDetail_TapOnPostCreator` green; plus one deliberate landscape-start run (rotate the sim landscape via `xcrun simctl` or a pre-step, then run the Person tests — first test must now pass thanks to the setUp pin; restore portrait after).

- [ ] Steps: fixture patch + setUp pin → focused UITest gate incl. the landscape-start run → swiftformat (no-op for JSON) → commit `test: pin portrait in SpudUITests setUp; repair stale person fixture` (explicit paths).

### Task 4: Gates + review + merge

- [ ] Docs: none expected (test-only branch; no user-facing behavior). Verify no docs/features claims reference the flaky suites.
- [ ] Final gates: `make test-only ONLY=SpudTests` + `ONLY=SpudDataKitTests` green; full `make snapshot` 261/261 (again, post-Task-2, zero ref changes); `mint run swiftformat --lint .` clean.
- [ ] Whole-branch review (fresh reviewer, most capable model): risk list = any ref-content drift smuggled in (verify zero `__Snapshots__` changes in the range), the flake fix actually addressing the diagnosed mechanism (not masking), traits classification table completeness (no `.image(size:traits:)` file missed), no device-config touched.
- [ ] ONE fix agent for findings; re-run gates.
- [ ] Merge protocol (workspace CLAUDE.md): re-check `main..worktree-test-hardening` + shared-checkout dirt overlap RIGHT BEFORE merging; `git annex restage` first; `--no-ff`. Push only on the user's explicit word.
