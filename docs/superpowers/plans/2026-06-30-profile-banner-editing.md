# Profile Banner Editing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Spec: `docs/superpowers/specs/2026-06-30-profile-banner-editing-design.md`.

**Goal:** Let a signed-in user set/remove their profile banner from Edit Profile (with a live-preview header), and show the banner in the Account tab header — reusing the existing avatar image-upload pipeline.

**Architecture:** Thread one `banner: String?` field through the already-shipped profile-save path (`saveProfile` → `saveUserSettings(banner:)` → optimistic `PersonRecord.bannerUrl` mirror → `getSite` reconcile). The UI is a near-copy of the avatar `PhotosPicker` → `uploadImage` (pict-rs) flow, presented as a full-width banner with an overlapping circular avatar. No new upload infrastructure and no LemmyKit changes.

**Tech Stack:** Swift 6 (language mode 6.0 on shipped targets), UIKit + SwiftUI (Account/EditProfile screens are SwiftUI), GRDB, LemmyKit (remote SPM pin 0.5.0 — unchanged), Swift Testing (SpudDataKitTests/SpudTests), pointfreeco/swift-snapshot-testing (SpudSnapshots), XcodeGen.

## Global Constraints

- **Swift strict concurrency** `SWIFT_STRICT_CONCURRENCY = complete`; new code is Swift 6.0 language mode. View models are `@MainActor @Observable`.
- **No emojis** in code/comments/docs/commits. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- **Branch:** all work on `feat/profile-banner-editing` (worktree `.claude/worktrees/profile-banner-editing`, spec committed at `efcda9bb`). Verify `git branch --show-current` before EVERY commit. Stage EXPLICIT paths only — NEVER `git add -A`, NEVER stage any `__Snapshots__` path except refs you intentionally record (the tree carries cosmetic git-annex `M` markers that are not yours). `git status` hides untracked files — use `git status -uall`.
- **Reuse, don't rebuild:** the avatar pipeline is the template. `banner` follows the `avatar` convention exactly, including **empty string = clear**. No crop/resize UI (JPEG 0.85 re-encode only). NO LemmyKit edits (`SaveUserSettings.banner` already exists). NOT routed through the outbox.
- **After adding/removing files,** run `make -C <worktree> project` (XcodeGen) before building.
- **SwiftFormat** touched files (`mint run swiftformat <paths>`) BEFORE the final verify of each task, never after. Mind `--enable isEmpty`.
- **Snapshot determinism:** header snapshots must use a nil/placeholder or stubbed local image — never trigger an async remote load (refs would be unstable). Record on iPhone 17 Pro / iOS 26.3.1, or pin a device config.

## File Structure

**Modified — SpudDataKit:**
- `Services/AppDatabase/Records/AccountEditableProfile.swift` — add `bannerUrl: String?` + seed from `PersonRecord.bannerUrl`.
- `Services/AppDatabase/Importers/AccountImporter.swift` — `setAccountProfile(... banner:)` mirror.
- `Services/Lemmy/LemmyService.swift` — `saveProfile(... banner:)` (protocol decl ~`:100` + impl `:1096`).

**Modified — Spud (app):**
- `Scenes/Account/EditProfile/EditProfileViewModel.swift` — banner state + `uploadBanner`/`removeBanner` + `save()` threads `banner`.
- `Scenes/Account/EditProfile/EditProfileView.swift` — live-preview banner+avatar header.
- `Scenes/Account/AccountView.swift` (+ its header subview) — show the banner.

**New — Spud (app):**
- `Scenes/Account/EditProfile/ProfileBannerHeaderView.swift` — a shared SwiftUI banner+overlapping-avatar header used by both the editor (interactive) and the Account tab (display-only), to DRY the layout. (Only if the duplication is real — see Task 5.)
- `SpudSnapshotTests/ProfileBannerSnapshotTests.swift` — header snapshots.

---

## PHASE 1 — Data layer (thread `banner` through save/mirror/seed)

