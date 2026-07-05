# Reflect & Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the standing footguns and highest-value duplication found by the 2026-07-05 architecture/tests/ergonomics/retrospective audit, without changing user-visible behavior.

**Architecture:** Pure hygiene + behavior-preserving extractions. New shared helpers (`OutboxBackoff`, `CompactCount`, `PostActions` protocol) follow existing precedents (`OutboxFailureClass` sharing, `InternalLinkRouting` protocol-per-VC, `LemmyService+Moderation` extension split). No schema-visible behavior changes except one additive migration dropping the dead `nodeInfo` table.

**Tech Stack:** Swift 6 / strict concurrency, UIKit, GRDB, Swift Testing (unit), XCTest (snapshots/UITests), XcodeGen, SwiftFormat via Mint.

## Global Constraints

- Zero user-visible behavior change (strings, haptics, ordering byte-identical) — except nothing: this plan has NO user-visible changes.
- No emojis anywhere. Conventional commit subjects. Small focused commits.
- Swift Testing for unit tests (`struct` suites, `@Test`, `#expect`); no `test` prefix on methods.
- After adding/removing source files: `make project` before building (XcodeGen).
- Run `mint run swiftformat <changed paths>` BEFORE the final test verify of each task.
- Build/test via `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud` (add `--simulator "iPhone 17"` for framework schemes); fall back to `xcodebuild -project Spud.xcodeproj ... -skipPackagePluginValidation -skipMacroValidation`.
- SpudDataKitTests via: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests -destination 'platform=iOS Simulator,id=<booted-sim-id>' -skipPackagePluginValidation -skipMacroValidation test` (resolve booted sim id via `xcrun simctl list devices | grep Booted`).
- Do NOT touch anything under `SpudSnapshotTests/__Snapshots__/` (git-annex refs) — no task in this plan changes rendered output.
- Commit from THIS worktree only; verify `git branch --show-current` == `worktree-reflect-refactor` before each commit.

---

### Task 1: Makefile test/build targets + destination resolver script

**Files:**
- Create: `scripts/resolve-test-destination.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces: `make build`, `make test`, `make test-only ONLY=<target>`, `make snapshot` — used by all later tasks and documented in Task 11.

**Why:** The OS pin (26.3 vs 26.3.1 contradiction in CLAUDE.md), the plugin-skip flags, the single-booted-sim rule, and booted-sim-by-id targeting currently live only as prose gotchas. Encode them in one script so agents stop re-deriving them.

- [ ] **Step 1: Write `scripts/resolve-test-destination.sh`**

```sh
#!/bin/sh
# Resolve an xcodebuild -destination for simulator test runs, encoding the
# rules that used to live as prose in CLAUDE.md:
#   - If a simulator is already booted, target it BY ID (never boot a second
#     sim by name: two booted sims cause "SBMainWorkspace Busy" test failures).
#   - Otherwise resolve the reference device (iPhone 17 Pro) on the newest
#     iOS 26.3.x runtime by UUID (the OS string alone drifts across minor
#     runtime updates: 26.3 vs 26.3.1).
#   - With --reference, additionally FAIL if the booted sim is not the
#     reference device: app-level snapshot references only match on
#     iPhone 17 Pro / iOS 26.3.x.
#
# Prints "platform=iOS Simulator,id=<UUID>" on stdout; exits non-zero with a
# hint on stderr if no suitable simulator exists.

set -eu

want_reference=false
[ "${1:-}" = "--reference" ] && want_reference=true

devices=$(xcrun simctl list devices)

booted_line=$(printf '%s\n' "$devices" | grep "(Booted)" | head -1 || true)
if [ -n "$booted_line" ]; then
    booted_id=$(printf '%s\n' "$booted_line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
    if $want_reference; then
        case "$booted_line" in
            *"iPhone 17 Pro "*) ;;
            *)
                echo "error: booted simulator is not the snapshot reference device (iPhone 17 Pro)." >&2
                echo "hint: shut it down (xcrun simctl shutdown all) or boot the reference sim first." >&2
                exit 1
                ;;
        esac
    fi
    echo "platform=iOS Simulator,id=$booted_id"
    exit 0
fi

# No booted sim: resolve the reference device on the newest 26.3.x runtime.
ref_id=$(printf '%s\n' "$devices" \
    | awk '/-- iOS 26\.3/{run=1; next} /^--/{run=0} run && /iPhone 17 Pro \(/ {print}' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1 || true)
if [ -z "$ref_id" ]; then
    echo "error: no iPhone 17 Pro simulator on an iOS 26.3.x runtime found." >&2
    echo "hint: xcrun simctl list devices | grep 'iPhone 17 Pro'" >&2
    exit 1
fi
echo "platform=iOS Simulator,id=$ref_id"
```

Then `chmod +x scripts/resolve-test-destination.sh`.

- [ ] **Step 2: Verify the script by hand**

