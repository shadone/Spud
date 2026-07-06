# Deferred refactor follow-ups — specs

Date: 2026-07-05
Status: Backlog (each section is a self-contained future initiative)
Scope: whole app + test infrastructure. Deferred from the 2026-07-05 reflect /
refactor branch.

These are the initiatives the 2026-07-05 five-agent audit (architecture /
duplication / test coverage / LLM ergonomics / session retrospective) surfaced
but that were out of scope for the branch that produced this doc. Each section is
its own spec: a problem statement (with the audit's evidence), a proposed
approach, and explicit non-goals. Context: ~891 Swift files / ~131k lines (app
target 283 files / 55.6k), 1,119 commits since 2026-05-01, zero reverts. The
through-line is verification debt — 12 features shipped/merged with on-device or
manual verification still owed, rooted in dead tap automation and no signed-in
UITest seam.

## 1. VC-to-VM data-layer migration

**Problem.** `PostDetailViewController.swift` (3,097 lines, 57 commits since
2026-06-15) holds `HasAppDatabase` and runs GRDB observation loops itself
(`observePostDetailHeader` ~line 632, `observePostDetailComments` ~716,
`observeOutboundComments` ~778), sync lookups (`postRowIdSync`,
`accountInstanceActorIdSync`, `postInteractionSnapshotSync`), and mutations
(`recordPostOpened` ~674, `muteCommunitySync` ~2523), while `PostDetailViewModel.swift`
(254 lines) never touches `appDatabase`. `PostListViewController.swift` (2,289
lines, 41 commits) mirrors this — starts `appDatabase.observePostListRows`
itself (~1080), calls `muteCommunitySync` / `recordPostSeen` directly.
`CommunityViewController` reaches around its (correct) view model for mute /
favorite mutations (~lines 345-435). `PersonViewController` is the template:
`PersonViewModel` owns the observation loops (the VC has only 2 direct
appDatabase calls, ~503, ~938). The logic that lives only in VCs is exactly the
logic with zero unit coverage today.

**Approach.** Extract PostDetail seams first as sibling extension files
(following the `PostListViewController+OfflineDownload.swift` precedent):
Moderation (~1910-2251), Delete/Restore (~1809-1910), Pending/optimistic comment
actions (~2251-2386), Report (~1740-1809). Then move the observation loops and
mutations down into the view models, making them unit-testable and shrinking the
three whale files. Fold PostDetail's post-level vote/save into the
`PostActionDispatching` protocol added by this branch (`Spud/Utils/PostActions.swift`);
comment-level vote stays separate (different entity type). Two open review notes
to address in that fold: (a) split the protocol into vote-dispatch vs
save-dispatch halves so vote-only screens (Activity) don't carry a stub
`currentSavedState`; (b) consider dropping `presentSignInGate` as a protocol
requirement (the UIViewController extension already provides it; the requirement
adds witness-table dispatch and a shadowing footgun).

**Non-goals.** Not changing the reactive model (stays AsyncSequence / Observation,
not Combine). Not merging comment-level vote into the post-level protocol. Not
reworking `CommunityViewModel`'s already-correct read-side observation.

**Landed (2026-07-06): Phase 1** (plan:
docs/superpowers/plans/2026-07-06-postdetail-phase1.md). `PostDetailViewController`
shrank 3,098 -> 2,268 lines via six pure-motion sibling files (+Content, +Report,
+DeleteRestore, +Moderation, +PendingComments, +OverflowMenu; token-level motion
audits). Both open review notes resolved: the protocol is now split into
`PostVoteDispatching` / `PostSaveDispatching` (Activity dropped its stub) and the
`presentSignInGate` requirement is gone; a `postActionWillDispatch` hook carries
PostDetail's offline-action toast, and PostDetail's post-level vote/save now fold
into `PostSaveDispatching` (behavior byte-identical, review-proven).

**Landed (2026-07-06): Phase 2** (plan:
docs/superpowers/plans/2026-07-06-postdetail-phase2.md). `PostDetailViewModel`
now owns the data layer: all three GRDB observation loops (header, comments —
via a published `commentsRevision` signal since `orderedComments` stays
`@ObservationIgnored` — and outbound), `recordVisit`, and the sync-read
accessors (`instanceActorId`, `isOwnContent`, `isKnownInstance`,
`muteCommunity`); the VC is a renderer reacting through `ObservationStream`
loops (`grep "appDatabase\." PostDetailViewController*.swift` is zero beyond
the DI declaration and the `InternalLinkRouting` conformance). 13 DB-backed VM
tests (in-memory GRDB harness) + a PostDetail header-vote e2e. The VC is 2,264
lines (reaction-loop scaffolding keeps it above the ~2,000 estimate); the VM is
508. Still open (Phase 3, optional): moving the lemmyService mutations
(report/delete/moderation) into VM methods, and applying the same
VM-owns-observations shape to `PostListViewController` and
`CommunityViewController`.

**Landed (2026-07-06): PostList/Community replication** (plan:
docs/superpowers/plans/2026-07-06-postlist-vm.md). `PostListViewModel` owns the
row observation, the lazy-feed gate (awaits the feed-creating first fetch
inline), the atomic `rowsByServerPostId` lookup + published `rowsRevision`, a
VM-published `firstSnapshotReadIds` (coalescing-proof pinned-read seeding), a
`keepingContent` restart flavor for pull-to-refresh, and the sync accessors;
the VC reacts via the shared `ObservationStream` with an `isolated deinit`
teardown (a review-caught leak fix — the teardown IS part of the template).
`CommunityViewModel` absorbed the six favorite/mute accessors. 12 new DB-backed
VM tests + a pagination-reactivity lock test. **Bonus latent-bug fix:** the
VC's local `values(of:)` shim (a pre-fix fork of `ObservationStream`) never
retained its scheduler — streams were one-shot, and the pagination footer had
been DEAD on shipped main (title/loadState were masked by alternate drivers);
replacing it with the shared, regression-tested `ObservationStream` revives the
pagination spinner/retry footer and the non-rows-coincident loadState surfaces
(initial-load failure surface, refresh-failure toast, slow-hint). Remaining
section 1 scope: PostDetail Phase 3 (lemmyService mutations) only.

## 2. Signed-in UITest seam

**Problem.** The only account seam today is `seedSignedOutDefaultAccount`
(`Spud/App/AppLaunchArgument.swift` has just 2 seams, no signed-in seed) — stated
explicitly at `SpudUITests/IPadSplitUITests.swift:270`, where the iPad Activity
split test is `throw XCTSkip` (~line 278) for exactly this reason. The
consequence is zero e2e coverage of login (LoginViewModel has zero test
references anywhere), compose+send (composer/outbox are superbly unit-tested but
the UI path is never driven), vote, inbox/DM, and the Activity split.

**Approach.** Add a `seedSignedInDefaultAccount` launch argument plus a
JWT/credential stub and SBT stubs for the signed-in bootstrap calls (getSite with
`my_user`, unread counts). Un-skip
`IPadSplitUITests.test_accountActivity_showsTwoColumnSplit`. This unlocks the
retrospective's 12-item shipped-but-never-verified pile: post tracking/history
delta, pull-to-refresh, undo scroll-to-top, optimistic vote/save/hide, saved-feed
loading indicator, durable composing, feed-switcher swipe, durable DMs,
profile/banner editing, Account->Activity phases 1-3, offline-download
retry/rate-limiting, iPad split polish. Also unblocks navbar tripwires for
auth-gated wrappers and the Instance wrapper tripwire (section 7).

**Non-goals.** Not replacing the broken tap-automation stack (idb) — this is a
launch-arg seed, not a driver fix. Not running e2e against live Lemmy instances;
everything stays SBT-stubbed.

**Landed (2026-07-05):** the `SPUDSeedSignedInDefaultAccount` seam (DEBUG
`AccountService` seed: person row + fake JWT, fixed keychainId) + the
`SPUDWipeAppDatabase` launch argument (the App Group DB survives SBT's
ResetFilesystem / `simctl uninstall`; the wipe makes signed-in tests
order-independent regardless of what a prior suite left behind), rolled out to
both the new signed-in suites and the legacy signed-out ones — `SpudUITests`
and `IPadSplitUITests` now pass `SPUDWipeAppDatabase` alongside their
signed-out seed too, closing the reverse-contamination gap where a signed-in
account left by an alphabetically-earlier suite could make a signed-out seed a
no-op. Four consumers green: `IPadActivitySplitUITests` un-skipping the
Activity split, `SignedInVoteUITests` pinning optimistic-vote-with-no-gate
against a 500 send, and the two legacy suites re-proven order-independent in
both directions on both the reference iPhone and the M5 iPad. Remaining scope
stays open: login/compose/inbox e2e, and the 12-item verification-debt
burn-down.

## 3. SpudWidget test target

**Problem.** SpudWidget is 22-24 source files (~1,200 lines) — timeline provider,
`TopPostsAppIntentProvider`, `EntryService`, asset image resolution, accessory
views — with ZERO tests and no test target. It reads the shared App Group DB, the
same DB whose multi-process migration race crashed TestFlight build 24 for every
user.

**Approach.** Add a `SpudWidgetTests` target in `project.yml` (Swift Testing,
mirroring the SpudDataKitTests conventions), unit-covering `EntryService`, the
timeline provider, and asset image resolution. Consider 2-3 SwiftUI snapshots for
the accessory views as a later increment.

**Non-goals.** Not snapshotting every accessory widget family now. Not testing
WidgetKit's own timeline scheduling — cover our provider logic, not the OS.

## 4. CI gate

**Problem.** Nothing gates today. Pre-commit was a lint-only `exit 0` until this
branch (now blocking lint, still no tests); no CI runs tests (only
`ci_scripts/ci_post_clone.sh` regenerating the project; Xcode Cloud is not set
up); `Spud.xctestplan` had `codeCoverage: false` and (until this branch) omitted
two test targets. Two release incidents this would have caught: build 12
(CODE_SIGNING_ALLOWED=NO stripped the App Group entitlement -> launch crash and
iOS wiped the App Group container = user data loss; invisible to tests/sim) and
build 24 (multi-process migration race -> launch crash for all users; Debug/sim
hid it). 2 of 25 TestFlight builds (8%) were launch-crash duds.

**Approach.** (a) Decide the runner: GitHub Actions macOS runner vs a self-hosted
Mac. Note that git-annex snapshot refs are NOT on origin, so CI cannot run
snapshot verification until section 6 lands — scope the first CI to unit tests +
build. (b) Run `make test` on PRs. (c) Add a Release-config fresh-install launch
smoke on a clean simulator. (d) Make `make verify-archive` / `verify-ipa` a
blocking, unskippable pre-upload step (they exist; nothing enforces them). Also
enable `codeCoverage` in the test plan (deliberately deferred from this branch's
Task 4).

**Non-goals.** No snapshot verification in CI until the annex remote (section 6)
exists. No device-farm / physical-device matrix — the smoke runs on a simulator.

## 5. Runtime-pinned snapshot trim

**Problem.** SpudSnapshotTests carry 406 PNG refs across 50 classes (+36 in
SpudMarkdownKitSnapshotTests), in two populations. Device-independent (KEEP): ~16
classes on `.image(on: .deterministicPhone)`, ~15 on `.image(on:)`, ~7 on-screen
(`drawHierarchyInKeyWindow`, for UIVisualEffectView blur) — robust, catch real
layout regressions. Device+runtime-pinned (TRIM): `.image(size:traits:)`
cell/header renders and full-screen app-level snapshots — they only match on
iPhone 17 Pro + iOS 26.3; ~129/185 fail on iOS 26.0 from pure font-hinting drift,
a library bump once caused a 96-failure repo-wide drift event, and there have
been 90 snapshot-related commits since 2026-06-01 (the single biggest time sink
in the project's history).

**Approach.** Cut the runtime-pinned full-screen app-level population to a minimal
smoke set (a handful of highest-value screens) and lean on the deterministic
cell/header snapshots for layout regressions. Keepers named by the audit:
`PostDetailCommentSnapshotTests` (50 refs) and `PostListPostCellSnapshotTests`
(38) — both cell/header-level. Expected effect: the re-record ceremony shrinks
from dozens of refs per UI change to a few.

**Non-goals.** Not deleting the deterministic cell/header snapshots — those are
the layer that stays. Not dropping the on-screen blur snapshots (they exist
because `deterministicPhone` can't render `UIVisualEffectView`).

**Addendum (2026-07-05, found during the reflect-refactor final verify): sim
UserDefaults leak into cell snapshots.** `PostListPostCellSnapshotTests` builds a
"fresh `PreferencesService`" per render, but `@UserDefaultsBacked` reads the
persisted sim defaults, so `thumbnailPosition` / `showVoteButtons` (gates at
`PostListPostContentView.swift:383-443`) silently change the rendered layout.
The `test_unavailableBadge` refs re-recorded at `771b6e75` were captured with
non-default preferences (no thumbnail placeholder, no vote buttons) and fail
against a clean-install render (780x159 ref vs 780x224 actual, light+dark) —
the one red test in an otherwise green 250-test suite run.

Immediate fix landed (same day): `PostListPostCellSnapshotTests.makeViewModel`
now pins `thumbnailPosition = .left` + `showVoteButtons = true` explicitly, and
the two contaminated refs were re-recorded under pinned clean-default state
(full plan 250/250 green). Owed by this initiative at the time: 9 other
snapshot fixture files construct a bare `PreferencesService()` and carry the
same latent leak (masked while the sim stays clean) — the durable fix was an
injectable `UserDefaults` store on `PreferencesService` (30
`@UserDefaultsBacked` properties hardcoded `.standard` at the time), applied
across all snapshot fixtures.

**Second addendum (2026-07-05, found during the signed-in-seam Task 5 final
verify): the same leak reaches across process boundaries into live UI tests,
not just snapshots.** `SpudTests` is hosted inside the `Spud` app target
(`project.yml`'s `dependencies: - target: Spud`), so a bare `PreferencesService()`
there reads/writes the REAL `info.ddenis.Spud` `UserDefaults.standard` domain —
the same one a later `SpudUITests` launch reads from, and SBT's
`ResetFilesystem` does not reliably clear it. `QuickSwitchViewModelTests` left
`showVoteButtons = false` / `thumbnailPosition = .right` / `postDensity = .compact`
persisted (no cleanup after its last write), which made the new
`SignedInVoteUITests` (section 2) fail 5/5 times when run as part of the full
`make test` plan — but always pass in isolation, since an `-only-testing` run
never executes `SpudTests` first. Fixed at the time: `QuickSwitchViewModelTests`,
`OfflineDownloadOptionsViewModelTests`, and `PostDetailConfigViewModelTests`
were made to `defer`-restore every mutated key to its documented default and
were `@Suite(.serialized)`d (Swift Testing runs a struct's tests in parallel by
default, racing the same shared keys otherwise); `make test` reran green twice
after. Not audited then: whether any OTHER `SpudTests` file leaks a different
key this way — the durable fix was the same injectable-store initiative above.

**Landed (2026-07-05):** the injectable `UserDefaults` store on
`PreferencesService` plus `PreferencesService.ephemeral()` (SpudTests) /
`SnapshotPreferences.ephemeral()` (SpudSnapshotTests) shipped (plan:
`docs/superpowers/plans/2026-07-05-test-determinism.md`), and every fixture
named above — plus the rest of the affected snapshot and unit fixtures — was
migrated onto a private per-instance `UserDefaults` suite. The defer-restore /
`@Suite(.serialized)` workaround described in both addenda above is retired;
it remains appropriate only for a suite that deliberately exercises
`.standard` itself (`PreferencesServiceStorageIsolationTests`). This closes
both addenda's leak; the rest of this section's scope — trimming the
runtime-pinned snapshot population itself — is unchanged and still open.

## 6. git-annex special remote + push cadence

**Problem.** 100% of the snapshot reference PNG content exists ONLY on this
machine: origin has no git-annex, so pushes carry pointer files only. A single
disk failure loses the entire snapshot baseline. Separately, the unpushed-main
backlog historically hit 57-98 commits (logged "57 commits ahead" 2026-06-22, "98
ahead" 2026-06-16) because pushes only happened at TestFlight ships.

**Approach.** Configure an annex special remote (evaluate: S3, a second machine,
or an external disk via a `directory` remote) and run `git annex sync --content`
after each re-record so the PNG bytes leave this machine. Change the push cadence:
push origin main at every `--no-ff` merge (or nightly), not only at ship time.

**Non-goals.** Not migrating snapshot storage off git-annex (e.g. to LFS or a
blob store) — keep annex, just give it a remote. Not committing to a specific
remote backend in this spec; the backend choice is the first evaluation step.

## 7. Instance wrapper navbar tripwire

**Problem.** The `InstanceOrLoadingViewController` promotion path is unreachable
from the signed-out UITest seed: every seeded host (lemmy.world x39,
discuss.tchncs.de x12) is in the bundled Explorer directory, so a directory hit
bypasses the wrapper, and no seeded surface links an off-directory host
(`SpudUITests/SpudUITests.swift:246`). This is the same wrapper-bug class
(child-VC `navigationItem` ignored by UIKit until promoted into the nav stack)
that shipped a visible bug in the Community wrapper. The same gap remains for
`PostDetailOrEmptyViewController` (iPad detail placeholder; partially covered by
IPadSplitUITests) and `CommunityReadingSplitViewController` (iPad, needs tap
flows).

**Approach** (recipe from `.superpowers/sdd/task-10-report.md`). Seed a
post/person on a guaranteed off-directory host `spud-test.example`, render a
tappable `info.ddenis.spud://instance` link to it, stub
`.../spud-test.example/api/v3/site` with a complete `GetSiteResponse` (required:
`site_view.{site, local_site, counts}`, `version`; cross-check every consumed
field against `ExplorerInstanceRecord+Synthesized.swift` and generated
`Types.swift`), then assert `app.navigationBars["spud-test.example"]` plus its
single share bar button (`square.and.arrow.up`,
`InstanceExploreViewController.swift:124-131`) with `waitForExistence(timeout: 10)`.
Tripwire to respect: `SBTStubResponse(fileNamed:)` NSAsserts at registration if
the fixture file is missing — "Executed 0 tests" means a fixture crash, not a
pass. Naturally paired with section 2's seed work.

**Non-goals.** Not covering the iPad split wrappers here beyond noting the same
class of gap. Not fabricating a live federated instance — the off-directory host
is a fixture, never a real network target.

## 8. Count-formatter style unification

**Problem.** 5+ compact-count implementations existed; this branch unified the
two byte-identical ones into `Spud/Utils/Formatters/CompactCount.swift`
("1.2K" / "32K" / "1.2M" style; the "—" empty wrapper stays in
InstanceHealthStyle). Deliberately untouched, because they render DIFFERENT
styles pinned by snapshot refs: `SpudDataKit/Utils/Formatters/CommentsFormatter.swift`
(K-only, 1 decimal), `SummaryHeatmapCardView.formatCount` (~line 151, K/M), and
`.formatted(.number.notation(.compactName))` in `SiteListSiteViewModel.swift`
(~95) and `SearchResults.swift` (~226).

**Approach.** Pick ONE visual style app-wide (probably CompactCount's), migrate
the remaining call sites to it, and re-record the affected snapshot refs in the
same change. This is a small, deliberate re-record — the whole point is that the
rendered strings change, so the snapshot churn is expected and bounded.

**Non-goals.** Not changing the "—" empty-value wrapper semantics. Not a
mechanical find-replace — decide per call site whether the locale-aware
`.compactName` output is intentionally wanted before collapsing it into
CompactCount.

**Second addendum to section 5 (2026-07-06, found during PostDetail Phase 2 final
verify): app-level accent leak fails 47 snapshot assertions (25 tests) on a
clean sim.** `StaticImageService` yields the bundled `tv-pattern` template image,
tinted by the window accent that `ThemeManager` reads from `UserDefaults.standard`
— outside the ephemeral-store isolation, which covers only `PreferencesService`
fixtures. Refs recorded under a non-default accent mismatch a clean-install run.
Proven pre-existing: plain main and the Phase 2 branch fail the IDENTICAL
25-test set on the same sim state. (An earlier draft of this note over-listed
affected classes from a degraded-run failure census — Toast/Media*/
PostUnavailable/LinkPreview/HeaderInlineImage/PostDetailComment reference
neither leak mechanism and were collateral in crashed runs, not accent
victims.)

**FIXED (2026-07-06,** plan:
docs/superpowers/plans/2026-07-06-accent-determinism.md**):**
`SnapshotDeterminism.pinAccent()` (`ThemeManager.shared.setAccent(.lemmy)`)
wired into the setUp of the empirically-verified 9 affected classes
(ActivityIPadSplit, InstanceDetail, InstanceExplore, IPadLayout,
OnboardingHomeBase, OutboundContentList, PendingPost, PostDetailHeader,
Summary); the 25 dirty-accent tests' 47 refs re-recorded under the pinned
default; suite 258/258 twice, byte-stable, on a clean sim. New snapshot
classes must call `pinAccent()` (or pin a tint explicitly). Deeper fix
(injectable ThemeManager store) remains optional future scope of this
section.