### Task 1: `AccountEditableProfile.bannerUrl` + seed

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Records/AccountEditableProfile.swift`
- Modify: the `accountEditableProfileSync(forKeychainId:)` reader (in `AppDatabase` / an importer — find it; it builds `AccountEditableProfile` from the joined `account`/`person` rows).
- Test: `SpudDataKitTests/AccountEditableProfileTests.swift` (new, or add to an existing account test suite).

**Interfaces:**
- Produces: `AccountEditableProfile` gains `public var bannerUrl: String?`. `accountEditableProfileSync` populates it from `PersonRecord.bannerUrl`.

- [ ] **Step 1: Failing test** — seed an in-memory `AppDatabase` with an account whose `person.bannerUrl = "https://lemmy.example/pictrs/image/b.jpg"`; call `accountEditableProfileSync(forKeychainId:)`; `#expect(profile.bannerUrl == "https://lemmy.example/pictrs/image/b.jpg")`. (Mirror how the existing avatar seed is tested, if a test exists; otherwise seed via the importers used by sibling account tests.)
- [ ] **Step 2:** `make project`; run `-only-testing:SpudDataKitTests/AccountEditableProfileTests`; verify FAIL (no `bannerUrl`).
- [ ] **Step 3:** Add `bannerUrl: String?` to the struct (place it next to `avatarUrl`, same access level + Codable/Sendable conformance as siblings) and read `person.bannerUrl` into it in `accountEditableProfileSync`.
- [ ] **Step 4:** Run the test; verify PASS.
- [ ] **Step 5:** SwiftFormat; commit `feat(profile): seed AccountEditableProfile.bannerUrl from PersonRecord`.

### Task 2: `setAccountProfile(banner:)` optimistic mirror

**Files:**
- Modify: `SpudDataKit/Services/AppDatabase/Importers/AccountImporter.swift:215` (`setAccountProfile`).
- Test: `SpudDataKitTests/SetAccountProfileBannerTests.swift` (new).

**Interfaces:**
- Consumes: `PersonRecord.bannerUrl` column (exists).
- Produces: `setAccountProfile` gains a `banner: String?` parameter (place it adjacent to `avatar:`, same position-convention). Writes `person.bannerUrl = banner.flatMap { $0.isEmpty ? nil : $0 }` — the exact pattern used for `avatarUrl` at `AccountImporter.swift:252`.

- [ ] **Step 1: Failing test** — seed an account+person; call `setAccountProfile(forKeychainId:, ..., banner: "https://x/b.jpg", ...)`; read back the `PersonRecord`; `#expect(person.bannerUrl == "https://x/b.jpg")`. Second case: `banner: ""` → `#expect(person.bannerUrl == nil)`.
- [ ] **Step 2:** `make project`; run `-only-testing:SpudDataKitTests/SetAccountProfileBannerTests`; verify FAIL (extra arg / not written).
- [ ] **Step 3:** Add `banner: String?` to the signature and the `person.bannerUrl = ...` write inside the existing GRDB write block. Do NOT change other fields.
- [ ] **Step 4:** Run the test; verify PASS. Also run the full `SpudDataKitTests` once to catch any other `setAccountProfile` call site that now needs the new argument (the only production caller is `LemmyService.saveProfile`, updated in Task 3; update test call sites as needed).
- [ ] **Step 5:** SwiftFormat; commit `feat(profile): mirror banner to PersonRecord in setAccountProfile`.

### Task 3: `LemmyService.saveProfile(banner:)`

**Files:**
- Modify: `SpudDataKit/Services/Lemmy/LemmyService.swift` — protocol decl (~`:100`, in `LemmyServiceType`) + impl (`:1096`).
- Test: `SpudDataKitTests/SaveProfileBannerTests.swift` (new), using the existing API fake pattern that other LemmyService tests use.

**Interfaces:**
- Consumes: `api.saveUserSettings(... banner:)` (LemmyKit, exists); `setAccountProfile(... banner:)` (Task 2).
- Produces: `saveProfile` gains `banner: String?` (adjacent to `avatar:`). It passes `banner` to `api.saveUserSettings(banner: banner)` AND to `appDatabase.setAccountProfile(banner: banner)`.

