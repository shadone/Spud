# Spud — Full-Parity App Store Release Plan

Goal: ship Spud to the App Store as a **full-featured Lemmy client** (feature parity with
mature clients: read, vote, comment, post, save, subscribe, search, inbox/DMs, moderation,
push). Scope decision (2026-06-12): **Full parity** before first submission.

Status baseline (verified 2026-06-12):

- Builds clean — Xcode 26.3, iOS 18 min, Swift 6 strict concurrency, 0 errors.
  (Headless builds: `swift-openapi-generator` plugin is now trusted; add
  `-skipMacroValidation` only if a macro-fingerprint prompt appears.)
- Tests 36/36 green; 1 UI test stubbed (`LinkLabel` a11y).
- Architecture is modern and done: UIKit + coordinators + `@Observable`, GRDB persistence,
  AsyncStream reactive, modular frameworks, OpenAPI `LemmyKit` 0.4.0.
- Today Spud is a **read + vote** client. `LemmyService` exposes only `fetchFeed`,
  `fetchComments`, `fetchPersonInfo`, `vote`, `fetchPostInfo`, `markAsRead`.

## Critical path & risk register

Good news first: **the API layer is not the bottleneck.** `Lemmy.yaml` already defines every
operation we need, so each feature is "wire `LemmyService` + GRDB mirror + UI", not "extend the
spec + regenerate". Regeneration is only needed if an endpoint shape is wrong in practice.

Real risks, highest first:

1. **Push notifications (R-HIGH).** Lemmy has no native push. Real push requires an external
   relay (poll-and-APNs backend, or UnifiedPush). This is infra + a server you must run and
   keep alive — the single heaviest item. **Recommendation: ship v1.0 with in-app inbox +
   background-refresh badge; treat true APNs push as a fast-follow (M7), not a launch blocker.**
2. **Image upload (R-MED).** `uploadImage` (pict-rs) is multipart/form-data with an auth'd
   session. Verify swift-openapi-urlsession handles the multipart body cleanly; if not, a small
   hand-written multipart client in `SpudDataKit` is the fallback. De-risk with a spike in M1.
3. **Guideline 4.2 over many half-features (R-MED).** Parity means lots of surfaces; any one
   shipped half-built reads as "incomplete". Each milestone must land a feature *fully* (happy
   path + empty/error + sign-in gating + a test) before moving on. No visible dead UI at submit.
4. **Write actions need a real (non-signed-out) account (R-LOW).** Every write path needs a
   consistent "Sign in to do this" affordance. Build the gating helper once in M1, reuse it.

## The spine (build once in M1, everything depends on it)

- `LemmyService` **write layer**: auth'd POST wrappers with JWT from the active account,
  optimistic local mutation → GRDB → server confirm → reconcile-on-failure.
- A reusable **mutation result + error surface** (toast/alert via existing `AlertService`).
- A **`requireSignedInAccount()`** gate used by every write entry point.
- A **composer** infrastructure (markdown text view, submit/cancel, attach-image hook) reused by
  comment reply, post create, edit, and DM compose.

---

## Milestones

Each milestone is independently shippable to TestFlight. Order is dependency-driven; estimates
assume solo dev with AI assist.

### M0 — Submission hygiene (must-do, unblocks archiving) — ~3–5 days
- [x] App icon: placeholder full-bleed opaque 1024 icon for app **and** widget, single-size
      `AppIcon.appiconset`. **Replace with final art before submission.** (Verified in bundle.)
- [ ] **B2** Remove `SBTUITestTunnelServer` from the **Spud app target**; link it only into
      `SpudUITests`. Verify it is absent from a Release archive's binary. **→ folded into M0.5.**
- [x] Add `PrivacyInfo.xcprivacy` (UserDefaults required-reason `CA92.1`, tracking = false).
      Added to Spud target; verified present in built `.app`.
- [x] `ITSAppUsesNonExemptEncryption = NO`; `LSApplicationCategoryType = social-networking`.
- [x] App name "Spud" final; `CFBundleDisplayName = Spud`. (Verified in built `.app`.)
- [ ] Produce a real archive; run App Store Connect validation to surface anything else early.

### M0.5 — Adopt XcodeGen (DONE 2026-06-12) — verified build + 36/36 test parity
Replaced hand/script-patched `project.pbxproj` with a declarative `project.yml`.
- [x] `project.yml` authored for all 11 targets (app, 2 extensions, 3 frameworks, 5 test targets).
- [x] **LemmyKit declared as a local package** (`path: ../LemmyKit`); bare project resolves it
      locally — "always open the workspace" footgun retired. DiasporaNodeInfo dropped (unused —
      imported nowhere).
