# Markdown Renderer — Phase 6 (Integration into Spud) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the old `BodyTextView` body rendering with the new `SpudMarkdownKit` `MarkdownBodyView` at the **post-detail header body** and **comment bodies**, wiring the `MarkdownBodyDelegate` to the app's existing navigation / media / haptics, preserving the off-main parse + cache + pre-warm pattern, and resolving the `spud-markdown://` ↔ `info.ddenis.spud://` scheme mismatch — leaving person bios / community descriptions / composer preview on the existing path (out of scope this round).

**Architecture:** Each in-scope cell hosts a `MarkdownBodyView` instead of a `BodyTextView`. The view-models carry the parsed `[MarkdownBlock]` (parsed + cached off-main, replacing the cached `NSAttributedString`). A host-side scheme adapter translates the framework's mention/community URLs to the app's internal-link scheme before the existing `linkTapped` routing. The framework's `ImageBlockView` gains the deferred `onContentSizeChange` firing so cached-height cells re-measure on async image load. Image/video/audio taps route to the existing `presentMediaViewer` / `presentVideoPlayer`.

**Tech Stack:** Swift 6, UIKit (UITableView diffable, self-sizing cells), SpudMarkdownKit, GRDB-backed view-models, XcodeGen. Worktree: `/Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration` (branch `markdown-renderer-integration`, off main `3931a30`).

---

## Scope (confirmed)

IN: post-detail **header body** (`PostDetailHeaderCell` + `PostDetailHeaderViewModel`) and **comment bodies** (`PostDetailCommentCell` + `PostDetailCommentViewModel`); the `PostDetailViewController` delegate routing + pre-warm; the scheme adapter; the `ImageBlockView` content-size follow-up.
OUT (left on the existing `MarkdownRenderer`/`BodyTextView` path): person bios (`PersonHeaderView`), community descriptions (`CommunityHeaderView`), composer preview (`MarkdownEditorView`). Do NOT remove `BodyTextView`, `MarkdownRenderer`, or `MarkdownRenderer.imageBody` — they remain used by the out-of-scope sites.

## Integration map (from the Phase-6 exploration — verify each file:line before editing; the tree is main `3931a30`)

- Post body: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift` (`bodyLabel: BodyTextView` ~L151-165; `attributedText` assign ~L487; `imageService` ~L486; `onContentSizeChange` → `tableView.beginUpdates()/endUpdates()` ~L160-163; `imageTapped` ~L29 → `presentMediaViewer` ~L1439/863; `videoTapped` ~L33 → `presentVideoPlayer` ~L1447). ViewModel `PostDetailHeaderViewModel.swift` (`body: NSAttributedString` ~L33; `MarkdownRenderer.shared.imageBody(...)` ~L109-112).
- Comment body: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` (`messageLabel: BodyTextView` ~L183-194; collapsed hides body ~L408; `onBodyImageLoaded` → `tableView.performBatchUpdates(nil)` ~L190-191/1506; `linkTapped` ~L187). ViewModel `PostDetailCommentViewModel.swift` (`body: NSAttributedString` ~L36; `imageBody(...)` ~L229-231).
- Link routing: `PostDetailViewController.swift` `linkTapped(_:)` ~L693-725 (switch on `url.spud`; falls back to `LemmyURLParser.classify(url:isKnownInstance:)` ~L719; else open external). `URL.spud` decoder: `SpudUtilKit/Extensions/URL+spud.swift` (scheme `info.ddenis.spud`, host `internal`). `URL.SpudInternalLink` cases (`.person(personId:instance:)`, `.community(name:instance:)`, …) each have a `.url`.
- Media: `presentMediaViewer(imageUrl:thumbnailUrl:preloadedImage:altText:)` ~L863; `presentVideoPlayer(url:)` `Spud/Utils/UIViewController+VideoPlayer.swift`.
- Cache/pre-warm: `Spud/Utils/MarkdownRenderer.swift` (`NSCache`, `imageBody`, keys); `PostDetailViewController.prewarmCommentBodies(...)` ~L443-457 called ~L391-394 before snapshot apply.
- Cells size via `UITableView.automaticDimension`, diffable datasource, re-measure via `begin/endUpdates` / `performBatchUpdates`.
- Framework API: `MarkdownBodyView(context:)`, `.setBlocks([MarkdownBlock])`, `.delegate`, `.imageLoader: @MainActor (URL) async -> UIImage?`; `MarkdownParser.parse(_:) -> [MarkdownBlock]`; delegate `markdownBody(didTapLink:)/(didTapImage:altText:sourceRect:)/(didTapVideo:)/(didTapAudio:)`.
- Scheme mismatch: `SpudMarkdownKit/Rendering/InlineAttributedStringBuilder.swift` emits `spud-markdown://mention?name=&instance=` and `spud-markdown://community?name=&instance=`; the app routes `info.ddenis.spud://internal/...`. Bridge in the host (Task 2).

