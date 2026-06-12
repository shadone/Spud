# Spud — session handoff (2026-06-12, cont.)

Branch: `app-store-prep` (Spud repo). Tree clean. Build green (0 errors,
1 benign SwiftGen Copy-Headers sandbox warning). Full `Spud` test plan green
(SpudDataKitTests 99, SpudUtilKitTests 43, SpudTests incl. MediaViewerShareTests,
SpudUITests — all 0 failures, ** TEST SUCCEEDED **, 2026-06-12 17:41). Goal:
App Store release + full Apollo-bar UI/UX parity (see DESIGN.md).

## Done this session — post-M8 UX & performance polish (17 commits)
Closing the remaining `DESIGN.md` gaps. Each verified (build + full plan) and
committed focused. Newest first:

- `b07ebfe` test(ui): `test_CaptureScreens` renders the feed then post detail
  full-screen as kept XCTAttachments (review end-to-end UX vs Apollo without a
  device). Extract with `xcrun xcresulttool export attachments --path <xcresult>
  --output-path <dir>` (needs `-resultBundlePath`). Reviewed: feed = floating
  pill tab bar + compact info-dense rows; detail = hero image, attribution,
  vote/save row, threaded comments with depth bars. Both Apollo-grade. Full Spud
  plan green WITH this test (SpudUITests incl. it, all bundles 0 failures).
- `0beb5dc` test(media): snapshot the feed thumbnail media affordances.
  `MediaUISnapshotTests` renders the thumbnail states (image, "GIF" badge, video
  play indicator, text, broken) to pinned-scale (64pt @2x) device-independent
  references — both eyeballed and regression-locked, 5 green. NOTE: peek
  (`PostPreviewViewController`) snapshots were prototyped and the peek renders
  correctly by eye (image peek = image + 2-line title + caption), but its
  self-sizing relies on a multi-pass label layout that a synthetic harness only
  reproduces flakily (title truncates to 1 line in the text-only case), so the
  peek is verified by eye, not pinned. Snapshot refs are fixed-size/2x so they do
  NOT need iPhone 14 Pro (unlike the screen-sized markdown snapshots); ran the
  class via `-only-testing:SpudSnapshotTests/MediaUISnapshotTests` on iPhone 17 Pro.
- `21a0414` feat(media): preserve GIF animation on save and share. Viewer kept
  saving/sharing `zoomableImageView.image` (flattened first frame).
  `ImageService.animatedImageData` vends the original GIF bytes (cached in a new
  `animatedDataCache` alongside the decoded animated image); for animated items
  the viewer saves via `PHAssetCreationRequest.addResource(.photo, data:)` and
  shares a temporary `.gif` file. Protocol method has a nil default so fakes are
  unaffected. `MediaViewerShareTests` (5) locks the temp-filename `.gif`
  derivation. Photos write + share sheet themselves need a device eyeball.
- `f42512c` / `c89e7d2` docs(plan): recorded this polish pass in RELEASE-PLAN.md.
- `92356c6` perf(images): target-size downsampling. `ImageDownsampler` (ImageIO
  thumbnail) + `ImageService.fetch(_:downsampleTo:)` (size-keyed cache). Feed
  thumbnail + prefetch request the 64pt cell size (`PostListPostCell.thumbnailDimension`).
  Protocol method with a full-res default so the viewer + fakes are unaffected.
  ImageDownsamplerTests.
- `0e64633` feat(feed): external-link posts show their embed thumbnail inline
  (`Thumbnail.linkImage`); tap opens the post, not the image viewer. Derivation
  extracted to testable `PostListPostViewModel.thumbnail(for:)`. Tapping a text
  placeholder now opens the post too (was a no-op). PostListPrefetchTests extended.
- `f1f21d0` feat(ux): context-menu PEEK on feed posts — `PostPreviewViewController`
  (image + title + full body, body via the MarkdownRenderer cache, self-sizing via
  `preferredContentSize`), wired as the feed context menu's `previewProvider`.
  NOTE: could not visually verify the peek's appearance — `idb` is broken on this
  machine (Python 3.14) so no tap automation, and UI tests don't exercise
  context-menu previews. Build + regression green; needs a human eyeball.
- `0ba25df` feat(media): "GIF" badge on feed + header thumbnails (`MediaBadgeView`,
  `URL.isAnimatedImage` helper in SpudUtilKit).
