# Markdown Renderer — Phase 2 (Prose Rendering) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the prose blocks (paragraph, heading, list, quote, thematic break) and the full inline layer of a parsed `[MarkdownBlock]` tree into real, self-sizing UIKit views, themed via SpudUIKit tokens, shown live in `MarkdownLab` with a context/theme/text-scale/density control bar.

**Architecture:** A `MarkdownContext` value type carries the per-context sizing (post vs comment base metrics, scaled by Dynamic Type + text-scale + density) and resolves theme colors. An `InlineAttributedStringBuilder` turns `[MarkdownInline]` + context into an `NSAttributedString` (links/mentions/communities/emoji/sup-sub/code/etc.). A `ProseBlockView` (non-scrolling TextKit 2 `UITextView`) renders one attributed string. `MarkdownBodyView` is the self-sizing top-level container that maps each block to a view (prose blocks render fully; code/table/spoiler/image/audio/video/footnotes render a labeled placeholder until Phase 3–4). Deterministic units (context metrics, the inline builder) are TDD; the views are verified by snapshot tests + a Lab eyeball.

**Tech Stack:** Swift 6, UIKit + TextKit 2 (`UITextView`), `UIFontMetrics` for Dynamic Type, SpudUIKit tokens (`Theme`, `ThemeManager.currentAccentColor`), swift-snapshot-testing, XcodeGen.

---

## Scope

Phase 2 is **prose + inline rendering + the Lab render surface** only. Out of scope (later phases): code/table/spoiler/footnotes block VIEWS (Phase 3), media VIEWS (Phase 4), the snapshot suite breadth + edge cases (Phase 5), real-app integration and the deferred parser limitations (Phase 6). Non-prose blocks render as a labeled placeholder box this phase so the Lab shows the whole kitchen sink without crashing.

Builds on Phase 1 (`docs/superpowers/specs/2026-06-15-markdown-renderer-design.md`, `docs/superpowers/plans/2026-06-15-markdown-renderer-phase1-foundation.md`). The parser, model, and `MarkdownLab` app already exist.

## Reference metrics (the design contract — from `md-render.jsx` `scale()` / `tokens()`)

Per context (`post` generous, `comment` dense), base point sizes BEFORE Dynamic Type scaling:

| metric | post | comment |
|---|---|---|
| body | 16.5 | 14.5 |
| h1 | 29 | 21 |
| h2 | 24 | 19 |
| h3 | 20.5 | 17.5 |
| h4 | 18 | 16 |
| h5 | 16 | 14.5 |
| h6 | 13.5 | 12.5 |
| code | 14 | 12.5 |
| small | 13 | 12 |
| line height (mult) | 1.55 | 1.48 |
| inter-block gap | 15 | 9 |
| list indent | 22 | 17 |

Heading weights: H1/H2 = `.heavy` (800), H3–H6 = `.bold` (700). H6 is `.uppercase` text in `secondaryLabel`. Tracking: H1/H2 ≈ −0.5, H3+ ≈ −0.2 (apply via `.kern` proportional to size; minor — snapshot-tune).

Color mapping (reference token → native):

| reference | native |
|---|---|
| label | `UIColor.label` |
| body | `UIColor.label` |
| secondary (sec) | `UIColor.secondaryLabel` |
| tertiary (ter) | `UIColor.tertiaryLabel` |
| link / accent | `ThemeManager.currentAccentColor` |
| inline code fg | dynamic `#9a4a25` (light) / `#e8b9a0` (dark) |
| inline code bg | `UIColor.secondarySystemFill` |
| highlight (mark) | `UIColor.systemYellow` @ 0.30 alpha |
| quote bar | `UIColor.quaternaryLabel` |
| chip bg | accent @ 0.15 alpha |

## File Structure

```
SpudMarkdownKit/
  Rendering/
    MarkdownContext.swift            ← sizing (fonts, spacing) + color tokens, per context
    MarkdownColors.swift             ← the custom dynamic UIColors (inline-code fg, highlight, chip bg)
    InlineAttributedStringBuilder.swift ← [MarkdownInline] + context -> NSAttributedString
    ProseBlockView.swift             ← TextKit 2 UITextView for one attributed string (+ link tap)
    QuoteBlockView.swift             ← tinted bar + inset container wrapping child block views
    ThematicBreakView.swift          ← hairline separator
    PlaceholderBlockView.swift       ← labeled box for not-yet-rendered block kinds (code/table/...)
    MarkdownBodyView.swift           ← top-level self-sizing container; block -> view dispatch
    MarkdownBodyDelegate.swift       ← link/mention/community tap callback protocol
SpudMarkdownKitTests/
    MarkdownContextTests.swift
    InlineAttributedStringBuilderTests.swift
SpudSnapshotTests/ (or a new SpudMarkdownKit snapshot target — see Task 0)
    MarkdownProseSnapshotTests.swift ← kitchen-sink prose in post/comment x light/dark
MarkdownLab/
    LabControlBar.swift              ← context/theme/text-scale/density toggles
    MarkdownLabApp.swift             ← MODIFIED: render MarkdownBodyView instead of the text dump
```

## Conventions (every task)

Copyright header on every new file:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
```

**MUST regenerate before every build/test:** `make project` (XcodeGen only picks up new files on regeneration). Canonical unit-test command:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/<CLASS> test 2>&1 | tail -30
```