## Conventions (every task)

BSD-2-Clause header on new files. **`make project` before every build/test.** Format before commit: `mint run swiftformat <dirs>`. `git status -uall`; stage explicit paths; never `git add -A`; don't touch `.remember/remember.md`. No emojis. Canonical app build/test:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration
make project
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -12
```
**Verification strategy note:** the app's snapshot tests (`SpudSnapshotTests`) are git-annex-backed and fragile in this worktree (see Phase-5 note), and re-recording the PostDetail* snapshots is deferred. So Phase-6 verification leans on: (1) clean BUILD, (2) the relevant UNIT tests (`SpudTests`, the new adapter/cache tests), and (3) a SIMULATOR eyeball of a real post + comment thread. Do NOT block a task on `SpudSnapshotTests` annex resolution; note any such failure as the known artifact.

---

## Task 1: ImageBlockView fires onContentSizeChange (SpudMarkdownKit)

**Files:** Modify `SpudMarkdownKit/Rendering/ImageBlockView.swift`, `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift`; Modify `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift`

So a cached-height host cell re-measures when an image finishes loading (loading placeholder → natural-aspect image / failed plate changes the view height). The renderer already has an `onContentSizeChange: (() -> Void)?` seam used by `SpoilerBlockView`; thread it into `ImageBlockView` too.

- [ ] **Step 1: Pass the callback into ImageBlockView.** In `MarkdownBlockRenderer.view(for:)` `.image` case, pass the renderer's `onContentSizeChange` into the `ImageBlockView` initializer (add an `onContentSizeChange: (() -> Void)?` parameter to `ImageBlockView.init`, defaulting/threaded from `self.onContentSizeChange`). Read the current `.image` case + `SpoilerBlockView` (which already captures `renderer.onContentSizeChange`) to mirror the pattern exactly.

- [ ] **Step 2: Fire it after async load.** In `ImageBlockView`, store the callback; after the load `Task` resolves and calls `apply(state:)` (the loaded/failed transition that changes the aspect box), invoke `onContentSizeChange?()` (on the main actor, after layout invalidation). Do NOT fire it for the initial synchronous `.loading` apply in `init` (only after the async transition). Keep it minimal.

- [ ] **Step 3: Test the dispatch still type-checks + a behavioral check if cheap.** Add/keep a renderer test confirming `.image` still returns an `ImageBlockView`. If feasible, add a small test that constructs an `ImageBlockView` with a synchronous stub `loader` returning an image and an `onContentSizeChange` spy, and asserts the spy fires after the load resolves (you may need to pump the main run loop briefly, e.g. an `expectation` fulfilled in the callback). If a reliable async test is awkward, a build-verify + the existing dispatch test is acceptable — note it.

- [ ] **Step 4: Verify** the SpudMarkdownKit unit tests pass:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration && make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests test 2>&1 | tail -15
```
Expected `** TEST SUCCEEDED **` (snapshot tests may have the known annex artifact — run only `SpudMarkdownKitTests` here).

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): ImageBlockView fires onContentSizeChange after async load

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Mention/community scheme adapter (app)

**Files:** Create `Spud/Utils/MarkdownInternalLink.swift` (or the closest existing Utils home — read the dir first); Create `SpudTests/MarkdownInternalLinkTests.swift`