- [ ] **Step 1: Failing test** — with a fake/recording `LemmyApi` (mirror the existing saveProfile/saveUserSettings test setup), call `saveProfile(..., banner: "https://x/b.jpg")`; assert the fake recorded `saveUserSettings` with `banner == "https://x/b.jpg"`, AND the `PersonRecord.bannerUrl` mirror landed. (If no saveProfile test exists yet, model it on the nearest LemmyService test with an injected api fake.)
- [ ] **Step 2:** `make project`; run `-only-testing:SpudDataKitTests/SaveProfileBannerTests`; verify FAIL.
- [ ] **Step 3:** Thread `banner` through the protocol + impl: add the param, pass to `api.saveUserSettings(... banner: banner ...)` and `setAccountProfile(... banner: banner ...)`. Update any other `saveProfile` call site (the app caller in `EditProfileViewModel` is updated in Task 4; update test callers now so the suite compiles).
- [ ] **Step 4:** Run the test; verify PASS, then full `SpudDataKitTests` green.
- [ ] **Step 5:** SwiftFormat; commit `feat(profile): thread banner through LemmyService.saveProfile`.

---

## PHASE 2 — UI (editor header + Account tab)

### Task 4: `EditProfileViewModel` banner state + upload/remove + save

**Files:**
- Modify: `Spud/Scenes/Account/EditProfile/EditProfileViewModel.swift`
- Test: `SpudTests/EditProfileViewModelBannerTests.swift` (new) — at minimum, that `save()` with `bannerEdited == true` calls `saveProfile` with the expected `banner` string (inject a fake `LemmyServiceType`/`AccountScope` as the existing VM tests do; if VM save isn't unit-tested today, add the smallest test that injects a fake service and asserts the `banner` argument).

**Interfaces:**
- Consumes: `accountScope.lemmyService.uploadImage(imageData:fileName:mimeType:)`, `saveProfile(... banner:)` (Task 3), `AccountEditableProfile.bannerUrl` (Task 1).
- Produces: `bannerUrl: URL?`, `bannerEdited: Bool`, `func uploadBanner(imageData: Data) async`, `func removeBanner()`. `save()` includes `banner: bannerEdited ? (bannerUrl?.absoluteString ?? "") : <unchanged>`.

- [ ] **Step 1: Failing test** per above (assert `save()` forwards the banner string).
- [ ] **Step 2:** `make project`; run `-only-testing:SpudTests/EditProfileViewModelBannerTests`; verify FAIL.
- [ ] **Step 3:** Implement. `uploadBanner` is a near-copy of the existing `uploadAvatar` (filename `banner-<UUID>.jpg`, mime `image/jpeg`, set `bannerUrl` + `bannerEdited = true`, reuse the same error handling). `removeBanner` mirrors `removeAvatar` (clear `bannerUrl`, `bannerEdited = true`). Seed `bannerUrl` from `AccountEditableProfile.bannerUrl` at init. In `save()`, compute and pass `banner` exactly as `avatar` is passed (empty string when cleared). Only send `banner` when `bannerEdited` (match the avatar `avatarEdited` gating, or always-send if that's what avatar does — match avatar's behavior verbatim).
- [ ] **Step 4:** Run the test; verify PASS.
- [ ] **Step 5:** SwiftFormat; commit `feat(profile): EditProfileViewModel banner upload/remove/save`.

### Task 5: `EditProfileView` live-preview header (+ shared header view)

**Files:**
- Create: `Spud/Scenes/Account/EditProfile/ProfileBannerHeaderView.swift`
- Modify: `Spud/Scenes/Account/EditProfile/EditProfileView.swift`
- (Reference: `Spud/Scenes/Person/Content/PersonHeaderView.swift` for the banner+overlapping-avatar proportions — banner ≈100pt full-width, circular avatar overlapping the bottom edge.)

**Interfaces:**
- Produces: `ProfileBannerHeaderView` — a SwiftUI view taking the banner image (or nil → placeholder), the avatar image (or nil), and optional edit affordances (the `PhotosPicker` bindings + Remove actions). When the edit affordances are absent it renders display-only (reused by Task 6).

- [ ] **Step 1:** Build `ProfileBannerHeaderView`: full-width banner (`aspectFill`, clipped, ≈100pt) with a neutral placeholder fill when nil; circular avatar overlapping the banner's bottom edge. Accept optional closures/bindings so the editor can make the banner + avatar tappable (`PhotosPicker`) and expose Remove (context menu / overlay button); display-only when those are nil.
- [ ] **Step 2:** In `EditProfileView`, replace the current avatar section + form top with `ProfileBannerHeaderView` wired to the view model: banner `PhotosPicker` → `viewModel.uploadBanner`, avatar `PhotosPicker` → existing `viewModel.uploadAvatar`, each with a Remove affordance (`removeBanner`/`removeAvatar`). Keep the rest of the form (display name, bio, toggles, listing type) unchanged below the header. **Accessibility:** banner exposes label + action ("Profile banner, double-tap to change"); Remove actions labeled; avatar keeps its label.
- [ ] **Step 3:** `make project`; build the app: `cd <worktree> && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`. Expected: build SUCCESS. Manually sanity-check (or note for the snapshot task) that the header renders with placeholder + image.
- [ ] **Step 4:** SwiftFormat; commit `feat(profile): live-preview banner+avatar header in Edit Profile`.

### Task 6: Account tab header shows the banner

**Files:**
- Modify: `Spud/Scenes/Account/AccountView.swift` (+ its header subview).

**Interfaces:**
- Consumes: `ProfileBannerHeaderView` (Task 5, display-only mode); the account's `bannerUrl`/`avatarUrl` already observed for the Account tab.

- [ ] **Step 1:** Render the banner in the Account tab header using `ProfileBannerHeaderView` in display-only mode (no pickers), styled to match the public person profile (banner behind/above avatar + name + handle). If the Account header's data source doesn't already expose `bannerUrl`, wire it from the same observation that feeds the avatar. Keep name/handle and the tap-to-edit affordance intact.
- [ ] **Step 2:** `make project`; build the app (command as Task 5). Expected: SUCCESS. Sanity-check the Account tab shows the banner (placeholder when none).
- [ ] **Step 3:** SwiftFormat; commit `feat(profile): show banner in Account tab header`.

---

## PHASE 3 — Snapshots, a11y, docs

### Task 7: Snapshots + accessibility verification

**Files:**
- Create: `SpudSnapshotTests/ProfileBannerSnapshotTests.swift`

- [ ] **Step 1:** Snapshot the Edit Profile header and the Account tab header, each with a **stubbed local banner image** and with **no banner (placeholder)**, light + dark. Use a deterministic local image (no remote load) per the snapshot conventions; pin a device config where possible, else record on iPhone 17 Pro / iOS 26.3.1. Record (first run fails) then verify (rerun green); ONE class at a time; `git add` only the new ref PNGs by explicit path.
- [ ] **Step 2:** Accessibility pass: confirm VoiceOver order (banner → avatar → fields), the banner's label/action and Remove labels, and that Dynamic Type still lays the form out sanely. Fix any gap (small, contained edits) and rebuild.
- [ ] **Step 3:** Commit `test(profile): banner header snapshots + a11y`.

### Task 8: Docs

**Files:**
- Modify: the profile-editing capability doc under `docs/features/` (the Edit Profile / account doc) + `docs/features/README.md`.

- [ ] **Step 1:** Add banner editing to the capability doc: behavior + a Given/When/Then scenario (set a banner; remove a banner; see it on the Account tab and the public person profile). Update the README capability table + by-area map. No `.swift` links; honest `Status:`.
- [ ] **Step 2:** Commit `docs: profile banner editing`.

---

## Self-review

- **Spec coverage:** data threading (T1 seed, T2 mirror, T3 service), editor VM (T4), editor header live-preview (T5), Account tab banner (T6), snapshots+a11y (T7), docs (T8). Reuse-of-avatar-pipeline, empty-string-clears, no-crop, not-via-outbox all honored. DRY header addressed via the shared `ProfileBannerHeaderView` (T5→T6).
- **Type consistency:** `bannerUrl: String?` (record/struct), `banner: String?` (service/importer params), `bannerUrl: URL?` + `bannerEdited: Bool` (VM), `ProfileBannerHeaderView` used identically in T5/T6.
- **No LemmyKit change** (the `SaveUserSettings.banner` param already exists) — confirmed in the spec.