Format before commit: `mint run swiftformat <dirs>`. `git status -uall`; stage explicit paths. Swift 6. The view types are `@MainActor` (UIKit); the value types (`MarkdownContext`) are `Sendable` where practical (note: `UIFont`/`UIColor` are not `Sendable`, so a context holding resolved fonts is `@MainActor`-built — keep `MarkdownContext` construction `@MainActor`).

---

## Task 0: Snapshot test target wiring

**Files:** Modify `project.yml`

Phase 2 needs snapshot tests for the views. The existing `SpudSnapshotTests` target depends on the `Spud` app (heavy) and is Swift 5. Add a focused snapshot target for the framework instead.

- [ ] **Step 1:** In `project.yml`, add a target after `SpudMarkdownKitTests`:

```yaml
  SpudMarkdownKitSnapshotTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: SpudMarkdownKitSnapshotTests
        excludes:
          - "__Snapshots__/**"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: info.ddenis.SpudMarkdownKitSnapshotTests
        SWIFT_VERSION: "5.0"
    dependencies:
      - target: SpudMarkdownKit
      - package: SnapshotTesting
```

- [ ] **Step 2:** Add it to the `SpudMarkdownKit` scheme's `test.targets` list (so `xcodebuild -scheme SpudMarkdownKit test` runs both):

```yaml
  SpudMarkdownKit:
    build:
      targets:
        SpudMarkdownKit: all
        SpudMarkdownKitTests: [test]
        SpudMarkdownKitSnapshotTests: [test]
    test:
      targets:
        - SpudMarkdownKitTests
        - SpudMarkdownKitSnapshotTests
```

- [ ] **Step 3:** Create `SpudMarkdownKitSnapshotTests/Placeholder.swift` so the target has a source:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest

final class SnapshotPlaceholderTests: XCTestCase {
    func test_placeholder() { XCTAssertTrue(true) }
}
```

- [ ] **Step 4:** `make project`, then build the scheme to confirm the new target links:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build-for-testing 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5:** Commit.
```bash
make project && mint run swiftformat SpudMarkdownKitSnapshotTests
git add project.yml SpudMarkdownKitSnapshotTests
git commit -m "build(markdown): add SpudMarkdownKit snapshot test target

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 1: MarkdownColors — custom dynamic colors

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownColors.swift`; Create `SpudMarkdownKitTests/MarkdownContextTests.swift` (shared test file, starts here)

The three non-system colors the design needs, as dynamic `UIColor`s resolving light/dark at draw time.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/MarkdownContextTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

final class MarkdownColorsTests: XCTestCase {
    func test_inlineCodeForegroundResolvesLightAndDark() {
        let light = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light))
        let dark = MarkdownColors.inlineCodeForeground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotEqual(light, dark)
    }

    func test_highlightIsTranslucentYellow() {
        var alpha: CGFloat = 0
        MarkdownColors.highlight.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(nil, green: nil, blue: nil, alpha: &alpha)
        XCTAssertLessThan(alpha, 1.0)
        XCTAssertGreaterThan(alpha, 0.0)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:SpudMarkdownKitTests/MarkdownColorsTests`). Expected: `cannot find 'MarkdownColors'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Rendering/MarkdownColors.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The non-system colors the markdown design uses, as dynamic colors that
/// resolve light/dark at draw time.
enum MarkdownColors {
    /// Inline-code text: a warm brown (light) / soft peach (dark).
    static let inlineCodeForeground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xE8 / 255, green: 0xB9 / 255, blue: 0xA0 / 255, alpha: 1)
            : UIColor(red: 0x9A / 255, green: 0x4A / 255, blue: 0x25 / 255, alpha: 1)
    }

    /// ==highlight== background — translucent yellow.
    static let highlight = UIColor { traits in
        UIColor.systemYellow.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.26 : 0.34)
    }

    /// Tinted chip background for @mentions / !communities — the accent at low alpha.
    static var chipBackground: UIColor {
        UIColor { _ in ThemeManager.currentAccentColor.withAlphaComponent(0.15) }
    }
}
```
(Imports SpudUIKit transitively via the framework; `ThemeManager` is from SpudUIKit — add `import SpudUIKit` if the build needs it.)

- [ ] **Step 4: Run to verify it passes** (`-only-testing:SpudMarkdownKitTests/MarkdownColorsTests`). Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): custom dynamic colors for inline code/highlight/chips

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: MarkdownContext — per-context sizing & fonts

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownContext.swift`; Modify `SpudMarkdownKitTests/MarkdownContextTests.swift`

A `@MainActor` value type carrying the resolved metrics for one render context. Base sizes scaled by Dynamic Type (`UIFontMetrics`) + a text-scale delta + a density delta.

- [ ] **Step 1: Write the failing test.** Append to `SpudMarkdownKitTests/MarkdownContextTests.swift`:
```swift
@MainActor
final class MarkdownContextTests: XCTestCase {
    func test_postBodyLargerThanComment() {
        let post = MarkdownContext(kind: .post)
        let comment = MarkdownContext(kind: .comment)
        XCTAssertGreaterThan(post.bodyFont.pointSize, comment.bodyFont.pointSize)
    }