Run: `scripts/resolve-test-destination.sh` and `scripts/resolve-test-destination.sh --reference`
Expected: each prints `platform=iOS Simulator,id=<UUID>` (or a clear error if a non-reference sim is booted for `--reference`).

- [ ] **Step 3: Add Makefile targets**

Append to `Makefile` (and add `build test test-only snapshot` to `.PHONY`):

```make
# Common xcodebuild invocation pieces. The plugin/macro skip flags are required
# for non-interactive builds (LemmyKit pulls in swift-openapi-generator's
# build-tool plugin, which xcodebuild won't validate headlessly).
XCB_FLAGS := -skipPackagePluginValidation -skipMacroValidation
TEST_DEST = $(shell scripts/resolve-test-destination.sh)
SNAPSHOT_DEST = $(shell scripts/resolve-test-destination.sh --reference)

# Build the app for the booted (or reference) simulator.
build:
	xcodebuild -project Spud.xcodeproj -scheme Spud -destination '$(TEST_DEST)' $(XCB_FLAGS) build

# Run the full Spud unit-test plan. Timeouts make a deadlocked Swift Testing
# test fail-and-name instead of hanging forever.
test:
	xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
	  -destination '$(TEST_DEST)' $(XCB_FLAGS) \
	  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 test

# Run a single test target from the Spud plan: make test-only ONLY=SpudDataKitTests
test-only:
	xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
	  -only-testing:$(ONLY) \
	  -destination '$(TEST_DEST)' $(XCB_FLAGS) \
	  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 test

# Run the snapshot plan on the pinned reference device (iPhone 17 Pro /
# iOS 26.3.x). Fails fast if a different simulator is booted.
snapshot:
	xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
	  -destination '$(SNAPSHOT_DEST)' $(XCB_FLAGS) test
```

Note: recipes use TABS, not spaces.

- [ ] **Step 4: Verify `make build` completes**

Run: `make build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Makefile scripts/resolve-test-destination.sh
git commit -m "chore: add make build/test/snapshot targets + destination resolver"
```

---

### Task 2: Blocking pre-commit, drop the isEmpty SwiftFormat rule, untrack .remember

**Files:**
- Modify: `scripts/git-hooks/pre-commit`
- Modify: `.swiftformat`
- Modify: `.gitignore`
- Delete (from index only): `.remember/remember.md`

- [ ] **Step 1: Make the pre-commit hook block on lint failure**

Replace `scripts/git-hooks/pre-commit` content with:

```sh
#!/bin/sh

# Spud.xcodeproj is generated by XcodeGen and gitignored, so there is no
# tracked project.pbxproj to sort. The project is the source of truth in
# project.yml; regenerate with `xcodegen generate` / `make project`.

# SwiftFormat lint gate: a formatting violation blocks the commit.
# Fix with: mint run swiftformat <paths>
if ! mint run swiftformat --lint . ; then
    echo "" >&2
    echo "pre-commit: SwiftFormat lint failed. Run 'mint run swiftformat .' and re-stage." >&2
    exit 1
fi
```

- [ ] **Step 2: Remove the isEmpty rule from `.swiftformat`**

Delete the line `--enable isEmpty`. Leave existing `// swiftformat:disable:next isEmpty` guard comments in the codebase alone (harmless no-ops).

- [ ] **Step 3: Verify the tree is already clean under the new rule set**

Run: `mint run swiftformat --lint . ; echo "exit=$?"`
Expected: `exit=0` (removing an --enable rule never introduces new violations).

- [ ] **Step 4: Untrack `.remember/`**

```bash
git rm --cached -r .remember
printf '\n# Session-handoff buffer (per-machine, never committed)\n.remember/\n' >> .gitignore
```

Then re-enable untracked-file display for this repo (it was set to hide untracked files largely because of this buffer):

```bash
git config --unset status.showUntrackedFiles || true
```

- [ ] **Step 5: Verify**

Run: `git status --short`
Expected: `.remember/` no longer listed as tracked-modified; untracked files now visible; `.gitignore` modified.

- [ ] **Step 6: Commit**

```bash
git add .gitignore .swiftformat scripts/git-hooks/pre-commit
git commit -m "chore: blocking pre-commit lint, drop isEmpty rule, untrack .remember"
```

(The `git rm --cached` deletion of `.remember/remember.md` is staged already by Step 4; include it in this commit.)

---

### Task 3: Delete NodeInfo dead code (+ drop migration)

**Files:**
- Delete: `SpudDataKit/Utils/NodeInfoSoftware.swift`
- Delete: `SpudDataKit/Services/AppDatabase/Records/NodeInfoRecord.swift`
- Modify: `SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift` (append new migration; do NOT edit existing ones)
- Test: `SpudDataKitTests/` (existing migration tests must stay green)

