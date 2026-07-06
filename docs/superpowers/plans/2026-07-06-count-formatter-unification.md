# Count-formatter unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace seven divergent compact-count formatters with one `CountFormatter` (in SpudUtilKit, CompactCount style) used by the app, SpudDataKit, and the widget.

**Architecture:** Add `CountFormatter` to SpudUtilKit (the lowest, pure-Foundation layer, reachable by every target). Migrate every call site to it, then delete `CompactCount`, `CommentsFormatter`, both copies of `UpvotesFormatter`, `SummaryHeatmapCardView.formatCount`, and `DiscoverView.compact`, and rewrite the two `.compactName` sites. Wire `SpudUtilKit` into the widget so it can drop its duplicate `UpvotesFormatter`.

**Tech Stack:** Swift 6, XcodeGen (`make project` after any add/delete of source files), Swift Testing (unit), pointfreeco/swift-snapshot-testing (snapshots on iPhone 17 Pro / iOS 26.3.x).

## Global Constraints

- Canonical style = CompactCount's algorithm, verbatim: `< 1000` and negatives render verbatim; `1000..<1_000_000` → `K`; `>= 1_000_000` → `M`; decimal dropped when the abbreviated value is whole OR `>= 100`, else one decimal. Examples: `999`→`"999"`, `1000`→`"1K"`, `1234`→`"1.2K"`, `5000`→`"5K"`, `32000`→`"32K"`, `100000`→`"100K"`, `312000`→`"312K"`, `1000000`→`"1M"`, `1250000`→`"1.2M"`, `0`→`"0"`, `-5`→`"-5"`, `-5000`→`"-5000"`.
- The single formatter is `public enum CountFormatter` with `public static func string(_ value: Int64) -> String`, in `SpudUtilKit/CountFormatter.swift`. `Int` callers pass `Int64(x)`.
- Any file that references `CountFormatter` must `import SpudUtilKit` (the app, SpudDataKit, and — after Task 2 — the widget all link it).
- After ANY create/delete of a `.swift` file or edit to `project.yml`, run `make project` before building (XcodeGen regenerates the gitignored `.xcodeproj`). This worktree has no generated project yet, so the first `make project` also creates it.
- Keep `InstanceHealthStyle`'s `—` empty-value wrapper; only its inner formatter call changes. Do NOT touch timing/timestamp math (`ExplorerDTO`, `RequestRetry`).
- No emojis. Conventional commit subjects. Swift Testing suites are `struct` with `@Test`/`#expect`; `import Foundation` where a Foundation type (e.g. `String(format:)`) is used.
- Build/test commands (from the worktree root): `make project`; `make build` (app); `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudWidgetExtension` (widget); `make test-only ONLY=<Target>` (a unit-test target); `make snapshot` (snapshot plan, reference sim). All resolve the destination automatically.

---

## File Structure

- `SpudUtilKit/CountFormatter.swift` — **create.** The single public formatter.
- `SpudUtilKitTests/CountFormatterTests.swift` — **create.** Boundary tests.
- `project.yml` — **modify.** Add `- target: SpudUtilKit` to `SpudWidgetExtension.dependencies`.
- Widget: `SpudWidget/TopPosts/PostView.swift`, `PostViewSmall.swift`, `PostAccessoryRectangularView.swift`, `PostAccessoryInlineView.swift` — **modify** (import + call sites); `SpudWidget/UpvotesFormatter.swift` — **delete.**
- App: `Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift`, `Spud/Scenes/Onboarding/OnboardingHomeBaseViewController.swift`, `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`, `Spud/Utils/Formatters/IconValueFormatter.swift`, `Spud/Scenes/Person/Content/PersonViewModel.swift`, `Spud/Scenes/Community/Content/CommunityViewModel.swift`, `Spud/Scenes/Activity/Summary/SummaryHeatmapCardView.swift`, `Spud/Scenes/Discover/DiscoverView.swift`, `Spud/Scenes/Search/SearchResults.swift`, `Spud/Scenes/Account/SiteList/SiteListSiteViewModel.swift` — **modify**; `Spud/Utils/Formatters/CompactCount.swift`, `Spud/Utils/Formatters/UpvotesFormatter.swift` — **delete**; `SpudTests/CompactCountTests.swift` — **delete** (superseded by CountFormatterTests).
- SpudDataKit: `SpudDataKit/Services/AppDatabase/Summary/SummaryObservations.swift` — **modify**; `SpudDataKit/Utils/Formatters/CommentsFormatter.swift` — **delete.**
- Snapshot references under `SpudSnapshotTests/__Snapshots__/**` (and possibly `SpudMarkdownKitSnapshotTests`) — **re-record only those that change.**