    func test_headingWeights() {
        let ctx = MarkdownContext(kind: .post)
        XCTAssertEqual(ctx.headingFont(level: 1).fontDescriptor.symbolicTraits.contains(.traitBold), true)
        // H1 is heavier than H3
        XCTAssertGreaterThan(ctx.headingFont(level: 1).pointSize, ctx.headingFont(level: 3).pointSize)
    }

    func test_textScaleIncreasesBody() {
        let base = MarkdownContext(kind: .post, textScale: 0)
        let bigger = MarkdownContext(kind: .post, textScale: 4)
        XCTAssertGreaterThan(bigger.bodyFont.pointSize, base.bodyFont.pointSize)
    }

    func test_compactDensityShrinksBody() {
        let comfortable = MarkdownContext(kind: .post, density: .comfortable)
        let compact = MarkdownContext(kind: .post, density: .compact)
        XCTAssertLessThan(compact.bodyFont.pointSize, comfortable.bodyFont.pointSize)
    }

    func test_interBlockGap() {
        XCTAssertGreaterThan(MarkdownContext(kind: .post).interBlockGap,
                             MarkdownContext(kind: .comment).interBlockGap)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:SpudMarkdownKitTests/MarkdownContextTests`). Expected: `cannot find 'MarkdownContext'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Rendering/MarkdownContext.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// The two body contexts: a full-width post body or a denser comment body.
public enum MarkdownContextKind: Sendable, Hashable { case post, comment }

/// Resolved sizing + color tokens for rendering a markdown body in one context.
/// Built on the main actor because it bakes `UIFont`s (Dynamic-Type scaled).
@MainActor
public struct MarkdownContext {
    public let kind: MarkdownContextKind
    /// Relative text-scale (the Display preference, roughly -3...+6 pt).
    public let textScale: CGFloat
    public let density: PostDensity

    public init(kind: MarkdownContextKind, textScale: CGFloat = 0, density: PostDensity = .comfortable) {
        self.kind = kind
        self.textScale = textScale
        self.density = density
    }

    private var post: Bool { kind == .post }

    /// Base body size before Dynamic Type, plus text-scale and density deltas.
    private var bodyBase: CGFloat { (post ? 16.5 : 14.5) + textScale + density.relativeFontSizeAdjustment }

    private func scaled(_ base: CGFloat, weight: UIFont.Weight = .regular,
                        textStyle: UIFont.TextStyle = .body) -> UIFont {
        let font = UIFont.systemFont(ofSize: base + textScale + density.relativeFontSizeAdjustment, weight: weight)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }

    public var bodyFont: UIFont { scaled(post ? 16.5 : 14.5) }
    public var smallFont: UIFont { scaled(post ? 13 : 12) }
    public var inlineCodeFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: (post ? 14 : 12.5) + textScale + density.relativeFontSizeAdjustment, weight: .regular))
    }

    public func headingFont(level: Int) -> UIFont {
        let base: CGFloat = post
            ? [29, 24, 20.5, 18, 16, 13.5][max(0, min(5, level - 1))]
            : [21, 19, 17.5, 16, 14.5, 12.5][max(0, min(5, level - 1))]
        let weight: UIFont.Weight = level <= 2 ? .heavy : .bold
        let style: UIFont.TextStyle = level <= 2 ? .title1 : (level <= 4 ? .title3 : .headline)
        return scaled(base, weight: weight, textStyle: style)
    }

    public var lineHeightMultiple: CGFloat { post ? 1.55 : 1.48 }
    public var interBlockGap: CGFloat { post ? 15 : 9 }
    public var listIndent: CGFloat { post ? 22 : 17 }

    // Colors
    public var labelColor: UIColor { .label }
    public var secondaryColor: UIColor { .secondaryLabel }
    public var tertiaryColor: UIColor { .tertiaryLabel }
    public var accentColor: UIColor { ThemeManager.currentAccentColor }
    public var inlineCodeForeground: UIColor { MarkdownColors.inlineCodeForeground }
    public var inlineCodeBackground: UIColor { .secondarySystemFill }
    public var highlightColor: UIColor { MarkdownColors.highlight }
    public var quoteBarColor: UIColor { .quaternaryLabel }
    public var chipBackground: UIColor { MarkdownColors.chipBackground }
}
```

- [ ] **Step 4: Run to verify it passes** (`-only-testing:SpudMarkdownKitTests/MarkdownContextTests`). Expected: `** TEST SUCCEEDED **`. (If `PostDensity.relativeFontSizeAdjustment` differs, it's a public CGFloat on `SpudUIKit.PostDensity` — `0` comfortable, `-1` compact; confirm the symbol.)

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): MarkdownContext sizing + theme tokens

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: InlineAttributedStringBuilder

**Files:** Create `SpudMarkdownKit/Rendering/InlineAttributedStringBuilder.swift`; Create `SpudMarkdownKitTests/InlineAttributedStringBuilderTests.swift`

Turns `[MarkdownInline]` + a `MarkdownContext` into an `NSAttributedString`. Handles every inline kind. Links/mentions/communities carry a `.link` attribute whose value is a `URL` (web for links; an internal `spud-markdown://mention?...` / `community?...` URL the host decodes — defined here so the framework stays decoupled). Phase 2 renders mention/community as accent text with a chip background + a leading SF Symbol attachment; the polished rounded pill is a Phase-3 refinement.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/InlineAttributedStringBuilderTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit
import XCTest
@testable import SpudMarkdownKit