- [x] Reproduced: SwiftGen pre-build script on SpudUIKit, both entitlements files (via
      `CODE_SIGN_ENTITLEMENTS`), app group + keychain capabilities, both test plans (with target
      UUIDs re-patched), schemes, per-target Swift modes, iOS 18, automatic signing.
- [x] `Spud.xcworkspace` removed; generated `.xcodeproj` gitignored + untracked; `Makefile`
      (`make project` / `make bootstrap`) added; README + both CLAUDE.md updated.
- [x] Acceptance met: `make project` reproduces the project; fresh build `BUILD SUCCEEDED`;
      `Spud` test plan 36/36 pass.
- Residuals: **B2 still open** (app still links `SBTUITestTunnelServer`) — now a trivial
  `project.yml` dependency edit, but the Debug UI-test tunnel needs it, so settle Debug-only
  linkage vs replacing SBT. CI/headless `xcodebuild` needs `-skipPackagePluginValidation
  -skipMacroValidation` (openapi-generator plugin). SpudUITests perf `.xcbaseline` not carried
  over (no active perf test, no impact).

### M1 — Write foundation + spike (the spine) — ~1 week
Auth already works (keychain `LemmyCredential{jwt}` per `accountKeychainId` →
`LemmyApi(credential:)` → `AuthorizationMiddleware` signs every request). Mutations follow the
existing **non-optimistic** `vote()` template: call the server, then mirror the confirmed
response into GRDB; the GRDB observation updates the UI. No optimistic/rollback machinery.
- [ ] **LemmyKit endpoint wrappers** — add `LemmyApi+CreateComment.swift` (then `+SavePost`,
      `+FollowCommunity`, … per feature) following the `LemmyApi+LikePost.swift` pattern. Paired
      LemmyKit commits; trivial now that it's a local package.
- [ ] **`LemmyService` write methods** following `vote()`: call `api.x(...)`, then
      `mirror…ToAppDatabase` (reuse `upsertPost`/`upsertComment`).
- [ ] **Sign-in gate** — `accountIsSignedOut` guard + `LemmyServiceError.requiresAuthentication`;
      UI affordance ("Sign in to comment") instead of a silent no-op.
- [ ] **Real error surfacing** — `AlertService` currently only logs. Return write errors to the
      view layer (or have AlertService present a `UIAlertController`); add `AlertHandlerRequest`
      cases. Required before any write ships.
- [ ] **Composer** (greenfield) — `UITextView` compose surface + live `Down`/`LinkLabel` markdown
      preview, `@Observable` VM via `ObservationStream`. Reused by reply / post / edit / DM.
- [ ] Spikes: confirm `uploadImage` multipart works through the generated client; confirm
      `createComment` round-trips against a live instance.
- [ ] Test fakes in `SpudDataKitTests` for the new write methods.

First build — **comment-reply vertical slice: DONE 2026-06-12, verified (build + tests green).**
Shipped: `LemmyApi+CreateComment` (LemmyKit) + test-seam init; `LemmyService.createComment`
(sign-out guard → `requiresAuthentication` → confirm-then-mirror via unified
`mirrorCommentToAppDatabase`); `ComposerViewController` sheet + `@Observable` VM (`ComposerTarget`
extensible to post/edit/DM); reusable `ErrorMessage` + `presentErrorAlert`; reply wired in
PostDetail (swipe + context menu + post-level button, sign-in gated); 2 new SpudDataKitTests.
The spine is proven — remaining M1/M2 writes reuse this pattern.
Follow-up (small): composer has no live markdown **preview pane** yet (surface is preview-ready).

### M2 — Core interactions — ~1.5–2 weeks
- [ ] **Comment + reply composer** (reply to post and to comment; edit + delete own).
- [ ] **Save / unsave** post and comment; wire the existing trailing swipe action; Saved list.
- [ ] **Subscribe / unsubscribe** communities; reflect in Subscriptions sidebar live.
- [ ] **Share** sheet for post/comment/community URLs (the other dead swipe action).
- → First external TestFlight beta can start here.

### M3 — Discovery & account — ~2 weeks
- [ ] **Search**: posts / comments / communities / users, with type filter + sort. Replace the
      placeholder `SearchViewController`.
- [ ] **Real community screen**: header, about, subscribe button, mod list, sort, sidebar.
- [ ] **Real Account screen** (replace placeholder): profile, your posts/comments, saved,
      settings entry, logout. Flesh out `PersonViewController` (user posts/comments tabs).
- [ ] **Registration / signup** flow (spec has `register`; handle captcha + email-verify states).

