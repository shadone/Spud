# Spud — Full-Parity App Store Release Plan

Goal: ship Spud to the App Store as a **full-featured Lemmy client** (read, vote, comment, post,
save, subscribe, search, inbox/DMs, moderation, push) whose **UI/UX is at least on par with
Apollo for Reddit** — see `DESIGN.md` for the quality bar every feature is built to.
Scope decision (2026-06-12): **Full parity** before first submission; **active build target:
M1–M5 + adjacent UX-polish**, feature-by-feature, each increment verified and committed.

## Build progress — M1–M6 + M8 shipped (2026-06-12, on branch `app-store-prep`)

All verified (build + tests green; final full test plan passed across all targets) and committed
in focused paired commits (Spud + LemmyKit). Every feature built to the `DESIGN.md` Apollo bar
(haptics, sign-in gating, designed empty/error/loading states, confirm-then-mirror data path).

- **M0** store-blockers (icon, privacy manifest, Info.plist keys) + **M0.5** XcodeGen migration.
- **M1** comment replies + markdown composer (formatting toolbar + live preview).
- **M2** save/unsave, subscribe/unsubscribe, saved feed, share posts/comments.
- **M3** search (posts/communities/users/comments), real community screen, real Account screen,
  Person profiles (posts/comments), registration.
- **M4** inbox (replies/mentions), private-message threads, live unread badge.
- **M5** new-post composer, pict-rs image upload (hand-written multipart, unit-tested),
  full-screen media viewer (zoom/pan/swipe-to-dismiss/save/share).
- **M6** block/unblock (person + community) + blocked-list management, report post/comment,
  hide/mark-read filter wired end to end, moderator/admin actions gated by site capability.
- **M8** theme system (light/dark/true-black OLED + accent), post/comment density, thumbnail
  side, selectable app icons, configurable swipe actions, Acknowledgements, `LinkLabel`
  VoiceOver pass, and the **iPad + landscape split-view handoff** (collapse/expand keeps the
  detail on screen; regression-tested on a Max-class iPhone). `OpenInAppExtension` routes real
  Lemmy URLs into the app via the `info.ddenis.spud://internal/...` deep-link path.
- **Adjacent UX**: comment tap/swipe collapse + depth rails + jump-to-next, shared `Haptics`,
  markdown editor, app-wide empty states.

Out of shipped scope: M7 push (deferred to v1.1), M9 archive + metadata + **B2** (SBT-server out
of the Release binary, Debug-only linkage — archive-stage). Smaller follow-ups noted per-section
below.

## Post-parity UX & performance polish (2026-06-12, branch `app-store-prep`)

Closing the remaining gaps to the `DESIGN.md` Apollo bar after M8 — each verified
(build + full `Spud` test plan green) and committed focused:

- **perf(comments)** off-main markdown cache (`MarkdownRenderer`): comment and
  post-header bodies parse off the main thread and cache, pre-warmed before the
  diffable snapshot is applied, so long threads scroll without cmark hitches.
- **perf(feed)** thumbnail prefetch via `UITableViewDataSourcePrefetching` — no
  image pop-in on fast scroll.
- **perf(images)** off-main bitmap decode (`byPreparingForDisplay`) so images
  draw without a main-thread decode hitch.
- **feat(media)** animated GIF playback in the full-screen viewer
  (`AnimatedImageDecoder` + `ImageService.fetchAnimatedImage`), `.gif` detection,
  and a "GIF" badge (`MediaBadgeView`) on feed + header thumbnails.
- **feat(ux)** context-menu peek on feed posts (`PostPreviewViewController`):
  long-press shows image + title + full body.
