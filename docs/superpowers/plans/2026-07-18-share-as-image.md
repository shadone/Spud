# Share as Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a Lemmy post — or a comment plus its ancestor chain — into a designed, shareable image card, configured in a direct-manipulation editor and handed to the system share sheet with the permalink and alt text.

**Architecture:** A fixed-metric, fixed-palette card view (`ShareCardView` / `ShareChainCardView`, app target) rendered off-screen to PNG by `ShareCardImageRenderer`; a `ShareAsImageViewController` editor sheet (direct manipulation: tap card elements to toggle them) presented from the existing context menus / overflow menu; content extracted from the rows those surfaces already hold (`PostListRow`, `PostDetailHeaderRow`, `PostDetailCommentRow`).

**Tech Stack:** UIKit, Swift 6 strict concurrency, Swift Testing (SpudTests), swift-snapshot-testing (SpudSnapshotTests), Core Image (deterministic blur), ImageIO (PNG metadata).

**Design source of truth:** the Claude Design deck (`Spud Share as Image.html` + `share-image.jsx` in the Spud design project) and `docs/design/SHARE-AS-IMAGE-DESIGN-PROMPT.md`. The deck's settled decisions, reproduced in this plan, are binding.

## Global Constraints

- **Copy:** the action is **"Share as Image"** everywhere (matching the app's existing menu items "Share" / "Cross-post", which carry no ellipsis; the deck's "Share as Image…" ellipsis is dropped for house consistency). Never "Create Image" / "Make Picture". Editor title: **"Share as Image"**.
- **The card never editorializes** (brief guardrail): card text is never editable; the **absolute timestamp and the permalink render in EVERY configuration** — no option may remove them (only the "via Spud" mark is toggleable). Absolute time only, never relative.
- **The card is accent-neutral and theme-independent:** its own two-surface palette (below); the only brand color is the fixed Lemmy teal (`AccentColor.lemmy`'s literal — NOT `ThemeManager.currentAccentColor`, NOT `Theme.*` tokens, which read the process-wide true-black flag).
- **The card ignores Dynamic Type** (fixed internal type scale); the editor chrome honors it.
- **NSFW media is spoilered by default, never auto-revealed;** the reveal is per-card, never persisted.
- **No UIVisualEffectView / system materials inside the card** — everything must render deterministically off-screen (Core Image gaussian blur for the NSFW spoiler, plain layers for redaction).
- Swift 6 / strict concurrency everywhere; no Combine, no Core Data. `DateFormatter`s built locally per call (never `static let` in non-`@MainActor` types).
- New files need `make project` (XcodeGen) before building. SwiftFormat (`mint run swiftformat <paths>`) BEFORE the final verify of each task. No emojis anywhere. Conventional commits.
- Tests: Swift Testing in `SpudTests` (`struct` suites, `@Test`, `#expect`); snapshot tests in `SpudSnapshotTests` (XCTest, `assertSnapshot`, device-independent `.image(size:)` on plain views).
- Verify commands: `make build`, `make test-only ONLY=SpudTests`, or targeted `xcodebuild … -only-testing:SpudTests/<Suite>` / `-only-testing:SpudSnapshotTests/<Class> -testPlan SpudSnapshots`. First snapshot run records + fails; rerun verifies. Snapshot refs are git-annex-tracked: `git add` only the explicit new refs.

## Card visual spec (from the design deck — binding)

Design width `CARD_W = 372` (pt). Padding 26. Corner radius 20. Hairline border `edge`.

Palette (`ShareCardPalette`), two fixed surfaces:

| token | light | dark |
|---|---|---|
| paper (canvas backdrop) | `#F7F5F1` | `#16171A` |
| panel (card bg) | `#FFFFFF` | `#202227` |
| ink | `#17181A` | `#F2F3F5` |
| sub | `rgba(23,24,26,0.56)` | `rgba(236,238,242,0.62)` |
| faint | `rgba(23,24,26,0.34)` | `rgba(236,238,242,0.38)` |
| hair | `rgba(0,0,0,0.10)` | `rgba(255,255,255,0.11)` |
| chip | `rgba(0,0,0,0.045)` | `rgba(255,255,255,0.06)` |
| edge | `rgba(0,0,0,0.06)` | `rgba(255,255,255,0.05)` |

Brand teal: `AccentColor.lemmy`'s fixed literal (`UIColor(red: 0, green: 0.59, blue: 0.53, alpha: 1)` — reference the enum, don't re-hardcode). Used ONLY for: score triangle glyph, "Read the full post on Lemmy →" line, chain destination rail + "SHARED" tag, the "via Spud" logo glyph.