---

### Task 1: Create `CountFormatter` + tests (SpudUtilKit)

**Files:**
- Create: `SpudUtilKit/CountFormatter.swift`
- Create: `SpudUtilKitTests/CountFormatterTests.swift`

**Interfaces:**
- Produces: `public enum CountFormatter { public static func string(_ value: Int64) -> String }` in module `SpudUtilKit`.

- [ ] **Step 1: Write the failing test.** Create `SpudUtilKitTests/CountFormatterTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudUtilKit

struct CountFormatterTests {
    @Test
    func compactBoundaries() {
        #expect(CountFormatter.string(0) == "0")
        #expect(CountFormatter.string(999) == "999")
        #expect(CountFormatter.string(1000) == "1K")
        #expect(CountFormatter.string(1234) == "1.2K")
        #expect(CountFormatter.string(5000) == "5K")
        #expect(CountFormatter.string(32000) == "32K")
        #expect(CountFormatter.string(100_000) == "100K")
        #expect(CountFormatter.string(312_000) == "312K")
        #expect(CountFormatter.string(1_000_000) == "1M")
        #expect(CountFormatter.string(1_250_000) == "1.2M")
    }

    @Test
    func negativesAndSmallRenderVerbatim() {
        #expect(CountFormatter.string(-5) == "-5")
        #expect(CountFormatter.string(-5000) == "-5000")
    }
}
```

- [ ] **Step 2: Generate the project and run the test to verify it fails.**

Run: `make project && make test-only ONLY=SpudUtilKitTests`
Expected: FAIL — compile error "cannot find 'CountFormatter' in scope" (the type does not exist yet).

- [ ] **Step 3: Create the formatter.** Create `SpudUtilKit/CountFormatter.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The single compact-count formatter for the whole app (app, data layer, and
/// widget). Renders "312", "1.2K", "32K", "1.2M": K/M suffixes, dropping the
/// decimal for whole values or when the abbreviated value is >= 100. Values
/// below 1000 and all negatives render verbatim.
public enum CountFormatter {
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

- [ ] **Step 4: Regenerate and run the test to verify it passes.**

Run: `make project && make test-only ONLY=SpudUtilKitTests`
Expected: PASS — look for `✔ Test run with N tests ... passed` (Swift Testing prints "Executed 0 tests" in the XCTest summary; trust the ✔ line).

- [ ] **Step 5: Commit.**

```bash
git add SpudUtilKit/CountFormatter.swift SpudUtilKitTests/CountFormatterTests.swift
git commit -m "feat: add CountFormatter compact-count formatter to SpudUtilKit"
```

---

### Task 2: Migrate the widget + drop its duplicate `UpvotesFormatter`

**Files:**
- Modify: `project.yml` (SpudWidgetExtension dependencies), `SpudWidget/TopPosts/PostView.swift`, `SpudWidget/TopPosts/PostViewSmall.swift`, `SpudWidget/TopPosts/PostAccessoryRectangularView.swift`, `SpudWidget/TopPosts/PostAccessoryInlineView.swift`
- Delete: `SpudWidget/UpvotesFormatter.swift`

**Interfaces:**
- Consumes: `CountFormatter.string(_:)` from Task 1.

- [ ] **Step 1: Add the SpudUtilKit dependency to the widget.** In `project.yml`, under the `SpudWidgetExtension:` target's `dependencies:` list (currently `- target: SpudDataKit` then `- target: SpudUIKit`), add a third line so it reads:

```yaml
    dependencies:
      - target: SpudDataKit
      - target: SpudUIKit
      - target: SpudUtilKit