**Interfaces:**
- Produces: migration `v29_dropNodeInfo` (or the next free `vNN` — check with `grep registerMigration SpudDataKit/Services/AppDatabase/AppDatabase+Migrations.swift | tail -1` and use latest+1).

- [ ] **Step 1: Verify the code is truly dead**

Run: `grep -rn "NodeInfo\|nodeInfo" --include="*.swift" Spud SpudDataKit SpudUIKit SpudUtilKit SpudMarkdownKit SpudWidget Shared OpenInAppExtension OpenInSpudAction | grep -v "AppDatabase+Migrations.swift" | grep -v "NodeInfoSoftware.swift" | grep -v "NodeInfoRecord.swift"`
Expected: no output. If ANY hit appears, STOP and report instead of deleting.

- [ ] **Step 2: Delete the two files, append the drop migration**

```bash
git rm SpudDataKit/Utils/NodeInfoSoftware.swift SpudDataKit/Services/AppDatabase/Records/NodeInfoRecord.swift
```

Append as the LAST registration in `AppDatabase+Migrations.swift` (adjust `vNN` per Interfaces note):

```swift
        // The nodeInfo table was written by a Diaspora NodeInfo prototype that
        // never shipped a reader; the record types are gone. Drop the table.
        migrator.registerMigration("v29_dropNodeInfo") { db in
            try db.drop(table: "nodeInfo")
        }
```

- [ ] **Step 3: Regenerate project, build, run DB tests**