- `edcdce4` feat(media): animated GIF playback in the full-screen viewer.
  `AnimatedImageDecoder` (ImageIO frame decode + GIF frame delays) +
  `ImageService.fetchAnimatedImage` (separate animated NSCache so inline stays a
  static frame). `.gif` detection in `PostContentDetectorService` (Image.isAnimated).
  Protocol method added with a static-image default so test fakes are unaffected.
  Tests: PostContentDetectorTests, AnimatedImageDecoderTests.
- `3c2acfd` perf(images): off-main bitmap decode via `byPreparingForDisplay()` in
  the ImageService fetch task (kills the main-thread decode hitch on scroll).
- `99e64c1` perf(feed): thumbnail prefetch (`UITableViewDataSourcePrefetching`) —
  no image pop-in on fast scroll. `PostListPostViewModel.prefetchThumbnailUrl` +
  PostListPrefetchTests.
- `4aa960a` perf(comments): off-main markdown cache (`MarkdownRenderer`). Comment +
  post-header bodies parse off-main and cache; pre-warmed before the diffable
  snapshot. NSAttributedString never crosses a concurrency boundary (each thread
  reads its own ref from the thread-safe NSCache). MarkdownRendererTests; Down
  linked into SpudTests.

- `d77b185` feat(media): inline VIDEO (mp4/mov/m4v). New `PostContentType.video`;
  plays in the system `AVPlayerViewController` (`UIViewController.presentVideoPlayer`).
  Feed thumbnail + header show poster + centred play indicator (`play.circle.fill`);
  peek shows poster too. webm intentionally stays an external link (AVFoundation
  can't decode it — opens in browser, no dead player). Detection + thumbnail
  derivation unit-tested. NOTE: playback itself not UI-verified (no video assert
  path on the sim) — build + detection verified; eyeball before submission.

## Follow-ups (noted in RELEASE-PLAN.md)
- Context-menu peek on comments: considered and dropped — comments aren't
  truncated in the detail view, so there's nothing to peek.

## Verification gaps (platform limitations, not bugs)
- Feed thumbnail affordances: now snapshot-verified (`MediaUISnapshotTests`, 5
  refs) — eyeballed + regression-locked. No longer a gap.
- Context-menu peek (`PostPreviewViewController`): visually verified by eye via a
  prototype snapshot (renders correctly), but NOT pinned — its self-sizing needs a
  multi-pass label layout the system drives in production and a synthetic harness
  only reproduces flakily. XCUITest also can't see live context-menu previews
  (separate system view). The peek view has a `postPreview` a11y id for manual
  inspection. Snapshot-rendering the peek deterministically would need hosting it
  the way the system does (estimated size first, then settle) — left for later.
- Video PLAYBACK and the GIF Photos save/share round-trip: device-only checks (no
  sim assertion path). GIF temp-filename derivation is unit-tested
  (`MediaViewerShareTests`); the Photos write + share sheet need a device eyeball.

## Milestone state (unchanged from prior handoff)
- M1-M6 + M8: DONE. M7 push deferred to v1.1. M9 (archive + ASC metadata +
  screenshots + privacy/support URLs + submit): NOT started — needs the user.
- B2 (SBTUITestTunnelServer in Release binary): still open, archive-stage. App is
  runtime-safe (`takeOff()` is `#if DEBUG`). See project.yml note + RELEASE-PLAN B2.

## Env gotchas (still current)
- Build wrapper: `dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py`.
  `--test --suite SpudDataKitTests` (bare target) mis-routes to "My Mac" and fails
  ("Unit tests without a host app"); run via the Spud test plan + `-only-testing`
  with a simulator destination, or the full plan, instead.
- `idb` BROKEN (Python 3.14) — no tap automation; use XCUITest for interaction.
- Keep only ONE simulator booted: two booted sims caused a UI-test launch flake
  ("SBMainWorkspace Busy / Application failed preflight checks"). Shutting down the
  extra sim cleared it.
- New files need `make project` (XcodeGen) before they're in the build.
- Format before staging: `mint run swiftformat <paths>` (pre-commit hook lints only).
- Snapshot tests of fixed-size components (pass `as: .image(size:traits:)` with a
  pinned `displayScale`) are device-independent — they do NOT need iPhone 14 Pro
  and can record/verify on the booted iPhone 17 Pro via
  `-testPlan SpudSnapshots -only-testing:SpudSnapshotTests/<Class>`. Only the
  screen-sized VC snapshots (MarkdownSnapshotTests) are locked to iPhone 14 Pro.
  First run with no reference records-and-fails; re-run to assert green.