- **feat(feed)** external-link posts show their embed thumbnail inline
  (`Thumbnail.linkImage`) instead of a generic placeholder; tapping opens the
  post (the embed isn't the content). Thumbnail derivation extracted to the
  testable `PostListPostViewModel.thumbnail(for:)`.
- **perf(images)** target-size downsampling (`ImageDownsampler` +
  `ImageService.fetch(_:downsampleTo:)`): feed thumbnails decode straight to the
  64pt cell size instead of loading a full-resolution bitmap.
- **feat(media)** inline **video** (mp4/mov/m4v): new `PostContentType.video`,
  played in the system `AVPlayerViewController`; feed/header show the poster +
  play indicator. webm stays an external link (no native AVFoundation decoder),
  so it opens in the browser instead of a dead player.
- **feat(media)** preserve GIF animation on save and share: the viewer keeps the
  original GIF bytes (`ImageService.animatedImageData`, cached alongside the
  decoded animated image) and, for animated items, saves via
  `PHAssetCreationRequest.addResource(.photo, data:)` and shares a temporary
  `.gif` file — so an animated post saves/shares as an animated GIF, not a flat
  first frame. `MediaViewerShareTests` locks the temp-filename `.gif` derivation.

Follow-ups: context-menu peek on comments was considered and dropped (comments
aren't truncated in the detail view, so there's nothing to peek).

Verification note: the feed thumbnail media affordances (image, "GIF" badge,
video play indicator, text/broken placeholders) are now rendered and reviewed
via `MediaUISnapshotTests` (device-independent snapshots, 5 references) — both
eyeballed and regression-locked. The context-menu peek (`PostPreviewViewController`)
was reviewed the same way during development and renders correctly, but its
self-sizing relies on a multi-pass label layout the system drives in production
and a synthetic harness reproduces only flakily, so it is verified by eye rather
than pinned; its view carries a `postPreview` accessibility id for manual
inspection. Video *playback* and the GIF Photos save/share round-trip remain
device-only checks (no simulator assertion path) — a human eyeball pass on those
is worthwhile before submission. XCUITest cannot see live context-menu preview
content (separate system view).

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

### M6 — Safety & moderation — DONE 2026-06-12
- [x] **Block / unblock** person and community; blocked-list management in settings.
- [x] **Report** post and comment (`createPostReport`/`createCommentReport`).
- [x] **Hide / mark-read** behaviour: `PreferencesPostMarkingAndHidingView` wired end to end
      through `HideReadPostsFilter` + `PostListViewController` + `PreferencesService`.
- [x] **Moderation actions** for mods/admins: gated by `fetchModerationCapability()` from
      site info (`LemmyService+Moderation.swift`).

### M7 — Push notifications (fast-follow candidate) — ~2–3 weeks (incl. backend)
- [ ] Decide approach: self-hosted poll→APNs relay vs UnifiedPush vs defer.
- [ ] APNs entitlement + capability in App Store Connect; device-token registration.
- [ ] Notification service: replies, mentions, DMs; deep-link into the right scene.
- [ ] **Note:** this introduces a server you must operate. Strongly consider launching v1.0
      without it (inbox + badge cover the need) and adding in v1.1.

### M8 — Polish & platform — DONE 2026-06-12 (snapshot baselines: follow-up)
- [x] **iPad + landscape** layout pass: split-view collapse/expand handoff keeps the post detail
      on screen across size-class changes; `test_PostDetail_SurvivesRotationHandoff` guards it.
- [x] Empty / error / loading states across scenes (designed states per `DESIGN.md`).
- [x] **Accessibility**: `LinkLabel` exposes each link range as a child element; Dynamic Type;
      `test_PostDetail_TapOnPostCreator` re-enabled.
- [x] `OpenInAppExtension`: routes real Lemmy URLs into the app via `info.ddenis.spud://internal`.
- [x] Acknowledgements screen (third-party licenses).
- [x] Theme (light/dark/true-black + accent), density, thumbnail side, selectable app icons,
      configurable swipe actions.
- [ ] Follow-up: refresh snapshot baselines on iPhone 14 Pro / portrait once UI has settled;
      offline / rate-limit specific states.

### M9 — Beta → submit — ~1 week + review
- [ ] Internal then external TestFlight; triage crash/feedback (use ASC crash triage).
- [ ] Screenshots (all required device sizes), description, keywords, **privacy-policy URL**,
      **support URL**, App Privacy questionnaire, category, age rating.
- [ ] Final archive, validate, submit for review.

---

## Store-blocker checklist (gates first upload — from M0)

- [x] B1 App icon present (app + widget, incl. 1024) + 4 selectable alternates.
- [~] B2 `SBTUITestTunnelServer` linkage. **Runtime-safe today**: `takeOff()` is `#if DEBUG`,
      so the embedded GCDWebServer never opens a socket in Release — no auto-reject risk from a
      running listener. **But** the library still ships in the Release binary (verified: a
      Release build contains ~229 SBT/GCDWebServer symbols). Root cause: SwiftPM links static
      products wholesale and XcodeGen 2.45 can't scope a package product to one configuration
      (`link: false` also removes the module, breaking the Debug `import`). To get it fully out
      of the archive, pick one at M9: (a) wrap the server in a Debug-only dynamic framework the
      app embeds only in Debug; (b) move UI-test tunneling to a mechanism that doesn't embed a
      server in the app; or (c) drop the `import` and call `takeOff` via the Obj-C runtime with a
      Debug-only manual `-l` link + explicit search path. See the note in `project.yml`.
- [x] B3 `PrivacyInfo.xcprivacy` present and accurate.
- [x] S1 `ITSAppUsesNonExemptEncryption = NO`.
- [x] S2 Final name + `CFBundleDisplayName` (Spud).
- [ ] S3 Privacy-policy URL + support URL exist (web pages) — needs hosted pages.
- [x] S4 `LSApplicationCategoryType` set (social-networking).

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