Post card layout, top to bottom:
1. **Community lockup** (toggleable *together with* creator): community icon 34pt (reuse the app's community-icon rendering; fallback initial-on-tint circle), community display name (15pt bold), `c/name@instance` handle in monospaced 11.5pt `faint`; creator top-right: 22pt avatar + `u/name@instance` mono 12.5 `sub`, max width ~156pt, ellipsized. **Redaction** replaces every person (creator + chain authors) with a striped/blurred placeholder circle + `u/•••••••`; community is never redacted.
2. **Title**: 22pt, weight 800-equivalent (`.systemFont(ofSize: 22, weight: .heavy)`), line height ~1.18, ink.
3. **Media** (image posts only, toggleable): rounded 12, height `0.72 × contentWidth` (or `0.52 ×` when image aspect is wider than 4:3 — "wide" relaxes the card). Loading state: `chip` background + shimmer + "Loading media…" caption. NSFW: gaussian-blurred image (CI radius ~26) + 42%-black overlay + eye glyph + "Sensitive content" 12.5pt bold white.
4. **Body** (only when post has body text): plain text from `MarkdownPlainText.preview(from:)`, 15pt, line height ~1.58, ink at 90% opacity. Treatments: `full` (unclamped), `truncate` (max height 132pt + bottom fade to panel + teal 12.5pt bold "Read the full post on Lemmy →"), `titleOnly` (no body).
5. **Stats row** (toggleable): teal up-triangle + score (mono 13, `CountFormatter`), comment glyph + count, absolute timestamp right-aligned mono 12.5 `faint`. When stats hidden, the absolute timestamp still renders alone, right-aligned (guardrail).
6. **Footer** (always present): hairline top border; permalink (mono 11, `faint`, middle-truncated, ALWAYS shown) + right-aligned "via" + teal Spud glyph + "Spud" 12.5 heavy (mark toggleable).

Chain card (comment share): optional post header (26pt community icon + name + handle, then 16.5pt heavy title, hairline below); then ancestor lines walking DOWN toward the shared comment — each line: 3pt rounded rail (hair; TEAL for the destination), author (redactable, 19pt avatar), score mini-stat, body 13.5pt at 74% opacity (destination: 15.5pt, full opacity, weight medium, plus its own absolute timestamp and "SHARED" tag in 9.5pt heavy uppercase teal). Deep chains (> 4 ancestors) elide the middle: keep the top 2 and bottom 2, insert a "`N` more replies" divider row. Footer identical to the post card, permalink = the shared comment's.

Canvas: `native` (image hugs the card), `square` (1080×1080: card scaled/centered on a `paper` radial-gradient backdrop with a 22pt-spaced dot grid at 50% `hair`), `story` (1080×1920, same backdrop). Export scale: render the card at 372pt width into a `UIGraphicsImageRenderer` with `scale = 3` (native ≈ 1116px wide).

## Options model (settled product scope, from the brief)

`ShareCardOptions: Codable, Equatable, Sendable` —
- `appearance: Appearance` (`.light` / `.dark`; default `.light`)
- `showCommunityAndCreator: Bool` (default true)
- `showStats: Bool` (default true)
- `showMedia: Bool` (default true)
- `bodyTreatment: BodyTreatment` (`.full` / `.truncate` / `.titleOnly`; default `.truncate`)
- `redactIdentities: Bool` (default false)
- `chainDepth: Int` (0–8; default 2; # of ancestors above the shared comment; clamped to available)
- `includePostInChain: Bool` (default true)
- `canvas: Canvas` (`.native` / `.square` / `.story`; default `.native`)
- `showViaSpudMark: Bool` (default true)
- `nsfwRevealed: Bool` — **NOT Codable-persisted** (custom `init(from:)`/`encode(to:)` that skips it, always decodes false). Runtime-only.

Persisted as last-used via `PreferencesService`: `@UserDefaultsBacked var shareAsImageOptions: ShareCardOptions` (key `"shareAsImageOptions"`, default `.init()`), following the `urlSanitizerConfig` pattern. NOTE: `UserDefaultsBacked` lives in SpudUtilKit and the options type in the app target — that's fine (`URLSanitizerConfig` precedent shows Codable value types work with zero plumbing; the preference is registered in `Spud/Services/Preferences/PreferencesService.swift`). Since `ShareCardOptions` must be visible to `PreferencesService` (app target) it lives in the app target — OK.

## Content model

`ShareCardContent: Sendable` (app target, `Spud/Scenes/ShareAsImage/`):
- `post: PostSummary?` — `title`, `bodyPlain: String?` (via `MarkdownPlainText.preview`), `communityName`, `communityHandle` ("c/name@instance", instance host derived from `communityActorId` via `InstanceActorId`), `communityIconUrl: URL?`, `creatorHandle: String?` ("u/name@instance"), `score: Int64`, `commentCount: Int64`, `published: Date`, `permalink: URL`, `mediaUrl: URL?`, `mediaAspectIsWide: Bool` (from `imageWidth`/`imageHeight` when known, else false), `isNsfw: Bool`
- `chain: [ChainItem]` — `authorHandle`, `score: Int64`, `bodyPlain`, `published: Date?`, `isDestination: Bool`; destination also carries `permalink: URL`
- `kind: Kind` — `.post` / `.comment` (comment ⇒ footer permalink is the comment's)

Builders:
- `ShareCardContent(postRow: PostListRow, permalink: URL)`
- `ShareCardContent(headerRow: PostDetailHeaderRow, permalink: URL)`
- `ShareCardContent(comment: PostDetailCommentRow, ancestors: [PostDetailCommentRow], header: PostDetailHeaderRow?, permalink: URL)` — ancestors ordered root-most first; builder marks the shared comment `isDestination`.

Ancestor walk (entry-point side, post-detail only): backward scan over `PostDetailViewModel.orderedComments` from the pressed row's index, collecting rows with strictly decreasing `depth` until depth 1 is collected — same algorithm as `CommentCollapseState.collapsedAncestors(of:in:collapsedIds:)` (`SpudDataKit/Services/AppDatabase/CommentCollapseState.swift:137`). Implement as a small pure helper `ShareCardAncestry.ancestors(of:in:) -> [PostDetailCommentRow]` in the app target with unit tests (do NOT modify CommentCollapseState).

Permalinks come from the existing `LinkURL.forPost` / `LinkURL.forComment` (`Spud/Utils/Sharing/LinkURL.swift`) at entry-point time, honoring `preferencesService.shareLinkInstance`. If no URL can be formed, behave like the existing share action: warning haptic, no editor.

Alt text: `ShareCardAltText.make(content:options:) -> String`. Shape (from the deck): `Lemmy post in c/linux@lemmy.ml: "TITLE", 3.4K points, 612 comments, Jul 12, 2026. Shared via Spud.` For comments: `Comment by u/name@instance in c/…: "BODY-PREFIX…", 52 points, Jul 12, 2026. Shared via Spud.` Redaction-aware (omit person handles when `redactIdentities`). Uses `CountFormatter` and a locally-built `DateFormatter` (`dateStyle: .medium, timeStyle: .none`).

Card timestamps: `dateStyle: .medium, timeStyle: .short` (e.g. "Jul 12, 2026 at 4:03 PM") — accept the locale's joiner; do not string-replace to force the deck's "·".

---

### Task 1: Card foundation — palette, options, content, alt text, ancestry

**Files:**
- Create: `Spud/Scenes/ShareAsImage/ShareCardPalette.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareCardOptions.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareCardContent.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareCardAltText.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareCardAncestry.swift`
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (declare + wire `shareAsImageOptions` in `init`, following `urlSanitizerConfig`)
- Test: `SpudTests/ShareCardOptionsTests.swift`, `SpudTests/ShareCardContentTests.swift`, `SpudTests/ShareCardAltTextTests.swift`, `SpudTests/ShareCardAncestryTests.swift`

**Interfaces (produces — later tasks rely on these exact names):**
```swift
struct ShareCardPalette { let paper, panel, ink, sub, faint, hair, chip, edge: UIColor
    static let light: ShareCardPalette; static let dark: ShareCardPalette
    static let teal: UIColor /* = AccentColor.lemmy fixed literal via SpudUIKit */ }
struct ShareCardOptions: Codable, Equatable, Sendable { /* fields as in "Options model" above */
    enum Appearance: String, Codable, Sendable { case light, dark }
    enum BodyTreatment: String, Codable, Sendable { case full, truncate, titleOnly }
    enum Canvas: String, Codable, Sendable { case native, square, story } }
struct ShareCardContent: Sendable { /* as in "Content model" above */ }
enum ShareCardAltText { static func make(content: ShareCardContent, options: ShareCardOptions) -> String }
enum ShareCardAncestry { @MainActor static func ancestors(of elementId: ..., in ordered: [PostDetailCommentRow]) -> [PostDetailCommentRow] }
```
(Adopt the exact element-id/index parameter shape `PostDetailViewController`'s comment menu already has at hand — check `commentRowsByElementId` usage at `PostDetailViewController.swift:2279-2400`.)

**Steps:**
- [ ] Write failing Swift Testing suites: options JSON roundtrip preserves every field EXCEPT `nsfwRevealed` (encode with `nsfwRevealed = true` → decode reads `false`); defaults match the table above; content builder maps a fixture `PostListRow` (use the `.fixture` helpers from `SpudTests/PostContextMenuBuilderTests.swift` if reusable, else build rows inline) → handles/`permalink`/`isNsfw`/wide-aspect; alt-text strings for post/comment/redacted; ancestry walk on a synthetic ordered array incl. a deep chain and a mid-tree start.
- [ ] Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/ShareCardOptionsTests -only-testing:SpudTests/ShareCardContentTests -only-testing:SpudTests/ShareCardAltTextTests -only-testing:SpudTests/ShareCardAncestryTests -destination "$(scripts/resolve-test-destination.sh)" -skipPackagePluginValidation -skipMacroValidation test` — expect FAIL (types missing). Remember `make project` first so the new files are in the project.
- [ ] Implement the five files + the preference registration. `///` docs on every public/internal type incl. the two guardrails (permalink/timestamp always survive; `nsfwRevealed` never persisted — say WHY in the doc comment).
- [ ] `mint run swiftformat Spud/Scenes/ShareAsImage SpudTests` then re-run the tests — expect PASS. Also `make build` (the app must still compile — PreferencesService change).
- [ ] Commit: `feat: share-as-image card foundation (palette, options, content, alt text)`

### Task 2: ShareCardView — the post card

**Files:**
- Create: `Spud/Scenes/ShareAsImage/ShareCardView.swift` (+ split subviews if the file grows past ~350 lines: `ShareCardMediaView.swift`, `ShareCardFooterView.swift`)
- Test: `SpudSnapshotTests/ShareCardViewSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces: `final class ShareCardView: UIView { init(content: ShareCardContent, options: ShareCardOptions); func apply(options: ShareCardOptions); var imageLoader: (@MainActor (URL) async -> UIImage?)?; func setMediaImage(_ image: UIImage?) /* test seam: inject without network */; var onLayoutChange: (() -> Void)? }` — fixed width 372, height from Auto Layout (`systemLayoutSizeFitting`).

**Steps:**
- [ ] Write the snapshot test class first (template: `SpudSnapshotTests/LinkPreviewViewSnapshotTests.swift` — build view, `systemLayoutSizeFitting`, `assertSnapshot(matching:as:.image(size:))`). Matrix (use a fixed en_US_POSIX-formatted date by injecting a fixed `Date` in content; card colors are all fixed so no trait plumbing needed): light+dark full config; body `.full` / `.truncate` (with a genuinely long body) / `.titleOnly`; media via `setMediaImage(solid-color UIImage)` incl. wide; NSFW spoilered (blurred solid image is deterministic); redacted; stats hidden (timestamp must still render); `showViaSpudMark: false` (permalink must still render).
- [ ] Implement the view: manual Auto Layout, fixed fonts (no `preferredFont`), all colors from `ShareCardPalette`. Truncate fade = `CAGradientLayer` over the body's clipping container + the teal "Read the full post on Lemmy →" label. NSFW blur via `CIGaussianBlur` applied to the media image (helper `ShareCardView.blurred(_ image:)`), NOT UIVisualEffectView. Media shimmer: simple two-stop `CAGradientLayer` animation; MUST render as its base `chip` color in a static snapshot (deterministic first frame).
- [ ] Run the snapshot class twice (record, then verify). `git add` ONLY the new `__Snapshots__/ShareCardViewSnapshotTests/` refs.
- [ ] SwiftFormat, re-verify, commit: `feat: share-as-image post card view`

### Task 3: ShareChainCardView — comment + ancestors

**Files:**
- Create: `Spud/Scenes/ShareAsImage/ShareChainCardView.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareChainElision.swift` (pure: `static func visibleRows(chain: [ShareCardContent.ChainItem], depth: Int) -> [Row]` where `Row = .item(ChainItem) | .elision(count: Int)` — keep top 2 / bottom 2 when > 4 visible ancestors)
- Test: `SpudTests/ShareChainElisionTests.swift`, `SpudSnapshotTests/ShareChainCardViewSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 1 types, Task 2's footer/redaction subviews (reuse — do not duplicate the footer).
- Produces: `final class ShareChainCardView: UIView { init(content: ShareCardContent, options: ShareCardOptions); func apply(options: ShareCardOptions) }`.

**Steps:**
- [ ] Failing unit tests for elision (5 ancestors → top2 + "1 more replies"? NO — singular/plural: use "1 more reply"/"N more replies"; test both) and depth clamping. Failing snapshot matrix: chain depth 0 (destination only) / 3 / deep-elided; includePost on/off; dark; redacted (timestamp + permalink still visible).
- [ ] Implement; destination row emphasized per the visual spec (teal rail, SHARED tag, own timestamp).
- [ ] Record + verify snapshots; add only the explicit refs. SwiftFormat. Commit: `feat: share-as-image comment chain card`

### Task 4: Renderer + share payload

**Files:**
- Create: `Spud/Scenes/ShareAsImage/ShareCardImageRenderer.swift`
- Modify: `Spud/Utils/Sharing/ShareService.swift` — add `presentShareSheet(items: [Any], sourceView:sourceItem:)`; make the existing URL variant delegate to it; adopt it in `MediaViewerViewController.presentActivity` (DRY cleanup flagged by the design prompt).
- Test: `SpudTests/ShareCardImageRendererTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 views.
- Produces:
```swift
@MainActor enum ShareCardImageRenderer {
    static func render(cardView: UIView, options: ShareCardOptions) -> UIImage            // native / square / story composition, scale 3
    static func writePNG(_ image: UIImage, altText: String, suggestedName: String) throws -> URL  // temp file, PNG description metadata
    static func shareItems(image: UIImage, pngFileURL: URL, permalink: URL) -> [Any]      // [pngFileURL, permalink]
}
```

**Steps:**
- [ ] Failing tests: `render` on a fixed-size dummy card returns `.square` → 1080×1080 px (`size × scale`), `.story` → 1080×1920 px, `.native` → width 1116 px; `writePNG` output re-read via `CGImageSourceCopyPropertiesAtIndex` contains the alt text under `kCGImagePropertyPNGDictionary`/`Description` (and `kCGImagePropertyIPTCDictionary` caption); file extension `.png`; suggestedName sanitized.
- [ ] Implement. Square/story backdrop: `paper` radial-ish gradient (`CAGradientLayer` type `.radial`), dot grid drawn in `draw(_:)` or a replicated layer, card image centered with ≥ 30pt padding, scaled down only (never up). Renderer must run the card's layout pass (`setNeedsLayout`/`layoutIfNeeded` at 372-width bounds) before drawing (`drawHierarchy(in:afterScreenUpdates:)` fallback `layer.render(in:)` — use `layer.render` since the view is off-screen).
- [ ] SwiftFormat, tests green (`-only-testing:SpudTests/ShareCardImageRendererTests`), `make build`. Commit: `feat: share-as-image renderer, PNG alt-text metadata, shared multi-item share sheet`

### Task 5: The editor — ShareAsImageViewController

**Files:**
- Create: `Spud/Scenes/ShareAsImage/ShareAsImageViewController.swift`
- Create: `Spud/Scenes/ShareAsImage/ShareAsImageTrayView.swift` (appearance + canvas pills, chain-depth stepper when chain, alt-text button)
- Create: `Spud/Scenes/ShareAsImage/ShareAsImageAltTextViewController.swift` (small sheet: editable `UITextView` prefilled with auto text, "Auto" badge resets)
- Test: `SpudTests/ShareAsImageViewModelTests.swift` (option mutations), `SpudSnapshotTests/ShareAsImageSnapshotTests.swift` (editor screen, `.image(on: .deterministicPhone)`)

**Interfaces:**
- Consumes: everything above; `PreferencesService.shareAsImageOptions` (open with last-used, save on Done/Share); `ImageServiceType.fetch` wrapped in the standard `imageLoader` closure idiom (`PostDetailHeaderCell.swift:674`).
- Produces: `static func makeSheet(content: ShareCardContent, imageService: ImageServiceType, preferencesService: PreferencesService) -> UIViewController` — wraps in `UINavigationController`, `modalPresentationStyle = .pageSheet` BEFORE touching `sheetPresentationController` (documented gotcha), detents `[.large()]`.

**Behavior (from the settled Editor C design):**
- Dark editor canvas (editor chrome MAY use app `Theme` tokens — it is an app screen) with dot grid; centered, scaled live preview (scale to fit width with margins, `UIScrollView` when taller than the viewport).
- Direct manipulation tap targets ON the preview (transparent overlay buttons tracking the card's subview frames): creator/avatar → toggle `redactIdentities`; community lockup → toggle `showCommunityAndCreator`; stats row → toggle `showStats`; body → cycle `bodyTreatment` full → truncate → titleOnly → full; media → toggle `showMedia`; blurred NSFW media shows a "Reveal for this card" pill (toggles `nsfwRevealed`); footer mark → toggle `showViaSpudMark`. Every toggle re-applies options with a short cross-dissolve + `Haptics` tap. First presentation shows one-time passive hint labels ("Tap any element to toggle it") in the tray caption, not floating badges.
- Tray (bottom, above output bar): Light/Dark pills, Native/Square/Story pills, chain-depth stepper ("Depth N" with −/+, only for comment cards), "Alt Text" button.
- Output bar: primary filled Share button (accent-tinted — editor chrome, not card), Save to Photos icon button, Copy icon button. Share: ensure media loaded (or `showMedia` effectively false), render, `writePNG`, present share sheet with `[pngFileURL, permalink]` anchored to the Share button. Save: `UIImageWriteToSavedPhotosAlbum` (Info.plist key already present) + success haptic + brief confirmation. Copy: `UIPasteboard.general.items = [[image], [permalink]]`.
- Persist `preferencesService.shareAsImageOptions = currentOptions` on Share/Save/Copy/Done (recall `nsfwRevealed` is stripped by the codec).
- Accessibility: each tap region is a `UIAccessibilityElement` (label = element name, value = current state, hint = what tap does, `.button` trait); the preview itself has `accessibilityLabel` = current alt text. Editor labels use `preferredFont` + `adjustsFontForContentSizeCategory`.
- Nav bar: title "Share as Image", right `Done` (dismiss, persisting options).

**Steps:**
- [ ] Failing view-model unit tests: cycling body treatment; NSFW reveal not persisted through save/load (uses the codec, but assert the VC's persist path too); depth clamp; alt-text override kept until content changes.
- [ ] Implement VC + tray + alt-text sheet.
- [ ] Editor snapshot (`deterministicPhone`, post card, default options, media injected) — record + verify.
- [ ] SwiftFormat; targeted tests + `make build`. Commit: `feat: share-as-image direct-manipulation editor`

### Task 6: Entry points

**Files:**
- Modify: `Spud/Utils/ContextMenus/PostContextMenuBuilder.swift` — `shareGroup` becomes `[replyAction, shareAction, shareAsImageAction, crossPostAction]`; new host requirement `func postShareAsImage(serverPostId: Int64)`; action title `"Share as Image"`, icon `UIImage(systemName: "photo")`.
- Modify: `Spud/Scenes/PostList/PostListViewController.swift` — conform (`postShareAsImage` → build `ShareCardContent(postRow:)` + `LinkURL.forPost` → present `ShareAsImageViewController.makeSheet`); same warning-haptic bail as `sharePost` when no URL.
- Modify: `Spud/Scenes/Search/SearchViewController.swift` — same conformance.
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController+OverflowMenu.swift` — insert after "Share" in `primaryGroup`.
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` — post-header inline menu (`postContextMenuConfiguration(at:)`, ~line 2404): after Share; comment inline menu (~2279-2400): "Share as Image" after Share → `ShareCardAncestry.ancestors` + `ShareCardContent(comment:ancestors:header:permalink:)` (permalink via `LinkURL.forComment`) → present editor. Initial `chainDepth` from saved options, clamped.
- Modify: `SpudTests/PostContextMenuBuilderTests.swift` — `FakePostContextMenuHost` records `postShareAsImage`; assert titles contain "Share as Image" adjacent to "Share"; tap-through invokes the host.
- Test: extend `SpudUITests/SpudUITests.swift` — in the existing long-press context-menu test path, assert `app.buttons["Share as Image"].waitForExistence(timeout: 5)` (do NOT tap — keep the test cheap and stub-free).

**Out of scope (document in Task 7):** Search's comment-row menu (`CommentContextMenuBuilder`) — Search has no comment tree in memory, so no ancestor chain; deliberately omitted rather than shipping a degraded chain-less variant there.

**Steps:**
- [ ] Failing builder tests first; then implement builder + conformances + menus. UIKit invokes `UIAction` handlers after menu dismissal — present the sheet directly (house pattern, no animator dance).
- [ ] Run `SpudTests/PostContextMenuBuilderTests` + `make build`; run the touched UITest class if the sim is free (`make test-only ONLY=SpudUITests` is long — a targeted `-only-testing:SpudUITests/SpudUITests/test_<name>` is fine).
- [ ] SwiftFormat. Commit: `feat: share-as-image entry points (feed and search menus, post detail, comment chain)`

### Task 7: Feature docs

**Files:**
- Create: `docs/features/share-as-image.md` (use `docs/features/README.md`'s `_TEMPLATE`; Surfaces `iphone`,`ipad`; Status shipped; behavior + the guardrails + Scenarios as Given/When/Then: share a post as image; share a comment with ancestors; redact identities; NSFW stays spoilered; permalink survives every configuration; last-used settings restored; Search comment rows excluded)
- Modify: `docs/features/sharing.md` — remove the "No share-as-image" not-supported bullet, link the new doc under Related.
- Modify: `docs/features/README.md` — capability table row + "Feature coverage by area" map (both sections).
- Modify: `docs/design/SHARE-AS-IMAGE-DESIGN-PROMPT.md` — flip its note that sharing.md "currently reads no-share-as-image" to past tense (one line).

**Steps:**
- [ ] Write docs; cross-check every behavioral claim against the implemented code (no aspirational claims).
- [ ] Commit: `docs: share-as-image feature docs`

### Final gate (main session, after all tasks)

- [ ] Broad final review subagent over the whole branch diff.
- [ ] `mint run swiftformat .` (lint-clean), then full `make test` and `make snapshot` on the reference sim; fix or faithfully report any red.
- [ ] Re-check `main..feat/share-as-image` overlap RIGHT before merging (shared checkout: main moves); merge into local `main` per CLAUDE.md's worktree-merge rules (`git annex restage` first if merging in the shared checkout). Do NOT push.

## Self-review notes

- Spec coverage: card (all variants/edges incl. loading shimmer, NSFW, redaction, canvas, wide media) → Tasks 2/3/4; editor C behaviors incl. last-used + alt text + a11y → Task 5; entry points + naming rule → Task 6; guardrails encoded as tests → Tasks 1/2/3; docs → Task 7. iPad: pageSheet presentation (house style) + editor snapshot; Dynamic Type: editor-only scaling stated in Task 5.
- Known deliberate deviations from the deck, restate in docs: no ellipsis in the menu title (house consistency); chain depth via stepper not drag (accessible, honest); permalink hard-always-on (brief guardrail beats the deck's `footerPermalink` toggle).