Run: `make project && make test-only ONLY=SpudDataKitTests 2>&1 | tail -5`
Expected: build succeeds; `Test run with N tests ... passed` (look for the Swift Testing summary line, not XCTest's "Executed N tests").

- [ ] **Step 4: Commit**

```bash
git add -A SpudDataKit
git commit -m "refactor: delete dead NodeInfo record/util, drop nodeInfo table"
```

---

### Task 4: Add missing unit targets to the Spud test plan

**Files:**
- Modify: `Spud.xctestplan`
- Maybe modify: `project.yml` (only if the scheme's testTargets list needs the two targets added for the plan to resolve them)

**Why:** `SpudUIKitTests` and `SpudMarkdownKitTests` only run via their own schemes today — "run the tests" silently skips two targets.

- [ ] **Step 1: Add the two targets to `Spud.xctestplan`**

Append to the `testTargets` array (identifiers are XcodeGen-generated — after `make project`, copy the exact `identifier` values for `SpudUIKitTests` and `SpudMarkdownKitTests` from another generated reference; if identifiers prove brittle, the correct fix is adding the targets to the scheme's test action in `project.yml` and regenerating):

```json
    {
      "target" : {
        "containerPath" : "container:Spud.xcodeproj",
        "identifier" : "<SpudUIKitTests identifier>",
        "name" : "SpudUIKitTests"
      }
    },
    {
      "target" : {
        "containerPath" : "container:Spud.xcodeproj",
        "identifier" : "<SpudMarkdownKitTests identifier>",
        "name" : "SpudMarkdownKitTests"
      }
    }
```

Check `project.yml`'s `schemes.Spud.test` section first — if test targets are declared there, add the two targets there instead/as well, then `make project`. The generated-identifier question resolves itself if the scheme is the source of truth.

- [ ] **Step 2: Verify both targets run in the plan**

Run: `make test-only ONLY=SpudUIKitTests 2>&1 | tail -5` and `make test-only ONLY=SpudMarkdownKitTests 2>&1 | tail -5`
Expected: each reports a passing Swift Testing run (no "isn't a member of the specified test plan" error).

- [ ] **Step 3: Commit**

```bash
git add Spud.xctestplan project.yml
git commit -m "test: run SpudUIKitTests + SpudMarkdownKitTests in the Spud test plan"
```

---

### Task 5: Unify the outbox exponential backoff

**Files:**
- Create: `SpudDataKit/Services/Outbox/OutboxBackoff.swift`
- Create: `SpudDataKitTests/OutboxBackoffTests.swift`
- Modify: `SpudDataKit/Services/Outbox/OutboxService.swift:207,299` (call site + delete `backoffDelay`)
- Modify: `SpudDataKit/Services/Outbox/ComposerOutboxService.swift:305,381` (call site + delete `composerBackoffDelay`)
- Modify: `SpudDataKitTests/ComposerOutboxServiceTests.swift:207-209` (retarget assertions)

**Interfaces:**
- Produces: `enum OutboxBackoff { public static func delay(attempts: Int64) -> Double }` in SpudDataKit. (Match `ComposerOutboxService.composerBackoffDelay`'s current `public` visibility so the test target keeps compiling regardless of `@testable`.)

- [ ] **Step 1: Write the failing test**

`SpudDataKitTests/OutboxBackoffTests.swift`:

```swift
import Foundation
import Testing
@testable import SpudDataKit

struct OutboxBackoffTests {
    @Test
    func delay_doublesAndCaps() {
        #expect(OutboxBackoff.delay(attempts: 1) == 2)
        #expect(OutboxBackoff.delay(attempts: 2) == 4)
        #expect(OutboxBackoff.delay(attempts: 3) == 8)
        #expect(OutboxBackoff.delay(attempts: 0) == 2) // clamped
        #expect(OutboxBackoff.delay(attempts: 20) == 300) // capped
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `make project && make test-only ONLY=SpudDataKitTests/OutboxBackoffTests 2>&1 | tail -5`
Expected: compile FAILURE ("cannot find 'OutboxBackoff' in scope").

- [ ] **Step 3: Implement `OutboxBackoff` and retarget both services**

`SpudDataKit/Services/Outbox/OutboxBackoff.swift`:

```swift
import Foundation

/// Shared retry back-off curve for BOTH durable outboxes (`OutboxService` /
/// `ComposerOutboxService`): exponential doubling from 2s, capped at 300s.
/// The two outboxes intentionally share failure classification
/// (`OutboxFailureClass`) and pacing — tune the curve HERE so they cannot
/// silently diverge.
public enum OutboxBackoff {
    public static func delay(attempts: Int64) -> Double {
        min(2.0 * pow(2.0, Double(max(0, attempts - 1))), 300)
    }
}
```

In `OutboxService.swift`: replace the `backoffDelay(attempts:)` call at line 207 with `OutboxBackoff.delay(attempts: record.attempts + 1)` and DELETE the `func backoffDelay` (lines 299-301).
In `ComposerOutboxService.swift`: replace `Self.composerBackoffDelay(attempts: attempts)` at line 305 with `OutboxBackoff.delay(attempts: attempts)` and DELETE `public static func composerBackoffDelay` (lines 381-383).
In `ComposerOutboxServiceTests.swift:207-209`: replace `ComposerOutboxService.composerBackoffDelay(` with `OutboxBackoff.delay(`.

- [ ] **Step 4: Run the full outbox test set**

Run: `make test-only ONLY=SpudDataKitTests 2>&1 | tail -5`
Expected: PASS (all suites — the outbox drain tests exercise the changed call sites).

- [ ] **Step 5: SwiftFormat + commit**

```bash
mint run swiftformat SpudDataKit/Services/Outbox SpudDataKitTests/OutboxBackoffTests.swift SpudDataKitTests/ComposerOutboxServiceTests.swift
git add SpudDataKit/Services/Outbox SpudDataKitTests/OutboxBackoffTests.swift SpudDataKitTests/ComposerOutboxServiceTests.swift
git commit -m "refactor: unify outbox backoff curve in shared OutboxBackoff"
```

---

### Task 6: Dedupe the byte-identical compact-count formatter

**Files:**
- Create: `Spud/Utils/Formatters/CompactCount.swift`
- Create: `SpudTests/CompactCountTests.swift`
- Modify: `Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift:50-66` (delegate; keep its nil/zero → "—" wrapper)
- Modify: `Spud/Scenes/Onboarding/OnboardingHomeBaseViewController.swift:388-405` (delete `compactCount` + `trim`, call shared)

**Interfaces:**
- Produces: `enum CompactCount { static func string(_ value: Int64) -> String }` in the Spud app target.

**Scope guard:** ONLY the two byte-identical copies. Do NOT touch `CommentsFormatter`, `SummaryHeatmapCardView.formatCount`, or `.formatted(.number.notation(.compactName))` call sites — unifying their differing output styles changes rendered strings and churns snapshot refs (deliberate follow-up, see the follow-up specs doc).

- [ ] **Step 1: Write the failing test**

`SpudTests/CompactCountTests.swift`:

```swift
import Testing
@testable import Spud

struct CompactCountTests {
    @Test
    func string_matchesExistingCompactStyle() {
        #expect(CompactCount.string(312) == "312")
        #expect(CompactCount.string(1000) == "1K")
        #expect(CompactCount.string(1234) == "1.2K")
        #expect(CompactCount.string(32_000) == "32K")
        #expect(CompactCount.string(120_000) == "120K")
        #expect(CompactCount.string(1_200_000) == "1.2M")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `make project && make test-only ONLY=SpudTests/CompactCountTests 2>&1 | tail -5`
Expected: compile FAILURE ("cannot find 'CompactCount' in scope").

- [ ] **Step 3: Implement + delegate both call sites**

`Spud/Utils/Formatters/CompactCount.swift`:

```swift
import Foundation

/// Compact count formatting shared by instance-health chips and onboarding
/// member counts, e.g. "312", "1.2K", "32K", "1.2M".
///
/// Deliberately NOT unified with `CommentsFormatter` (K-only style) or the
/// Activity heatmap's formatter — their output styles differ and are pinned
/// by snapshot references; see docs/superpowers/specs/2026-07-05-follow-ups.md.
enum CompactCount {
    static func string(_ value: Int64) -> String {
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

`InstanceHealthStyle.formatCount` becomes:

```swift
    /// Compact count (e.g. "1.2K", "32K"). Returns "—" for nil/zero.
    static func formatCount(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return CompactCount.string(value)
    }
```

(delete its private `trim`). In `OnboardingHomeBaseViewController`: delete `private static func compactCount` and `private static func trim`; replace the single call `Self.compactCount(members)` with `CompactCount.string(members)`.

- [ ] **Step 4: Run tests + affected suites**

Run: `make test-only ONLY=SpudTests 2>&1 | tail -5`
Expected: PASS (includes the new suite; instance-detail/onboarding snapshot refs are NOT run here and are unaffected because output is byte-identical).

- [ ] **Step 5: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Utils/Formatters Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift Spud/Scenes/Onboarding/OnboardingHomeBaseViewController.swift SpudTests/CompactCountTests.swift
git add Spud/Utils/Formatters Spud/Scenes/Account/InstanceDetail/Components/InstanceHealthStyle.swift Spud/Scenes/Onboarding/OnboardingHomeBaseViewController.swift SpudTests/CompactCountTests.swift
git commit -m "refactor: share compact-count formatter between instance health and onboarding"
```

---

### Task 7: Extract shared post-actions dispatch (vote/save/swipe)

**Files:**
- Create: `Spud/Utils/PostActions.swift`
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` (~1622-1670 + `performSwipeAction` near 1416)
- Modify: `Spud/Scenes/Person/Content/PersonViewController.swift` (~853-920)
- Modify: `Spud/Scenes/Activity/ActivityViewController.swift` (~810-830)

**Interfaces:**
- Produces: `@MainActor protocol PostActionDispatching: UIViewController` with default implementations. Precedent: `InternalLinkRouting` (protocol implemented per-VC with shared behavior).

**Scope guard:** PostList, Person, Activity ONLY. Leave `PostDetailViewController`'s post/comment variants alone in this task (its saved-state lookup and comment-vote paths differ; folding it in is part of the VC→VM follow-up). Strings, comments, and haptic calls must move VERBATIM — a changed user-facing string is a task failure.

- [ ] **Step 1: Write the shared protocol**

`Spud/Utils/PostActions.swift`:

```swift
import LemmyKit
import SpudDataKit
import SpudUIKit
import UIKit

/// Shared post-action dispatch (vote / save) for every screen that shows a
/// post row (feed, person profile, activity). All paths route through the
/// per-account optimistic `LemmyService` calls (the durable outbox), never a
/// direct network write, so feed parity is structural rather than copy-pasted.
///
/// Conformers supply the per-screen bits: the account scope, the current
/// saved state for a post, and the sign-in gate presenter (every conformer
/// already has `presentSignInGate(title:)` and `alertService`).
@MainActor
protocol PostActionDispatching: UIViewController {
    var postActionsAccountScope: AccountScope { get }
    var postActionsAlertService: AlertServiceType { get }
    /// Currently observed saved state for the post (used by save-toggle).
    func currentSavedState(serverPostId: Int64) -> Bool
    func presentSignInGate(title: String)
}

@MainActor
extension PostActionDispatching {
    /// Votes on the post through the per-account optimistic outbox path (the
    /// same `lemmyService.vote` the feed calls): the local write applies
    /// synchronously and flows back through the row observation; network
    /// failures are retried by the outbox.
    func vote(serverPostId: Int64, action: VoteStatus.Action) async {
        guard !postActionsAccountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to vote", comment: "Sign-in gate title when a signed-out user tries to vote")
            )
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        do {
            try await postActionsAccountScope.lemmyService
                .vote(serverPostId: Components.Schemas.PostID(serverPostId), vote: action)
        } catch {
            // The optimistic write already applied synchronously inside enqueue;
            // network failures are retried by the outbox and surfaced via toast.
            // This catch is now a defensive log only.
            postActionsAlertService.handle(error, for: .vote)
        }
    }

    /// Toggles the saved state for `serverPostId` against its currently
    /// observed value, gating on sign-in.
    func toggleSaved(serverPostId: Int64) {
        guard !postActionsAccountScope.isSignedOut else {
            presentSignInGate(
                title: NSLocalizedString("Sign in to save", comment: "Sign-in gate title when a signed-out user tries to save a post")
            )
            return
        }
        let currentlySaved = currentSavedState(serverPostId: serverPostId)
        Task { await setSaved(serverPostId: serverPostId, saved: !currentlySaved) }
    }

    func setSaved(serverPostId: Int64, saved: Bool) async {
        Haptics.tap()
        do {
            try await postActionsAccountScope.lemmyService
                .setSaved(serverPostId: Components.Schemas.PostID(serverPostId), saved: saved)
        } catch {
            postActionsAlertService.handle(error, for: .save)
        }
    }
}
```

NOTE for the implementer: verify exact types before building — `AlertServiceType`'s `handle(_:for:)` category enum cases (`.vote`, `.save`), `VoteStatus.Action`, and `AccountScope` are used exactly as the current per-VC copies use them; if the real signatures differ, match the EXISTING call sites, not this sketch.

- [ ] **Step 2: Conform the three VCs, delete their private copies**

Per VC:
- Add `PostActionDispatching` conformance in an extension.
- `postActionsAccountScope`: PostList/Person return `viewModel.accountScope`; Activity returns `accountService.scope(forAccountKeychainId: accountKeychainId)`.
- `postActionsAlertService`: return the existing `alertService` dependency accessor.
- `currentSavedState(serverPostId:)`: PostList/Person return `rowsByServerPostId[serverPostId]?.isSaved ?? false`; Activity (no save path today) returns `false` with a comment.
- DELETE the now-shadowed private `vote`/`toggleSaved`/`setSaved` from each VC. Keep each VC's `performSwipeAction`, `replyToPost`, `sharePost` in place (they call the shared methods now).
- Person's doc comment "feed parity … the SAME per-account optimistic `LemmyService` calls" moves to the protocol doc (already there); delete the stale copy.

- [ ] **Step 3: Build + full app-target tests**

Run: `make project && make test-only ONLY=SpudTests 2>&1 | tail -5`
Expected: BUILD SUCCEEDED, all SpudTests pass.

- [ ] **Step 4: Byte-identical string check**

Run: `grep -rn "Sign in to vote\|Sign in to save" Spud/ | wc -l` before and after — the total must only DROP by the number of deleted duplicates; the remaining strings (incl. PostDetail's) unchanged.

- [ ] **Step 5: SwiftFormat + commit**

```bash
mint run swiftformat Spud/Utils/PostActions.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Activity/ActivityViewController.swift
git add Spud/Utils/PostActions.swift Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/Person/Content/PersonViewController.swift Spud/Scenes/Activity/ActivityViewController.swift
git commit -m "refactor: shared PostActionDispatching for vote/save across feed, person, activity"
```

---

### Task 8: Split LemmyService into extension files

**Files:**
- Create: `SpudDataKit/Services/Lemmy/LemmyService+Inbox.swift`
- Create: `SpudDataKit/Services/Lemmy/LemmyService+Safety.swift`
- Create: `SpudDataKit/Services/Lemmy/LemmyService+Composer.swift`
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift`

**Precedent:** `LemmyService+Moderation.swift` (277 lines) — copy its file-header/doc style exactly.

**Motion map (pure code motion, zero edits to bodies):**
- `LemmyService.swift` actor MARK `Safety (block / report)` (starts line 1878) → `LemmyService+Safety.swift`
- actor MARK `Composer outbox` (starts line 2229) → `LemmyService+Composer.swift`
- actor MARK `Inbox` (starts line 2406, runs to end of actor) → `LemmyService+Inbox.swift`
- The `LemmyServiceType` PROTOCOL (lines 42-620) stays whole in `LemmyService.swift` (protocol requirements cannot live in extensions).

**Access-level rule:** if a moved method calls a `private` member of the main file (e.g. a `mirror*ToAppDatabase` helper, `diagnosticLog`, `api`), do NOT weaken it blindly: prefer keeping truly-shared helpers in the main file and raising their access to `internal` ONLY when required, each with a one-line comment `// internal: shared with LemmyService+<X>`. `private` members of the same TYPE are not visible across files — expect several of these.

- [ ] **Step 1: Move the three MARK sections into extension files**

Each new file:

```swift
import Foundation
import GRDB
import LemmyKit
import os.log
import SpudUtilKit

// MARK: - <Section name>

extension LemmyService {
    // moved bodies, verbatim
}
```

(Match `LemmyService+Moderation.swift`'s exact import list and header comment style — read it first.)

- [ ] **Step 2: Regenerate + build + full SpudDataKitTests**

Run: `make project && make test-only ONLY=SpudDataKitTests 2>&1 | tail -5`
Expected: PASS. The inbox/safety/composer LemmyService test suites exercise every moved method.

- [ ] **Step 3: Diff sanity — confirm pure motion**

Run: `git diff --stat` — `LemmyService.swift` shrinks by ≈ the sum of the three new files (± imports/headers). Spot-check with `git diff SpudDataKit/Services/Lemmy/LemmyService.swift | grep "^+" | grep -v "^+++" | grep -v "internal: shared" | head` — expected: essentially no added lines in the main file.

- [ ] **Step 4: SwiftFormat + commit**

```bash
mint run swiftformat SpudDataKit/Services/Lemmy
git add SpudDataKit/Services/Lemmy
git commit -m "refactor: split LemmyService inbox/safety/composer into extension files"
```

---

### Task 9: Consolidate SpudDataKitTests' makeService copies

**Files:**
- Create: `SpudDataKitTests/Helpers/LemmyServiceHarness.swift`
- Modify: every `SpudDataKitTests/LemmyService*Tests.swift` file with a private `makeService` (~27 files — enumerate with `grep -l "func makeService" SpudDataKitTests`)

**Interfaces:**
- Produces (match the EXACT signature/shape of the existing copies — read `LemmyServiceSaveTests.swift:127-135` and `LemmyServiceSubscribeTests.swift:93-101` first; the canonical form is):

```swift
import Foundation
import LemmyKit
import OpenAPIRuntime
@testable import SpudDataKit

/// Canonical `LemmyService` builder for tests: fake instance URL + JWT,
/// injectable transport. Replaces ~27 identical private `makeService` copies.
@MainActor
enum LemmyServiceHarness {
    // Copy the body of the existing private makeService VERBATIM here as
    // `static func make(...)`, preserving every parameter and default.
}
```

- [ ] **Step 1: Read 3 existing copies; extract the superset signature into the helper**
- [ ] **Step 2: Migrate all files mechanically** — replace each private `makeService(` definition with nothing and each call `makeService(` with `LemmyServiceHarness.make(`. If a file's copy has a real semantic difference (different instance URL, extra seeding), LEAVE that file alone and note it in the commit message.
- [ ] **Step 3: Run**: `make project && make test-only ONLY=SpudDataKitTests 2>&1 | tail -5` — Expected: PASS, identical test count to baseline.
- [ ] **Step 4: SwiftFormat + commit**

```bash
mint run swiftformat SpudDataKitTests
git add SpudDataKitTests
git commit -m "test: consolidate LemmyService test builders into LemmyServiceHarness"
```

---

### Task 10: Wrapper-VC navbar UITests (Person + Instance)

**Files:**
- Modify/Create under `SpudUITests/` (follow `SpudUITests.swift`'s `test_VisitCommunityFromPostContextMenu_showsNavbarActions` pattern — read it first)
- Fixtures: `SpudUITests/Fixtures/` (or wherever the existing stub JSONs live — check the target layout)

**Why:** the resolve-then-show wrapper class of bug (child VC's navigationItem silently ignored) shipped invisibly once; only the Community wrapper has a tripwire today. Add the same guard for `PersonOrLoadingViewController` and `InstanceOrLoadingViewController` paths reachable from the signed-out seed.

**Fixture rule (CRITICAL):** `SBTStubResponse(fileNamed:)` NSAsserts at registration if the fixture file is missing — the whole class then reports "Executed 0 tests" and reads as if it never ran. Every fixture referenced MUST exist in the UITest target; cross-check required response fields against LemmyKit's generated `Types.swift` (missing required fields decode-fail silently).

- [ ] **Step 1: Read the existing Community navbar test + the two wrapper VCs** to determine each wrapper's expected navbar content (overflow menu, sort button, title) and an entry path from the seeded signed-out feed (e.g. context menu on a post creator → person; instance name → instance detail).
- [ ] **Step 2: Write the two tests** asserting: after navigating the WRAPPER path, the resolved screen's navigationBar exposes its expected buttons/title (`app.navigationBars[...]`, `.buttons[...]` with explicit `waitForExistence(timeout: 10)`).
- [ ] **Step 3: Run them on the booted sim**:
`xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUITests/<ClassName> -destination "platform=iOS Simulator,id=$(scripts/resolve-test-destination.sh | cut -d= -f3)" -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -5`
Expected: both PASS and the log shows the tests EXECUTED (not "Executed 0 tests" — that means a missing fixture).
- [ ] **Step 4: Commit**

```bash
git add SpudUITests
git commit -m "test: navbar-presence UITests for Person/Instance wrapper VCs"
```

If an entry path is NOT reachable from the signed-out seed without disproportionate new fixtures, implement the reachable one and record the other in the follow-up specs doc (Task 12) — do not force it.

---

### Task 11: CLAUDE.md restructure + doc fixes

**Files:**
- Modify: `CLAUDE.md`
- Create: `SpudSnapshotTests/CLAUDE.md`
- Create: `docs/release-runbook.md`
- Modify: `docs/features/diagnostics-logging.md` (Status line)
- Create: `.claude/settings.json` (PostToolUse hook)

**Rules:** No content invented — every moved bullet moves VERBATIM (minus duplication). CLAUDE.md keeps a one-line pointer to each extracted doc. Numbers duplicated from config files are replaced by pointers ("see `exactVersion:` in project.yml").

- [ ] **Step 1: Fix the contradictions/stale facts in `CLAUDE.md`**
  - Line 25 + 263: "pinned to 0.5.0" → "pinned via `exactVersion:` in `project.yml`".
  - Line 204: build-number prose → "bump `CURRENT_PROJECT_VERSION` in `project.yml` (see the file for the current value; auto-memory tracks the next TestFlight number)".
  - Reconcile the OS pin: all snapshot/destination prose now defers to `make snapshot` / `scripts/resolve-test-destination.sh`; delete the `OS=26.3` vs `26.3.1` contradiction (lines 64, 169-177, parts of 248).
- [ ] **Step 2: Rewrite "Build & test"** around `make build` / `make test` / `make test-only ONLY=...` / `make snapshot` (keep the `build_and_test.py` fast-path note and the raw `xcodebuild` forms as a fallback reference).
- [ ] **Step 3: Extract to `SpudSnapshotTests/CLAUDE.md`:** every snapshot/annex bullet (the `deterministicPhone` block, re-record ceremony, annex restage rules, blur/on-screen rendering notes, async-GRDB-observation seeding note, scrollable-size note, fixture-schema note stays in main if it's UITest-related). Leave in root CLAUDE.md: a 3-line summary + pointer.
- [ ] **Step 4: Extract to `docs/release-runbook.md`:** the entire "Release / TestFlight" section verbatim + the symbolication and Release-crash-repro bullets. Root keeps: "Archive with `make release-project`, gate with `make verify-archive`/`verify-ipa`, full runbook: docs/release-runbook.md".
- [ ] **Step 5: Fix `docs/features/diagnostics-logging.md`** Status line: `Status: shipped` (drop the "pending release (on feat/logging-observability)" clause).
- [ ] **Step 6: Add `.claude/settings.json` PostToolUse hook** that regenerates the project when `project.yml` changes:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.file_path // empty' | grep -q 'project\\.yml$' && xcodegen generate --quiet || true"
          }
        ]
      }
    ]
  }
}
```

Verify the hook JSON parses (`jq . .claude/settings.json`). If the harness rejects the shape at runtime it fails open (`|| true`) — acceptable.

- [ ] **Step 7: Sanity checks** — `wc -l CLAUDE.md` (expect a meaningful drop, roughly 100+ lines out); every pointer target exists; `grep -n "26.3" CLAUDE.md` shows no remaining contradictory pin advice.
- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md SpudSnapshotTests/CLAUDE.md docs/release-runbook.md docs/features/diagnostics-logging.md .claude/settings.json
git commit -m "docs: restructure CLAUDE.md — extract snapshot + release runbooks, fix stale pins, add project-regen hook"
```

---

### Task 12: Follow-up specs for deferred initiatives

**Files:**
- Create: `docs/superpowers/specs/2026-07-05-follow-ups.md`

One spec doc, one section per deferred initiative, each with: problem statement (from the audit), proposed approach, and explicit non-goals. Sections:

1. **VC→VM data-layer migration** — move GRDB observation loops + mutations out of `PostDetailViewController` / `PostListViewController` / `CommunityViewController` into their view models; `PersonViewModel` is the template; includes folding PostDetail's post-level actions into `PostActionDispatching`; extraction seams per the audit (Moderation/Delete/Report/Pending-comments as sibling extension files first, then observation moves).
2. **Signed-in UITest seam** — `seedSignedInDefaultAccount` launch argument + JWT/login SBT stubs; unlocks login/compose+send/vote/inbox/Activity e2e and un-skips `IPadSplitUITests.test_accountActivity_showsTwoColumnSplit`; burn-down list = the 12-item verification-debt table from the retrospective.
3. **SpudWidget test target** — `SpudWidgetTests` in project.yml; unit-cover `EntryService` / `TopPostsProvider` / asset image resolution.
4. **CI gate** — runner choice (GitHub Actions macOS vs self-hosted), runs `make test` on PRs + Release-config fresh-install launch smoke; blocking entitlement gate before upload.
5. **Runtime-pinned snapshot trim** — cut full-screen app-level snapshots to a smoke set; keep `deterministicPhone` + on-screen-blur populations; expected effect on the re-record ceremony.
6. **git-annex special remote + push cadence** — get snapshot refs off this machine; push main at every merge.
7. **Count-formatter style unification** — one visual style for compact counts app-wide (changes rendered strings → snapshot re-records; deliberate, small).

- [ ] **Step 1: Write the doc** (each section 10-20 lines, concrete, citing file paths from this plan/audit).
- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-07-05-follow-ups.md
git commit -m "docs: follow-up specs for deferred refactor initiatives"
```

---

### Task 13: Final verification + merge

- [ ] **Step 1:** `mint run swiftformat --lint .` → clean.
- [ ] **Step 2:** Full suite: `make test 2>&1 | tail -8` → the Swift Testing summary lines all pass; UITests pass.
- [ ] **Step 3:** Whole-branch review by a FRESH reviewer subagent (diff `main...HEAD`), checking: behavior preservation (strings/haptics), access-level weakening in Task 8, plan-vs-implementation drift.
- [ ] **Step 4:** Address findings; re-run affected suites.
- [ ] **Step 5:** Merge: from the MAIN checkout, `git merge --no-ff worktree-reflect-refactor`; verify `git diff main worktree-reflect-refactor` is empty post-merge.