```

- [ ] **Step 2: Migrate the widget call sites.** In each of `SpudWidget/TopPosts/PostView.swift`, `PostViewSmall.swift`, `PostAccessoryRectangularView.swift`, `PostAccessoryInlineView.swift`:
  - Add `import SpudUtilKit` (alongside the existing `import SpudDataKit`).
  - Replace every `UpvotesFormatter.string(from: X)` with `CountFormatter.string(X)`.
  - Replace every `CommentsFormatter.string(from: X)` with `CountFormatter.string(X)`.

  (`PostView.swift`, `PostViewSmall.swift`, `PostAccessoryRectangularView.swift` use both; `PostAccessoryInlineView.swift` uses `UpvotesFormatter` only. The transformation is purely dropping the `from:` label and switching the type name.)

- [ ] **Step 3: Delete the widget's duplicate formatter.**

```bash
git rm SpudWidget/UpvotesFormatter.swift
```

- [ ] **Step 4: Regenerate and build the widget.**

Run: `make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme SpudWidgetExtension`
Expected: BUILD SUCCEEDED, 0 errors. (`CommentsFormatter` still exists in SpudDataKit — the widget just no longer references it.)

- [ ] **Step 5: Verify no widget file still references the old formatters.**

Run: `grep -rn "UpvotesFormatter\|CommentsFormatter" SpudWidget`
Expected: no output.

- [ ] **Step 6: Commit.**

```bash
git add project.yml SpudWidget
git commit -m "refactor: widget uses CountFormatter, drop duplicate UpvotesFormatter"
```

---

### Task 3: Migrate all app call sites; delete `CompactCount` + app `UpvotesFormatter`

**Files:**
- Modify: `Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift`, `Spud/Scenes/Onboarding/OnboardingHomeBaseViewController.swift`, `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift`, `Spud/Utils/Formatters/IconValueFormatter.swift`, `Spud/Scenes/Person/Content/PersonViewModel.swift`, `Spud/Scenes/Community/Content/CommunityViewModel.swift`, `Spud/Scenes/Activity/Summary/SummaryHeatmapCardView.swift`, `Spud/Scenes/Discover/DiscoverView.swift`, `Spud/Scenes/Search/SearchResults.swift`, `Spud/Scenes/Account/SiteList/SiteListSiteViewModel.swift`
- Delete: `Spud/Utils/Formatters/CompactCount.swift`, `Spud/Utils/Formatters/UpvotesFormatter.swift`, `SpudTests/CompactCountTests.swift`

**Interfaces:**
- Consumes: `CountFormatter.string(_:)` from Task 1.

Apply these uniform replacements (all keep the same argument value; only the type/label/shape changes). Add `import SpudUtilKit` to any modified file that does not already import it (needed in: InstanceHealthStyle, OnboardingHomeBaseViewController, IconValueFormatter, PersonViewModel, SummaryHeatmapCardView, DiscoverView, SiteListSiteViewModel; already present in PostDetailCommentViewModel, CommunityViewModel, SearchResults).

- [ ] **Step 1: `CompactCount` sites.**
  - `InstanceHealthStyle.swift`: replace `CompactCount.string(value)` with `CountFormatter.string(value)` (keep the surrounding `—`-for-empty logic unchanged).
  - `OnboardingHomeBaseViewController.swift`: replace `CompactCount.string(members)` with `CountFormatter.string(members)`.

- [ ] **Step 2: `UpvotesFormatter` sites (app).**
  - `PostDetailCommentViewModel.swift`: replace `UpvotesFormatter.string(from: row.score)` with `CountFormatter.string(row.score)`.
  - `IconValueFormatter.swift`: replace `UpvotesFormatter.string(from: value)` with `CountFormatter.string(value)`.

- [ ] **Step 3: `CommentsFormatter` sites (app).** Replace every `CommentsFormatter.string(from: X)` with `CountFormatter.string(X)` in:
  - `PersonViewModel.swift` (posts, comments)
  - `CommunityViewModel.swift` (subscribers, posts, usersActiveWeek, usersActiveMonth)
  - `IconValueFormatter.swift` (the comments variant)

- [ ] **Step 4: `SummaryHeatmapCardView.formatCount`.** In `SummaryHeatmapCardView.swift`, replace the call `formatCount(total)` with `CountFormatter.string(Int64(total))` (`total` is an `Int`), and delete the entire `private func formatCount(_ count: Int) -> String { ... }` method.

- [ ] **Step 5: `DiscoverView.compact`.** In `DiscoverView.swift`, replace every call of the form `Self.compact(X)` and `DiscoverCommunityRow.compact(X)` with `CountFormatter.string(X)` (the arguments are already `Int64` fields — `numberOfSubscribers`, `usersActiveWeek`, `groupTotalSubscribers`, `totalSubscribers`, `totalActiveWeek`), then delete the `static func compact(_ value: Int64) -> String { ... }` method.

- [ ] **Step 6: `.compactName` sites.**
  - `SearchResults.swift`: replace `usersTotal.formatted(.number.notation(.compactName))` with `CountFormatter.string(usersTotal)` (`usersTotal` is `Int64`).
  - `SiteListSiteViewModel.swift`: replace the body of `abbreviatedCount(_ value: Int64)` — `value.formatted(.number.notation(.compactName))` — with `CountFormatter.string(value)` (and update the doc comment "locale-aware" → "compact").

- [ ] **Step 7: Delete the app formatters and their test.**

```bash
git rm Spud/Utils/Formatters/CompactCount.swift Spud/Utils/Formatters/UpvotesFormatter.swift SpudTests/CompactCountTests.swift
```

- [ ] **Step 8: Regenerate and build the app.**

Run: `make project && make build`
Expected: BUILD SUCCEEDED. (Only `CommentsFormatter` remains, referenced solely by `SummaryObservations` in SpudDataKit — removed in Task 4.)

- [ ] **Step 9: Verify no app file still references the deleted formatters.**

Run: `grep -rn "CompactCount\|UpvotesFormatter" Spud SpudTests`
Expected: no output. (`CommentsFormatter` may still appear only via SpudDataKit's own file — none should appear under `Spud/` or `SpudTests/`.)
Also run: `grep -rn "CommentsFormatter\|compactName" Spud` — expected: no output.

- [ ] **Step 10: Run the app-hosted unit tests and fix any changed count-string expectations.**

Run: `make test-only ONLY=SpudTests`
Expected: PASS. If a test asserts an old formatted string (e.g. a `"32.0K"` that is now `"32K"`), update the expected value to the new style and re-run. Snapshot suites are NOT part of this plan — they are re-recorded in Task 5.

- [ ] **Step 11: Commit.**

```bash
git add Spud SpudTests
git commit -m "refactor: app uses CountFormatter; remove CompactCount + app UpvotesFormatter"
```

---

### Task 4: Migrate SpudDataKit; delete `CommentsFormatter`

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Summary/SummaryObservations.swift`
- Delete: `SpudDataKit/Utils/Formatters/CommentsFormatter.swift`