@MainActor
final class InlineAttributedStringBuilderTests: XCTestCase {
    private func build(_ inlines: [MarkdownInline]) -> NSAttributedString {
        InlineAttributedStringBuilder.build(inlines, context: MarkdownContext(kind: .post))
    }

    func test_plainText() {
        XCTAssertEqual(build([.text("hello")]).string, "hello")
    }

    func test_strongIsBold() {
        let s = build([.strong([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
    }

    func test_emphasisIsItalic() {
        let s = build([.emphasis([.text("x")])])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitItalic) ?? false)
    }

    func test_linkCarriesURL() {
        let url = URL(string: "https://lemmy.world/post/1")!
        let s = build([.link(text: [.text("here")], url: url)])
        XCTAssertEqual(s.attribute(.link, at: 0, effectiveRange: nil) as? URL, url)
    }

    func test_highlightHasBackground() {
        let s = build([.highlight([.text("x")])])
        XCTAssertNotNil(s.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    func test_inlineCodeUsesMonospace() {
        let s = build([.code("ls")])
        let font = s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) ?? false)
    }

    func test_mentionCarriesInternalLinkAndAccentColor() {
        let s = build([.mention(name: "alice", instance: "lemmy.world")])
        // Contains the handle text and a .link with the spud-markdown internal scheme.
        XCTAssertTrue(s.string.contains("alice"))
        let url = s.attribute(.link, at: s.length - 1, effectiveRange: nil) as? URL
        XCTAssertEqual(url?.scheme, "spud-markdown")
    }

    func test_superscriptRaised() {
        let s = build([.text("x"), .superscript([.text("2")])])
        // The superscript run carries a baseline offset.
        let offset = s.attribute(.baselineOffset, at: s.length - 1, effectiveRange: nil) as? CGFloat
        XCTAssertNotNil(offset)
        XCTAssertGreaterThan(offset ?? 0, 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:SpudMarkdownKitTests/InlineAttributedStringBuilderTests`). Expected: `cannot find 'InlineAttributedStringBuilder'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Rendering/InlineAttributedStringBuilder.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Builds an `NSAttributedString` from inline markdown for a given context.
/// Mentions/communities encode their destination as an internal
/// `spud-markdown://` URL so the host can resolve navigation without this
/// framework knowing the app's URL scheme.
@MainActor
enum InlineAttributedStringBuilder {
    static func build(_ inlines: [MarkdownInline], context: MarkdownContext) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for inline in inlines {
            out.append(render(inline, context: context, baseFont: context.bodyFont))
        }
        return out
    }

    /// Internal destination URLs for mentions/communities (host decodes).
    static func mentionURL(name: String, instance: String) -> URL {
        URL(string: "spud-markdown://mention?name=\(name)&instance=\(instance)")!
    }

    static func communityURL(name: String, instance: String) -> URL {
        URL(string: "spud-markdown://community?name=\(name)&instance=\(instance)")!
    }

    private static func render(_ inline: MarkdownInline, context: MarkdownContext,
                               baseFont: UIFont) -> NSAttributedString {
        switch inline {
        case let .text(s):
            return NSAttributedString(string: s, attributes: [.font: baseFont, .foregroundColor: context.labelColor])

        case let .strong(children):
            return mapChildren(children, context: context, baseFont: baseFont.withTraits(.traitBold))
        case let .emphasis(children):
            return mapChildren(children, context: context, baseFont: baseFont.withTraits(.traitItalic))
        case let .strikethrough(children):
            let inner = mapChildren(children, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            m.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: context.secondaryColor],
                            range: NSRange(location: 0, length: m.length))
            return m
        case let .highlight(children):
            let inner = mapChildren(children, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            m.addAttribute(.backgroundColor, value: context.highlightColor,
                           range: NSRange(location: 0, length: m.length))
            return m
        case let .code(s):
            return NSAttributedString(string: s, attributes: [
                .font: context.inlineCodeFont,
                .foregroundColor: context.inlineCodeForeground,
                .backgroundColor: context.inlineCodeBackground,
            ])
        case let .superscript(children):
            return script(children, context: context, baseFont: baseFont, offset: baseFont.pointSize * 0.35)
        case let .subscript(children):
            return script(children, context: context, baseFont: baseFont, offset: -baseFont.pointSize * 0.2)

        case let .link(text, url):
            let inner = mapChildren(text, context: context, baseFont: baseFont)
            let m = NSMutableAttributedString(attributedString: inner)
            m.addAttributes([.link: url, .foregroundColor: context.accentColor,
                             .underlineStyle: NSUnderlineStyle.single.rawValue],
                            range: NSRange(location: 0, length: m.length))
            return m
        case let .mention(name, instance):
            return chip(symbol: "at", text: "\(name)@\(instance)",
                        url: mentionURL(name: name, instance: instance), context: context, baseFont: baseFont)
        case let .community(name, instance):
            return chip(symbol: "person.2", text: "\(name)@\(instance)",
                        url: communityURL(name: name, instance: instance), context: context, baseFont: baseFont)

        case let .emoji(s):
            return NSAttributedString(string: s, attributes: [.font: baseFont])
        case let .customEmoji(shortcode):
            // Phase 2: render as literal :shortcode: (server-emoji image is Phase 3+).
            return NSAttributedString(string: ":\(shortcode):",
                                      attributes: [.font: baseFont, .foregroundColor: context.secondaryColor])
        case let .footnoteReference(label):
            let small = baseFont.withSize(baseFont.pointSize * 0.78)
            return NSAttributedString(string: "[\(label)]", attributes: [
                .font: small,
                .foregroundColor: context.accentColor,
                .baselineOffset: baseFont.pointSize * 0.3,
            ])
        }
    }

    private static func mapChildren(_ children: [MarkdownInline], context: MarkdownContext,
                                    baseFont: UIFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for child in children { out.append(render(child, context: context, baseFont: baseFont)) }
        return out
    }

    private static func script(_ children: [MarkdownInline], context: MarkdownContext,
                               baseFont: UIFont, offset: CGFloat) -> NSAttributedString {
        let small = baseFont.withSize(baseFont.pointSize * 0.72)
        let inner = mapChildren(children, context: context, baseFont: small)
        let m = NSMutableAttributedString(attributedString: inner)
        m.addAttribute(.baselineOffset, value: offset, range: NSRange(location: 0, length: m.length))
        return m
    }

    private static func chip(symbol: String, text: String, url: URL,
                             context: MarkdownContext, baseFont: UIFont) -> NSAttributedString {
        let m = NSMutableAttributedString()
        if let image = UIImage(systemName: symbol)?.withTintColor(context.accentColor, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = image
            let size = baseFont.pointSize * 0.85
            attachment.bounds = CGRect(x: 0, y: baseFont.descender * 0.3, width: size, height: size)
            m.append(NSAttributedString(attachment: attachment))
            m.append(NSAttributedString(string: "\u{2009}"))  // thin space
        }
        m.append(NSAttributedString(string: text, attributes: [.font: baseFont.withTraits(.traitBold)]))
        m.addAttributes([.link: url, .foregroundColor: context.accentColor,
                         .backgroundColor: context.chipBackground],
                        range: NSRange(location: 0, length: m.length))
        return m
    }
}

extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var combined = fontDescriptor.symbolicTraits
        combined.insert(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(combined) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
```

- [ ] **Step 4: Run to verify it passes** (`-only-testing:SpudMarkdownKitTests/InlineAttributedStringBuilderTests`). Expected: `** TEST SUCCEEDED **`. If any attribute-key detail doesn't match (e.g. `.traitMonoSpace` availability on the resolved monospaced font), adjust the assertion's trait check or the builder until all 8 pass — the tests pin the required attributes.

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): inline attributed-string builder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: MarkdownBodyDelegate + ProseBlockView

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownBodyDelegate.swift`, `SpudMarkdownKit/Rendering/ProseBlockView.swift`

A non-scrolling, self-sizing TextKit 2 `UITextView` that renders one attributed string and reports link taps. (Mirrors the `BodyTextView` approach from Phase 0's `BodyTextView.swift` for link handling, but is greenfield and prose-block-scoped.)

- [ ] **Step 1: Create the delegate** at `SpudMarkdownKit/Rendering/MarkdownBodyDelegate.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Host callback for taps inside a rendered markdown body. The host resolves
/// web links (in-app vs Safari per preference) and `spud-markdown://`
/// mention/community URLs (via the app's own routing).
@MainActor
public protocol MarkdownBodyDelegate: AnyObject {
    func markdownBody(didTapLink url: URL)
}
```

- [ ] **Step 2: Create the view** at `SpudMarkdownKit/Rendering/ProseBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A non-editable, non-scrolling, self-sizing TextKit 2 text view for one
/// attributed string (a paragraph/heading run, or a list/quote leaf).
final class ProseBlockView: UITextView {
    var onTapLink: ((URL) -> Void)?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        adjustsFontForContentSizeCategory = true
        delegate = self
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) not implemented") }
}

extension ProseBlockView: UITextViewDelegate {
    func textView(_: UITextView, primaryActionFor textItem: UITextItem,
                  defaultAction: UIAction) -> UIAction? {
        if case let .link(url) = textItem.content {
            return UIAction { [weak self] _ in self?.onTapLink?(url) }
        }
        return defaultAction
    }
}
```

- [ ] **Step 3: Verify it builds** (no unit test — it's a view; verified via snapshot in Task 8 and the Lab in Task 9):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): MarkdownBodyDelegate + ProseBlockView

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Block helper views — ThematicBreakView, PlaceholderBlockView, QuoteBlockView

**Files:** Create `SpudMarkdownKit/Rendering/ThematicBreakView.swift`, `SpudMarkdownKit/Rendering/PlaceholderBlockView.swift`, `SpudMarkdownKit/Rendering/QuoteBlockView.swift`

- [ ] **Step 1:** `ThematicBreakView.swift` — a 0.5pt full-width separator:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

final class ThematicBreakView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .separator
        heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}
```

- [ ] **Step 2:** `PlaceholderBlockView.swift` — a labeled box for not-yet-rendered block kinds (so the Lab shows the whole kitchen sink):
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A muted placeholder for block kinds rendered in a later phase (code, table,
/// spoiler, image, audio, video, footnotes).
final class PlaceholderBlockView: UIView {
    init(label: String) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = 8
        let text = UILabel()
        text.text = "[\(label)]"
        text.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        text.textColor = .secondaryLabel
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}
```

- [ ] **Step 3:** `QuoteBlockView.swift` — a tinted leading bar + inset container holding child block views (built by `MarkdownBodyView` in Task 6; the view just provides the bar + inset and an `addArrangedChild`):
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A blockquote: a colored leading bar and an inset vertical stack of child
/// block views. Nesting is achieved by placing a `QuoteBlockView` inside another.
final class QuoteBlockView: UIView {
    private let stack = UIStackView()

    init(context: MarkdownContext) {
        super.init(frame: .zero)
        let bar = UIView()
        bar.backgroundColor = context.quoteBarColor
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let barWidth: CGFloat = context.kind == .post ? 3 : 2.5
        let inset: CGFloat = context.kind == .post ? 13 : 10
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: barWidth),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func addArrangedChild(_ view: UIView) { stack.addArrangedSubview(view) }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}
```

- [ ] **Step 4: Build to verify** (canonical build command from Task 4 Step 3). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): thematic-break, placeholder, and quote block views

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: MarkdownBodyView — block dispatch & layout

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`

The public top-level view: takes `[MarkdownBlock]` + a `MarkdownContext`, builds a vertical stack of block views (prose rendered; lists rendered with markers as attributed strings; non-prose blocks → `PlaceholderBlockView`), wires link taps to the delegate. Self-sizing via Auto Layout.

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Renders a parsed markdown body (`[MarkdownBlock]`) as a self-sizing vertical
/// stack of block views, in a given context. Phase 2 renders prose blocks
/// (paragraph, heading, list, quote, thematic break); other block kinds show a
/// labeled placeholder.
@MainActor
public final class MarkdownBodyView: UIView {
    public weak var delegate: MarkdownBodyDelegate?
    private let stack = UIStackView()
    private var context: MarkdownContext

    public init(context: MarkdownContext) {
        self.context = context
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = context.interBlockGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Replaces the rendered content with `blocks`.
    public func setBlocks(_ blocks: [MarkdownBlock]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for view in blocks.map({ view(for: $0) }) { stack.addArrangedSubview(view) }
    }

    // MARK: Block -> view

    private func view(for block: MarkdownBlock) -> UIView {
        switch block {
        case let .paragraph(inlines):
            return prose(InlineAttributedStringBuilder.build(inlines, context: context))
        case let .heading(level, inlines):
            return prose(heading(level: level, inlines: inlines))
        case let .unorderedList(items):
            return prose(listAttributed(items, ordered: false, start: 1))
        case let .orderedList(start, items):
            return prose(listAttributed(items, ordered: true, start: start))
        case let .blockQuote(children):
            let quote = QuoteBlockView(context: context)
            for child in children { quote.addArrangedChild(view(for: child)) }
            return quote
        case .thematicBreak:
            return ThematicBreakView()
        case .codeBlock: return PlaceholderBlockView(label: "code")
        case .table: return PlaceholderBlockView(label: "table")
        case .spoiler: return PlaceholderBlockView(label: "spoiler")
        case .image: return PlaceholderBlockView(label: "image")
        case .audio: return PlaceholderBlockView(label: "audio")
        case .video: return PlaceholderBlockView(label: "video")
        case .footnotes: return PlaceholderBlockView(label: "footnotes")
        }
    }

    private func prose(_ attributed: NSAttributedString) -> ProseBlockView {
        let view = ProseBlockView()
        let m = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = context.lineHeightMultiple
        m.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
        view.attributedText = m
        view.onTapLink = { [weak self] url in self?.delegate?.markdownBody(didTapLink: url) }
        return view
    }

    private func heading(level: Int, inlines: [MarkdownInline]) -> NSAttributedString {
        let font = context.headingFont(level: level)
        let color: UIColor = level == 6 ? context.secondaryColor : context.labelColor
        let inner = InlineAttributedStringBuilder.build(inlines, context: context)
        let m = NSMutableAttributedString(attributedString: inner)
        let full = NSRange(location: 0, length: m.length)
        m.addAttributes([.font: font, .foregroundColor: color], range: full)
        if level == 6 {
            m.replaceCharacters(in: full, with: NSAttributedString(
                string: m.string.uppercased(),
                attributes: [.font: font, .foregroundColor: color]))
        }
        return m
    }

    private func listAttributed(_ items: [MarkdownListItem], ordered: Bool, start: Int) -> NSAttributedString {
        // Phase 2: flat-render each item's first paragraph with a marker prefix and
        // hanging indent. Nested lists/blocks recurse with deeper indent.
        let out = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            let marker = ordered ? "\(start + i)." : "\u{2022}"
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = context.listIndent
            paragraph.firstLineHeadIndent = 0
            paragraph.lineHeightMultiple = context.lineHeightMultiple
            let markerStr = NSAttributedString(string: "\(marker)\t", attributes: [
                .font: context.bodyFont, .foregroundColor: context.secondaryColor,
                .paragraphStyle: paragraph,
            ])
            out.append(markerStr)
            // First paragraph's inlines inline; deeper blocks are dropped in Phase 2
            // flat rendering (nested lists handled in Phase 3 list-view work).
            if case let .paragraph(inlines)? = item.blocks.first {
                let content = NSMutableAttributedString(
                    attributedString: InlineAttributedStringBuilder.build(inlines, context: context))
                content.addAttribute(.paragraphStyle, value: paragraph,
                                     range: NSRange(location: 0, length: content.length))
                out.append(content)
            }
            if i < items.count - 1 { out.append(NSAttributedString(string: "\n")) }
        }
        return out
    }
}
```

- [ ] **Step 2: Build to verify** (canonical build command). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): MarkdownBodyView block dispatch + prose layout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

NOTE: nested-list rendering and tight list-item spacing are intentionally simplified in Phase 2 (flat marker + hanging indent on the first paragraph). Full nested-list and multi-block list items are Phase 3 list-view work. This is called out as a known Phase-2 limitation.

---

## Task 7: Lab control bar

**Files:** Create `MarkdownLab/LabControlBar.swift`

A SwiftUI control row: context (post/comment), theme (light/dark/true-black), text-scale stepper, density toggle. Drives the render in Task 8.

- [ ] **Step 1: Implement** `MarkdownLab/LabControlBar.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SpudUIKit
import SwiftUI

/// The live render configuration the Lab toggles.
struct LabConfig: Equatable, Hashable {
    var kind: MarkdownContextKind = .post
    var style: ColorScheme = .light
    var trueBlack = false
    var textScale: CGFloat = 0
    var density: PostDensity = .comfortable
}

struct LabControlBar: View {
    @Binding var config: LabConfig

    var body: some View {
        VStack(spacing: 8) {
            Picker("Context", selection: $config.kind) {
                Text("Post").tag(MarkdownContextKind.post)
                Text("Comment").tag(MarkdownContextKind.comment)
            }.pickerStyle(.segmented)

            HStack {
                Picker("Theme", selection: $config.style) {
                    Text("Light").tag(ColorScheme.light)
                    Text("Dark").tag(ColorScheme.dark)
                }.pickerStyle(.segmented)
                Toggle("OLED", isOn: $config.trueBlack).fixedSize()
            }

            HStack {
                Stepper("Scale \(Int(config.textScale))", value: $config.textScale, in: -3 ... 6)
                Toggle("Compact", isOn: Binding(
                    get: { config.density == .compact },
                    set: { config.density = $0 ? .compact : .comfortable })).fixedSize()
            }
        }
        .font(.footnote)
        .padding(.horizontal)
    }
}
```

- [ ] **Step 2: Build the Lab** (it won't be wired until Task 8, but should compile):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit.**
```bash
make project && mint run swiftformat MarkdownLab
git add MarkdownLab
git commit -m "feat(markdown): MarkdownLab control bar

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Wire the Lab to render MarkdownBodyView

**Files:** Modify `MarkdownLab/MarkdownLabApp.swift`

Replace the parse-tree text dump with a hosted `MarkdownBodyView`, driven by the control bar.

- [ ] **Step 1: Replace** `MarkdownLab/MarkdownLabApp.swift` `LabView` with an editor + control bar + a `UIViewRepresentable` host. (Keep the `@main` struct.) Full file:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SpudUIKit
import SwiftUI

@main
struct MarkdownLabApp: App {
    var body: some Scene { WindowGroup { LabView() } }
}

private let defaultSample = """
Valve **finally** shipped SteamOS, with ~~three~~ two rough edges. Ping @glidergun@lemmy.world or drop into !linux_gaming@lemmy.world. Smart quotes "work," en--dashes too.

# H1 — Section title
## H2 — Subsection

- A USB-C drive, **8 GB or larger**.
- The official `rufus` flasher.

1. Disable Secure Boot.
2. Flash the recovery image.

> Third-party support is **best-effort**.

H~2~O and E=mc^2^. See https://store.steampowered.com/steamos for details.

---
"""

struct LabView: View {
    @State private var source = defaultSample
    @State private var config = LabConfig()

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $source)
                .font(.system(.footnote, design: .monospaced))
                .frame(height: 150)
                .border(.separator)
            LabControlBar(config: $config)
                .padding(.vertical, 6)
            Divider()
            ScrollView {
                // Keying on `config` makes SwiftUI recreate the host (and thus a
                // fresh MarkdownBodyView with a fresh context) whenever a toggle
                // changes; source-only edits re-render via updateUIView.
                MarkdownBodyHost(source: source, config: config)
                    .id(config)
                    .padding(16)
            }
        }
        .preferredColorScheme(config.style)
    }
}

/// Hosts the UIKit `MarkdownBodyView`. The context is baked at init from
/// `config`; `LabView` keys this host on `config` so a toggle change recreates
/// it. `updateUIView` handles live source edits.
struct MarkdownBodyHost: UIViewRepresentable {
    let source: String
    let config: LabConfig

    func makeUIView(context _: Context) -> MarkdownBodyView {
        let view = MarkdownBodyView(
            context: MarkdownContext(kind: config.kind, textScale: config.textScale, density: config.density))
        view.setBlocks(MarkdownParser.parse(source))
        return view
    }

    func updateUIView(_ uiView: MarkdownBodyView, context _: Context) {
        uiView.setBlocks(MarkdownParser.parse(source))
    }
}
```

- [ ] **Step 2: Build + boot the Lab and eyeball it:**
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /tmp/mdlab-dd build 2>&1 | tail -8
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$(find /tmp/mdlab-dd -name MarkdownLab.app -type d | head -1)"
xcrun simctl launch booted info.ddenis.MarkdownLab
```
Expected: the Lab shows the editor, the control bar, and the **rendered** body below — bold/italic, H1/H2 at the right scale, bullet + numbered lists, a quoted line with a bar, teal links and @mention/!community chips, superscript/subscript, and a horizontal rule. Flipping Post/Comment, Light/Dark, scale, and Compact visibly changes the render. (Take a screenshot with `xcrun simctl io booted screenshot /tmp/mdlab.png` and review it.)

- [ ] **Step 3: Commit.**
```bash
make project && mint run swiftformat MarkdownLab
git add MarkdownLab
git commit -m "feat(markdown): Lab renders MarkdownBodyView live

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Prose snapshot tests

**Files:** Create `SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests.swift`

Lock the rendered output: the prose kitchen sink in post/comment × light/dark, at a pinned width and scale (device-independent).

- [ ] **Step 1: Write the snapshot test** at `SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudMarkdownKit
import UIKit
import XCTest

final class MarkdownProseSnapshotTests: XCTestCase {
    private let sample = """
    Valve **finally** shipped it, with ~~three~~ two edges. Ping @alice@lemmy.world in !linux@lemmy.world.

    # Heading One
    ## Heading Two

    - first **item**
    - second `item`

    1. step one
    2. step two

    > a quoted line

    H~2~O and E=mc^2^. A [link](https://example.com).

    ---
    """

    @MainActor
    private func render(kind: MarkdownContextKind, width: CGFloat = 360) -> UIView {
        let view = MarkdownBodyView(context: MarkdownContext(kind: kind))
        view.setBlocks(MarkdownParser.parse(sample))
        view.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            view.widthAnchor.constraint(equalToConstant: width - 32),
        ])
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.layoutIfNeeded()
        container.frame = CGRect(x: 0, y: 0, width: width,
                                 height: container.systemLayoutSizeFitting(
                                    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)).height)
        return container
    }

    @MainActor
    func test_postLight() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_postDark() {
        assertSnapshot(of: render(kind: .post), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @MainActor
    func test_commentLight() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .light)))
    }

    @MainActor
    func test_commentDark() {
        assertSnapshot(of: render(kind: .comment), as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }
}
```

- [ ] **Step 2: Record then verify.** First run records references and fails:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests test 2>&1 | tail -20
```
First run: records 4 `__Snapshots__` PNGs and FAILS (expected for new refs). **Open the 4 PNGs and eyeball them against the design** (post body generous, comment denser, teal links/chips, heading scale, quote bar, sub/sup). If they look right, re-run the same command — expect `** TEST SUCCEEDED **` (verifies against the recorded refs). If they look wrong, fix the rendering (Tasks 2–6) and re-record.

- [ ] **Step 3: Commit** (the new test + the recorded reference PNGs):
```bash
make project && mint run swiftformat SpudMarkdownKitSnapshotTests
git add SpudMarkdownKitSnapshotTests
git commit -m "test(markdown): prose render snapshots (post/comment x light/dark)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
NOTE: these snapshot refs are NOT git-annex tracked (they're under `SpudMarkdownKitSnapshotTests/`, not `SpudSnapshotTests/__Snapshots__/`); they commit as normal files.

---

## Final verification

- [ ] Full framework target green:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` (Phase 1 unit tests + the new MarkdownContext/InlineAttributedStringBuilder/MarkdownColors tests + 4 prose snapshots).

- [ ] Main Spud app still builds:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

## Done criteria for Phase 2

- `MarkdownBodyView(context:).setBlocks(MarkdownParser.parse(source))` renders prose (paragraph/heading/list/quote/hr) + the full inline layer (bold/italic/strike/highlight/code/sup/sub/link/mention/community/emoji/footnote-ref) into self-sizing UIKit views.
- The Lab shows it live with post/comment × light/dark/OLED × text-scale × density toggles.
- Prose render is snapshot-locked (post/comment × light/dark) and eyeballed against the design.
- Deterministic units (context, inline builder, colors) are unit-tested; full target + Spud app green.

## Known Phase-2 limitations (carried forward)

- Nested lists and multi-block list items render flat (first paragraph only) — full list-view rendering is Phase 3.
- Mentions/communities are accent text + glyph + rectangular chip background — the rounded-pill chip is a Phase-3 polish.
- Custom emoji renders as literal `:shortcode:` (server-emoji image is Phase 3+).
- Plus all carried Phase-1 items (fence-aware preprocessors, spoiler-in-list, etc.).

## Next (separate plans)

- **Phase 3** — structural/interactive block views: `CodeBlockView` (copy + h-scroll), `TableBlockView`, `SpoilerBlockView`, `FootnotesBlockView`, plus full nested-list rendering and the rounded mention/community chip.
- **Phase 4** — media: `ImageBlockView` (states/zoom/caption), `AudioBlockView`, `VideoBlockView`.
- **Phase 5** — snapshot suite breadth + edge cases.
- **Phase 6** — integration into Spud (replace `BodyTextView`/`LinkLabel`) + wire delegate to real navigation/media/haptics + fix carried parser limitations.
</content>