Translate the framework's `spud-markdown://mention?name=&instance=` / `spud-markdown://community?name=&instance=` URLs into the app's `URL.SpudInternalLink` (`.person` / `.community`) `.url`, so the existing `linkTapped` routing handles them unchanged.

- [ ] **Step 1 (TDD): Write tests** at `SpudTests/MarkdownInternalLinkTests.swift`. First READ `SpudUtilKit/Extensions/URL+spud.swift` for the exact `SpudInternalLink` case shapes + how instances are represented (e.g. `InstanceActorId` / a base-URL string) and how `.person`/`.community` build their `.url`; READ `SpudMarkdownKit/Rendering/InlineAttributedStringBuilder.swift` for the EXACT `spud-markdown://` URL shape it emits (host, query item names). Then test a translator `MarkdownInternalLink.resolve(_ url: URL) -> URL?` that:
  - given a `spud-markdown://mention?name=ada&instance=lemmy.world` returns the same `URL` that `URL.SpudInternalLink.person(...)` would produce for that handle (assert it round-trips through `url.spud` to the right case), 
  - given `spud-markdown://community?name=rust&instance=lemmy.world` returns the community internal URL,
  - given a non-`spud-markdown` URL returns `nil` (so the caller falls through to normal handling).
  Match the real API shapes you read (do not invent `InstanceActorId(from:)` if that's not the real initializer — use whatever the codebase actually uses to build a `.person`/`.community` link).

- [ ] **Step 2: Run to verify RED** (`-only-testing:SpudTests/MarkdownInternalLinkTests`). Expected: compile error or assertion failure (translator not implemented).

- [ ] **Step 3: Implement** `MarkdownInternalLink.resolve(_:)` to parse the `spud-markdown://` URL (scheme check, host = mention|community, `name`/`instance` query items) and return the corresponding `URL.SpudInternalLink.person/community(...).url`. Keep it pure + small.

- [ ] **Step 4: Run to verify GREEN.** `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat Spud SpudTests
git add Spud SpudTests
git commit -m "feat(markdown): adapter from spud-markdown:// to app internal links

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Off-main block parse + cache (app)

**Files:** Modify `Spud/Utils/MarkdownRenderer.swift` (add a blocks cache + parse helper) OR create `Spud/Utils/MarkdownBlockCache.swift`; Modify `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (pre-warm); Create `SpudTests/MarkdownBlockCacheTests.swift`

Preserve the proven off-main-parse + cache + pre-warm-before-snapshot pattern, but cache `[MarkdownBlock]` (Sendable) keyed by source markdown (parsing is context-independent; the `MarkdownContext` only affects rendering, not the block tree, so the cache key is just the markdown string + a version tag). Read `MarkdownRenderer.swift` to mirror its `NSCache` + key style.

- [ ] **Step 1 (TDD): Write tests** at `SpudTests/MarkdownBlockCacheTests.swift`: a `blocks(for: String) -> [MarkdownBlock]` helper returns `MarkdownParser.parse(source)` and caches by source (second call returns an equal result; the cache is populated). Assert equality of the returned blocks for the same input, and that distinct inputs parse distinctly. (Keep it simple — this mostly verifies the cache wrapper is wired to `MarkdownParser.parse`.)

- [ ] **Step 2: Verify RED**, then **Step 3: Implement** the blocks cache (an `NSCache<NSString, ...>` — wrap `[MarkdownBlock]` in a small reference box since `NSCache` needs a class value; or use a thread-safe dictionary with a lock mirroring `MarkdownRenderer`'s approach). Key: `"blocks.v1." + markdown`. Expose a `func blocks(for markdown: String) -> [MarkdownBlock]` that is safe to call off-main (parsing is pure/Sendable). **Step 4: Verify GREEN.**

- [ ] **Step 5: Update the pre-warm.** In `PostDetailViewController`, the existing `prewarmCommentBodies(...)` (nonisolated async, before snapshot apply) currently calls `MarkdownRenderer.shared.imageBody(...)`. Add (or switch the in-scope path to) pre-warming the BLOCK cache: for each post/comment body markdown, call the blocks-cache `blocks(for:)` off-main so the cells dequeue with a warm parse. Keep the existing `imageBody` pre-warm if/where still needed by out-of-scope sites; do not break them.

- [ ] **Step 6: Build + commit.**
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration && make project
xcodebuild -project Spud.xcodeproj -scheme Spud -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -8
mint run swiftformat Spud SpudTests
git add Spud SpudTests
git commit -m "feat(markdown): off-main block parse cache + pre-warm

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Post-detail header body → MarkdownBodyView

**Files:** Modify `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift`, `PostDetailHeaderViewModel.swift`, and `PostDetailViewController.swift` (delegate routing for the header body)

Replace the header `BodyTextView` with a `MarkdownBodyView`. READ all three files fully first; preserve everything around the body (layout, the non-body parts of the cell, the existing `imageTapped`/`videoTapped` for the post's MAIN media which is separate from inline body media — keep those intact).

- [ ] **Step 1: ViewModel** — give `PostDetailHeaderViewModel` the body as `[MarkdownBlock]` (parse via the Task-3 cache off the body markdown) instead of (or in addition to, transitionally) the `NSAttributedString` `body`. Keep the raw markdown available. Do not delete `imageBody` from `MarkdownRenderer` (out-of-scope sites use it).

- [ ] **Step 2: Cell** — replace `bodyLabel: BodyTextView` with a `MarkdownBodyView(context: MarkdownContext(kind: .post, textScale: <existing textSizeAdjustment>, density: <existing>))`. In `configure`, call `bodyView.setBlocks(viewModel.bodyBlocks)`. Set `bodyView.imageLoader = { [imageService] url in <fetch via ImageService → UIImage?> }` (read how `BodyTextView` used `imageService` to fetch an image for a URL — mirror that fetch, reduced to "first ready image or nil"; keep it `@MainActor`). Wire `bodyView.delegate` to a forwarder that calls the cell's existing closures: link → `linkTapped?`, image → a new `bodyImageTapped?((url, altText, sourceRect))` closure, video → `bodyVideoTapped?`, audio → `bodyAudioTapped?`. Wire the body view's content-size change to the existing `onContentSizeChange` (the `tableView.beginUpdates()/endUpdates()` re-measure) — the `MarkdownBodyView` already invalidates its own intrinsic size; expose a hook or use the delegate/closure so the cell triggers the table re-measure.

- [ ] **Step 3: ViewController routing** — in `PostDetailViewController`, where it currently wires the header cell, set the new body closures: link → existing `linkTapped(url)` BUT first run it through the Task-2 adapter: `linkTapped(MarkdownInternalLink.resolve(url) ?? url)`; body image → `presentMediaViewer(imageUrl: url, thumbnailUrl: nil, preloadedImage: nil, altText: altText)`; body video/audio → `presentVideoPlayer(url:)`. (Add a `Haptics.tap()` on media open if consistent with existing taps.)

- [ ] **Step 4: Build + SIMULATOR eyeball.** Build the Spud app (expect `** BUILD SUCCEEDED **`). Then boot a sim, run the app, open a post WITH a rich body (formatting, a link, a mention, an inline image if available), and confirm: the post body renders via the new block renderer (teal links/mentions, real blocks), tapping a link/mention navigates, tapping an inline image opens the media viewer, and the cell height is correct (no clipping; re-measures when an image loads). Screenshot to `/tmp/spud-phase6-post.png` and report what you see. (Use the `ddenis:ios-simulator-skill` mechanics if helpful.)

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat Spud
git add Spud
git commit -m "feat(markdown): render post body with MarkdownBodyView

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Comment bodies → MarkdownBodyView

**Files:** Modify `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift`, `PostDetailCommentViewModel.swift`, and `PostDetailViewController.swift` (comment cell wiring)

Same swap for comments, honoring the collapsed state + depth rail. READ the three files first.

- [ ] **Step 1: ViewModel** — `PostDetailCommentViewModel` carries body `[MarkdownBlock]` (via the Task-3 cache). Keep collapsed semantics.

- [ ] **Step 2: Cell** — replace `messageLabel: BodyTextView` with a `MarkdownBodyView(context: MarkdownContext(kind: .comment, …))`. In `configure`, `bodyView.setBlocks(viewModel.isCollapsed ? [] : viewModel.bodyBlocks)` (collapsed → no blocks). Keep the `depthRailsView` and layout exactly. Set `imageLoader`, `delegate` forwarder, and content-size → the existing `onBodyImageLoaded` / `performBatchUpdates(nil)` re-measure, exactly as Task 4 did for the header.

- [ ] **Step 3: ViewController wiring** — set the comment cell's body closures the same way as Task 4 (link via adapter → `linkTapped`, image → `presentMediaViewer`, video/audio → `presentVideoPlayer`).

- [ ] **Step 4: Build + SIMULATOR eyeball** — build, open a post with a deep comment thread containing formatting/links/mentions/a spoiler; confirm comment bodies render via the new renderer, the depth rail still indents correctly, collapse/expand still hides/shows the body, links/mentions navigate, a spoiler expands and the row re-measures. Screenshot `/tmp/spud-phase6-comments.png`; report.

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat Spud
git add Spud
git commit -m "feat(markdown): render comment bodies with MarkdownBodyView

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Cleanup + final verification

**Files:** small cleanups across the Task 4/5 files; possibly `PostDetailViewController.swift` (pre-warm tidy)

- [ ] **Step 1: Remove now-dead body wiring** at the two in-scope sites only (e.g. the old `BodyTextView`-specific properties/closures the new path replaced — `tapped`, the old `attributedText` assignment, the inline-image attachment plumbing IF it's only used by the replaced bodies). Be conservative: if a helper is shared with the out-of-scope sites (bios/descriptions/composer) or the post's main media, KEEP it. Do not remove `BodyTextView`, `MarkdownRenderer`, or `imageBody`.

- [ ] **Step 2: FINAL VERIFICATION.**
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud-markdown-integration && make project
# App + framework build:
xcodebuild -project Spud.xcodeproj -scheme Spud -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -8
# Unit tests (avoid the annex-fragile snapshot suites): run the unit-only targets explicitly.
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudMarkdownKitTests test 2>&1 | tail -6
xcodebuild -project Spud.xcodeproj -scheme Spud -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation -only-testing:SpudTests test 2>&1 | tail -8
```
Expected: app `** BUILD SUCCEEDED **`; `SpudMarkdownKitTests` + `SpudTests` `** TEST SUCCEEDED **`. Report results + any `SpudSnapshotTests` annex artifacts (do not block on those). Note: the `PostDetail*` app snapshot tests will be visually stale (body renderer changed) — re-recording them is deferred with the annex-storage decision; call this out.

- [ ] **Step 3: Commit** any cleanup.
```bash
make project && mint run swiftformat Spud
git add Spud
git commit -m "refactor(markdown): tidy replaced body-rendering wiring at post/comment sites

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria for Phase 6

- Post-detail header body and comment bodies render via `MarkdownBodyView` (the new block renderer): real blocks, teal links/mentions/communities, interactive code/table/spoiler/footnotes/media.
- Links/mentions/communities navigate (scheme adapter → existing routing); inline images open the media viewer; videos/audio open the player; haptics consistent.
- Cells re-measure correctly on async image load + spoiler expand; collapsed comments hide the body; depth rail intact.
- Off-main parse + block cache + pre-warm preserved. App builds; `SpudMarkdownKitTests` + `SpudTests` green; verified by simulator eyeball of a real post + comment thread.
- `BodyTextView` / `MarkdownRenderer` / `imageBody` remain for the out-of-scope sites (bios, descriptions, composer).

## Deferred / follow-ups

- Migrate bios / community descriptions / composer preview to the new renderer + then retire `BodyTextView`/`imageBody` (a later round).
- Re-record the `PostDetail*` `SpudSnapshotTests` against the new renderer once the git-annex snapshot-storage question is resolved (Phase-5 note).
- Footnote ref↔def smooth scroll, rounded chips, fence-aware preprocessors, spoiler-in-list, H6 inline formatting (carried-forward renderer limitations).
- Loaded-image VoiceOver element (the remaining Phase-4 a11y follow-up).