**Interfaces:**
- Consumes: `CountFormatter.string(_:)` from Task 1 (SpudDataKit already depends on SpudUtilKit).

- [ ] **Step 1: Migrate `SummaryObservations`.** In `SpudDataKit/Services/AppDatabase/Summary/SummaryObservations.swift`, add `import SpudUtilKit` if not already present, and replace every `CommentsFormatter.string(from: X)` with `CountFormatter.string(X)` (the six sites: posts, comments, saved, votes, communities, read — some wrap `Int64(...)`; keep the existing `Int64(...)` conversion, e.g. `CountFormatter.string(Int64(voteCount))`).

- [ ] **Step 2: Delete the formatter.**

```bash
git rm SpudDataKit/Utils/Formatters/CommentsFormatter.swift
```

- [ ] **Step 3: Regenerate and build.**

Run: `make project && make build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify NO reference to any retired formatter remains anywhere.**

Run: `grep -rn "CompactCount\b\|CommentsFormatter\|UpvotesFormatter\|notation(\.compactName)" Spud SpudDataKit SpudWidget SpudUIKit SpudUtilKit --include='*.swift' | grep -v CountFormatter`
Expected: no output. (The only surviving formatter is `CountFormatter`.)

- [ ] **Step 5: Run the SpudDataKit unit tests and fix any changed count-string expectations.**

Run: `make test-only ONLY=SpudDataKitTests`
Expected: PASS. If `SummaryStatsTests` (or any other) asserts an old formatted count string that changed, update it to the new style and re-run. (Note: SpudDataKitTests has one known flaky offline network test — a lone rerun-passes failure is that flake, not this change.)

- [ ] **Step 6: Commit.**

```bash
git add SpudDataKit
git commit -m "refactor: SummaryObservations uses CountFormatter; remove CommentsFormatter"
```

---

### Task 5: Re-record affected snapshots + reconcile any docs

**Files:**
- Modify (re-record): specific references under `SpudSnapshotTests/__Snapshots__/**` (and, if any change, `SpudMarkdownKitSnapshotTests/__Snapshots__/**`)
- Possibly modify: a `docs/features/*.md` file that quotes a now-changed count string

**Interfaces:** none (verification + goldens).

This task runs on the reference simulator (iPhone 17 Pro / iOS 26.3.x). Respect the single-booted-sim rule and the git-annex ceremony (`SpudSnapshotTests/CLAUDE.md`): re-record ONE class at a time, never `git annex restage` between a record and its verify, and `git add` only the explicit refs you re-recorded.

- [ ] **Step 1: Run the snapshot plan in verify mode to get the authoritative changed-ref list.**

Run: `make snapshot`
Expected: FAILURES on any snapshot whose rendered count string changed (e.g. Community/Person/Activity/Discover/Search/SiteList/Instance/PostList/widget). Capture the authoritative failing list from the xcresult (`xcrun xcresulttool get test-results tests --path <bundle>` — walk `testNodes` for `result=="Failed"`), NOT by grepping stdout.

- [ ] **Step 2: Separate real changes from ambient drift.** For any failing class that seems unrelated to count formatting, confirm causation with a stash-control: `git stash push -- <the swift files changed in Tasks 1-4>` is NOT possible after commit — instead compare against `main`: check out the ref's pre-change bytes are drift by running that one class against `origin`/`main`. In practice: a failure on a class that renders a count is this change; a failure on an unrelated class (or the known pre-existing `DiagnosticLog`/`mediaComment` drift) is not — leave those untouched. When unsure, image-diff (a size change is a formatter/layout change; pure anti-alias drift is ambient).

- [ ] **Step 3: Re-record only the changed refs, one class at a time.** For each confirmed class: `rm` its changed `.png` refs, run that class (records missing + fails), rerun (verifies green). Example:

```bash
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
rm SpudSnapshotTests/__Snapshots__/<Class>/<changed refs>.png
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/<Class> \
  -destination "platform=iOS Simulator,id=$SIM" \
  -skipPackagePluginValidation -skipMacroValidation test   # records + fails
xcodebuild ... -only-testing:SpudSnapshotTests/<Class> ... test   # verifies green
git add SpudSnapshotTests/__Snapshots__/<Class>/<changed refs>.png
```

- [ ] **Step 4: Full snapshot verify.**

Run: `make snapshot`
Expected: PASS (except any pre-existing ambient-drift refs you deliberately left, which must be the SAME set that failed before Task 1 — not new).

- [ ] **Step 5: Reconcile docs if needed.**

Run: `grep -rnE '"[0-9]+\.[0-9](K|M)"|[0-9]+\.0K' docs/features`
If a feature doc quotes a specific count string this change alters, update it to the new style. If none, no docs change (count formatting has no dedicated feature doc).

- [ ] **Step 6: Commit.**

```bash
git add SpudSnapshotTests/__Snapshots__   # only the explicit refs staged in Step 3
git commit -m "test: re-record snapshots for unified CountFormatter output"
```

---

## Self-Review

**1. Spec coverage:**
- One `CountFormatter` in SpudUtilKit, CompactCount style → Task 1. ✓
- Retire CompactCount → Task 3; CommentsFormatter → Tasks 2/3/4 (all call sites) + delete Task 4; both UpvotesFormatter copies → Task 2 (widget) + Task 3 (app); SummaryHeatmap.formatCount → Task 3; DiscoverView.compact → Task 3; .compactName ×2 → Task 3. ✓
- Widget SpudUtilKit wiring + duplicate deletion → Task 2. ✓
- Keep `—` wrapper; skip timing math → Global Constraints + Task 3 Step 1. ✓
- SpudUtilKitTests boundaries → Task 1. ✓ Existing formatter tests updated/removed → Task 3 (CompactCountTests deleted), Task 3 Step 10 + Task 4 Step 5 (assertion fixes). ✓
- Build app + widget → Task 3 Step 8, Task 2 Step 4. ✓
- Snapshot re-records (bounded, verify-first) → Task 5. ✓
- Docs reconciliation (only if a quoted string changed) → Task 5 Step 5. ✓

**2. Placeholder scan:** Task 5's re-record step uses `<Class>`/`<changed refs>` as loop variables over the authoritative failing list (unavoidable — the exact set is data-dependent and discovered in Step 1), not as unfilled placeholders; the method to obtain them is exact. All code steps show complete code. No TBD/TODO.

**3. Type consistency:** `CountFormatter.string(_ value: Int64) -> String` is used identically in every task. `Int` sites (`SummaryHeatmapCardView` `total`) use `Int64(total)`; `Int64` sites (Discover fields, `usersTotal`, SiteList `value`, `row.score`, `record.*`) pass directly. The retired symbols (`CompactCount`, `CommentsFormatter`, `UpvotesFormatter`, `formatCount`, `compact`) each have a delete step gated behind migrating their call sites, and Task 4 Step 4 greps the whole tree to prove none survive.