### M4 — Inbox & messaging — ~1.5–2 weeks
- [ ] **Inbox**: replies, mentions, with read/unread + mark-all-read; unread badge on tab.
- [ ] **Private messages**: list + thread + compose (`getPrivateMessages`/`createPrivateMessage`).
- [ ] Background-refresh to update unread counts (App Refresh task), no server needed.

### M5 — Content creation — ~1.5 weeks
- [ ] **New post composer**: URL / text / image post types, community picker, NSFW flag.
- [ ] **Image upload** to pict-rs (depends on M1 spike); attach to posts and comments.
- [ ] **Full-screen image viewer** (zoom/pan/share/save) for thumbnails and inline images.

### M6 — Safety & moderation — ~1.5–2 weeks
- [ ] **Block / unblock** person and community; blocked-list management in settings.
- [ ] **Report** post and comment (`createPostReport`/`createCommentReport`).
- [ ] **Hide / mark-read** behaviour: implement the currently-stubbed preference logic
      (`PreferencesPostMarkingAndHidingView`) end to end, or remove if descoped.
- [ ] **Moderation actions** for mods/admins: remove/lock/feature/distinguish, ban from
      community, mod-only views. Gate by permission from site/community info.

### M7 — Push notifications (fast-follow candidate) — ~2–3 weeks (incl. backend)
- [ ] Decide approach: self-hosted poll→APNs relay vs UnifiedPush vs defer.
- [ ] APNs entitlement + capability in App Store Connect; device-token registration.
- [ ] Notification service: replies, mentions, DMs; deep-link into the right scene.
- [ ] **Note:** this introduces a server you must operate. Strongly consider launching v1.0
      without it (inbox + badge cover the need) and adding in v1.1.

### M8 — Polish & platform — ~1.5–2 weeks
- [ ] **iPad + landscape** layout pass (currently snapshot-locked to iPhone portrait).
- [ ] Empty / error / loading / offline / rate-limit states across all scenes.
- [ ] **Accessibility**: re-enable the `LinkLabel` VoiceOver fix (expose each link range as a
      child element); Dynamic Type; VoiceOver sweep; re-enable `test_PostDetail_TapOnPostCreator`.
- [ ] `OpenInAppExtension`: implement real Lemmy-URL routing into the app (currently a stub).
- [ ] Acknowledgements screen (third-party licenses); refresh snapshot baselines.
- [ ] Dark mode / theme + text-size preferences if in parity scope.

### M9 — Beta → submit — ~1 week + review
- [ ] Internal then external TestFlight; triage crash/feedback (use ASC crash triage).
- [ ] Screenshots (all required device sizes), description, keywords, **privacy-policy URL**,
      **support URL**, App Privacy questionnaire, category, age rating.
- [ ] Final archive, validate, submit for review.

---

## Store-blocker checklist (gates first upload — from M0)

- [ ] B1 App icon present (app + widget, incl. 1024).
- [ ] B2 `SBTUITestTunnelServer` not linked into the app binary.
- [ ] B3 `PrivacyInfo.xcprivacy` present and accurate.
- [ ] S1 `ITSAppUsesNonExemptEncryption = NO`.
- [ ] S2 Final name + `CFBundleDisplayName`.
- [ ] S3 Privacy-policy URL + support URL exist (web pages).
- [ ] S4 `LSApplicationCategoryType` set.

## Cross-cutting (apply every milestone)

- Each feature: happy path + empty/error states + sign-in gating + at least one unit or UI test.
- Keep `SpudDataKitTests` fakes in lockstep with new `LemmyService` methods.
- Conventional commits, small focused PRs; a Spud feature may need a paired LemmyKit commit only
  if an endpoint shape proves wrong.
- Maintain Swift 6 strict concurrency cleanliness (no new warnings).

## Decisions (2026-06-12)

- **App name: "Spud"** — placeholder is now final. Set `CFBundleDisplayName = Spud`.
- **Push: deferred to v1.1** — v1.0 ships in-app inbox + background-refresh badge, no relay server.

## Open decisions

1. **Default instance** — keep `discuss.tchncs.de` bootstrap, or a neutral landing/instance picker on first run?
2. **Minimum iOS** — stay at 18.0 (narrower install base, simplest concurrency story) or lower to 17?
3. **Moderation depth** — full mod/admin tooling at launch, or mod-read + basic actions, rest in v1.1?

## Suggested first two weeks

1. M0 in full (unblocks archiving + first TestFlight pipeline).
2. M1 spine + the `uploadImage`/`createComment` spikes (de-risks everything downstream).
3. Stand up the TestFlight internal build so real-device feedback runs in parallel from M2 on.
