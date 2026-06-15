# Markdown Renderer — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the `SpudMarkdownKit` framework and `MarkdownLab` test app, and build the pure markdown→block-tree parser (data model + swift-markdown walk + Lemmy-extension passes) with full unit-test coverage.

**Architecture:** A new `SpudMarkdownKit` iOS framework (no app dependency) exposes `MarkdownParser.parse(_:) -> [MarkdownBlock]`. Parsing is layered, the same shape Lemmy uses (markdown-it + plugins): pre-process the raw source to lift out spoiler containers and footnote definitions, parse the remainder with Apple's `swift-markdown` into a `MarkdownBlock` tree, then run a custom inline lexer over text runs for Lemmy's inline extensions. The `MarkdownLab` app renders a live parse-tree dump so the parser is exercised end-to-end without building Spud. Rendering (real block views) is Phases 2–5, planned separately.

**Tech Stack:** Swift 6 (strict concurrency complete), UIKit/SwiftUI, XcodeGen (`project.yml` → `make project`), Apple `swift-markdown`, XCTest.

---

## Scope

This plan is **Phase 1 only** — the framework/Lab scaffold and the parser. It produces working, testable software on its own: a unit-tested parser plus an app that shows the parse tree. Phases 2–5 (prose blocks, structural/interactive blocks, media blocks, snapshot suite) and Phase 6 (integration into Spud) are separate plans, written once Phase 1's shapes are real. See `docs/superpowers/specs/2026-06-15-markdown-renderer-design.md`.

## File Structure

Created in this plan:

```
SpudMarkdownKit/                         ← new framework target
  Model/
    MarkdownBlock.swift                  ← block enum + MarkdownListItem
    MarkdownInline.swift                 ← inline enum
    MarkdownTable.swift                  ← table value type + Alignment
    MarkdownImage.swift                  ← image value type
    MarkdownFootnote.swift               ← footnote value type
  Parsing/
    SmartTypography.swift                ← straight→curly quotes, dashes, ellipsis, (c)/(tm)/(r)
    InlineLexer.swift                    ← Text-run lexer for Lemmy inline extensions
    BlockParser.swift                    ← swift-markdown Document → [MarkdownBlock]
    MediaDetector.swift                  ← URL extension → image/audio/video
    SpoilerPreprocessor.swift            ← lift ::: spoiler containers to sentinels
    FootnoteExtractor.swift              ← lift [^n]: definitions out of the source
    MarkdownParser.swift                 ← public top-level orchestrator
SpudMarkdownKitTests/                    ← new unit-test target
  SmartTypographyTests.swift
  InlineLexerTests.swift
  BlockParserTests.swift
  SpoilerPreprocessorTests.swift
  FootnoteExtractorTests.swift
  MediaDetectorTests.swift
  MarkdownParserTests.swift              ← kitchen-sink golden integration test
  Fixtures/KitchenSink.swift            ← the kitchen-sink markdown source (ported from md-content.jsx)
MarkdownLab/                             ← new app target
  MarkdownLabApp.swift                   ← SwiftUI @main + parse-tree dump view
  BlockTreeDump.swift                    ← MarkdownBlock → debug lines
project.yml                             ← MODIFIED: package + 3 targets + 2 schemes
```

## Conventions used in every task

**MUST regenerate before every build/test.** The generated `Spud.xcodeproj` is gitignored and only picks up newly-created `.swift` files when XcodeGen re-runs. Therefore **every** `xcodebuild` invocation in this plan is preceded by `make project` — it is shown in the canonical command below and is REQUIRED before each build/test step even where an individual command omits it for brevity. (This worktree has a `../LemmyKit` symlink, so package resolution works here.)

**Canonical test command** (regenerate, then run on an iOS simulator — a framework scheme defaults to "My Mac" and fails without a simulator destination; the plugin/macro skip flags keep fresh derived-data builds non-interactive):

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/<CLASS>/<METHOD> test 2>&1 | tail -30
```

**swift-markdown API note:** A few `Markdown` accessor names (e.g. table cell access, `OrderedList.startIndex` integer type, `CodeBlock.language`) can vary by version. Where a failing-compile step reveals a mismatch, adjust to the compiler — the code below is written against `swift-markdown` on `main` (June 2026). This is the only place external-API drift is expected.

**Copyright header** — every new `.swift` file starts with the repo header:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
```

**Format before committing:** `mint run swiftformat <changed files>` (the pre-commit hook lints only).

---

## Task 1: Scaffold the framework, test target, Lab app, and swift-markdown package

**Files:**
- Modify: `project.yml` (packages, targets, schemes)
- Create: `SpudMarkdownKit/Model/MarkdownInline.swift` (placeholder so the framework has a source file)
- Create: `MarkdownLab/MarkdownLabApp.swift` (minimal app so the target builds)
- Create: `SpudMarkdownKitTests/ScaffoldTests.swift` (one trivial test so the bundle builds)

- [ ] **Step 1: Add the swift-markdown package.** In `project.yml`, under `packages:`, after the `Down:` entry, add:

```yaml
  SwiftMarkdown:
    url: https://github.com/apple/swift-markdown
    branch: main
```

- [ ] **Step 2: Add the three targets.** In `project.yml`, under `targets:`, after the `SpudUtilKit:` target block (before `SpudTests:`), add:

```yaml
  SpudMarkdownKit:
    type: framework
    platform: iOS
    sources:
      - SpudMarkdownKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: info.ddenis.SpudMarkdownKit
        DEFINES_MODULE: "YES"
    dependencies:
      - target: SpudUIKit
      - target: SpudUtilKit
      - package: SwiftMarkdown
        product: Markdown

  SpudMarkdownKitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - SpudMarkdownKitTests
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: info.ddenis.SpudMarkdownKitTests
    dependencies:
      - target: SpudMarkdownKit

  MarkdownLab:
    type: application
    platform: iOS
    sources:
      - MarkdownLab
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: info.ddenis.MarkdownLab
        GENERATE_INFOPLIST_FILE: "YES"
        INFOPLIST_KEY_UILaunchScreen_Generation: "YES"
    dependencies:
      - target: SpudMarkdownKit
      - target: SpudUIKit
```

- [ ] **Step 3: Add the two schemes.** In `project.yml`, under `schemes:`, after the `SpudUIKit:` scheme block, add:

```yaml
  SpudMarkdownKit:
    build:
      targets:
        SpudMarkdownKit: all
        SpudMarkdownKitTests: [test]
    test:
      targets:
        - SpudMarkdownKitTests

  MarkdownLab:
    build:
      targets:
        MarkdownLab: all
    run:
      config: Debug
```

- [ ] **Step 4: Create the placeholder framework source** at `SpudMarkdownKit/Model/MarkdownInline.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Placeholder — replaced in Task 2.
enum SpudMarkdownKitScaffold {}
```

- [ ] **Step 5: Create the minimal Lab app** at `MarkdownLab/MarkdownLabApp.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI

@main
struct MarkdownLabApp: App {
    var body: some Scene {
        WindowGroup {
            Text("MarkdownLab")
        }
    }
}
```

- [ ] **Step 6: Create the scaffold test** at `SpudMarkdownKitTests/ScaffoldTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class ScaffoldTests: XCTestCase {
    func test_frameworkLinks() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 7: Regenerate the project.** Run:

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum && make project
```

Expected: `Loaded project … Created project at Spud.xcodeproj` with no error. (First run resolves swift-markdown — allow network.)

- [ ] **Step 8: Build + run the scaffold test.** Run:

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/ScaffoldTests/test_frameworkLinks test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. Also confirm the Lab builds:

```bash
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
mint run swiftformat SpudMarkdownKit MarkdownLab SpudMarkdownKitTests
git add project.yml SpudMarkdownKit MarkdownLab SpudMarkdownKitTests
git commit -m "feat(markdown): scaffold SpudMarkdownKit framework + MarkdownLab app

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Define the block & inline data model

**Files:**
- Modify: `SpudMarkdownKit/Model/MarkdownInline.swift`
- Create: `SpudMarkdownKit/Model/MarkdownBlock.swift`
- Create: `SpudMarkdownKit/Model/MarkdownTable.swift`
- Create: `SpudMarkdownKit/Model/MarkdownImage.swift`
- Create: `SpudMarkdownKit/Model/MarkdownFootnote.swift`
- Test: `SpudMarkdownKitTests/ScaffoldTests.swift` (extend with a model test)

The model is two value-type trees. `mention`/`community` carry `name` + `instance` only (no baked URL) — the host derives the navigation target at tap time via the existing `LemmyURLParser`, so the framework stays decoupled from the app's internal URL scheme.

- [ ] **Step 1: Write the failing test.** Replace the body of `SpudMarkdownKitTests/ScaffoldTests.swift` with:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class ModelTests: XCTestCase {
    func test_blocksAreEquatable() {
        let a: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        let b: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        XCTAssertEqual(a, b)
    }

    func test_tableModelHoldsAlignmentsHeadRows() {
        let table = MarkdownTable(
            alignments: [.left, .right],
            head: [[.text("A")], [.text("B")]],
            rows: [[[.text("1")], [.text("2")]]]
        )
        XCTAssertEqual(table.alignments, [.left, .right])
        XCTAssertEqual(table.rows.count, 1)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/ModelTests test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'MarkdownBlock'` / `'MarkdownTable'`.

- [ ] **Step 3: Write the inline model.** Replace `SpudMarkdownKit/Model/MarkdownInline.swift` with:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A span of inline content inside a block. Recursive so emphasis/strong/etc.
/// can nest. `mention`/`community` carry only `name` + `instance`; the host
/// derives the navigation destination at tap time.
public indirect enum MarkdownInline: Equatable, Sendable {
    case text(String)                                   // already smart-typographed
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case highlight([MarkdownInline])                    // ==mark==
    case code(String)                                   // inline code, never wraps
    case superscript([MarkdownInline])                  // ^x^
    case `subscript`([MarkdownInline])                  // ~x~
    case link(text: [MarkdownInline], url: URL)
    case mention(name: String, instance: String)        // @user@instance
    case community(name: String, instance: String)      // !community@instance
    case emoji(String)                                  // resolved unicode
    case customEmoji(shortcode: String)                 // ::shortcode:: (server emoji)
    case footnoteReference(String)                      // [^label]
}
```

- [ ] **Step 4: Write the block model** at `SpudMarkdownKit/Model/MarkdownBlock.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A top-level (or nested) block in a rendered body.
public indirect enum MarkdownBlock: Equatable, Sendable {
    case paragraph([MarkdownInline])
    case heading(level: Int, [MarkdownInline])
    case unorderedList([MarkdownListItem])
    case orderedList(start: Int, [MarkdownListItem])
    case blockQuote([MarkdownBlock])
    case codeBlock(language: String?, code: String)
    case table(MarkdownTable)
    case image(MarkdownImage)
    case audio(url: URL)
    case video(url: URL)
    case spoiler(title: [MarkdownInline], children: [MarkdownBlock])  // title empty => render fallback label
    case footnotes([MarkdownFootnote])
    case thematicBreak
}

/// One list item; its content is itself a sequence of blocks (typically a
/// paragraph, optionally followed by a nested list).
public struct MarkdownListItem: Equatable, Sendable {
    public var blocks: [MarkdownBlock]
    public init(blocks: [MarkdownBlock]) { self.blocks = blocks }
}
```

- [ ] **Step 5: Write the table model** at `SpudMarkdownKit/Model/MarkdownTable.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct MarkdownTable: Equatable, Sendable {
    public enum Alignment: Equatable, Sendable { case left, center, right }

    /// One entry per column; `head`/`rows` cells are inline content.
    public var alignments: [Alignment]
    public var head: [[MarkdownInline]]
    public var rows: [[[MarkdownInline]]]

    public init(alignments: [Alignment], head: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.alignments = alignments
        self.head = head
        self.rows = rows
    }
}
```

- [ ] **Step 6: Write the image model** at `SpudMarkdownKit/Model/MarkdownImage.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct MarkdownImage: Equatable, Sendable {
    public var url: URL
    public var altText: String?

    public init(url: URL, altText: String?) {
        self.url = url
        let trimmed = altText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.altText = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
```

- [ ] **Step 7: Write the footnote model** at `SpudMarkdownKit/Model/MarkdownFootnote.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct MarkdownFootnote: Equatable, Sendable {
    public var label: String
    public var content: [MarkdownInline]

    public init(label: String, content: [MarkdownInline]) {
        self.label = label
        self.content = content
    }
}
```

- [ ] **Step 8: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/ModelTests test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`. (New files were added, so `make project` already ran in Task 1; if the build can't find the new files, run `make project` again.)

- [ ] **Step 9: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): add block & inline data model

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Smart typography

**Files:**
- Create: `SpudMarkdownKit/Parsing/SmartTypography.swift`
- Create: `SpudMarkdownKitTests/SmartTypographyTests.swift`

Ports the reference `smart()` transform: `(c)/(tm)/(r)`, `---`→em-dash, `--`→en-dash, `...`→ellipsis, straight→curly quotes.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/SmartTypographyTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class SmartTypographyTests: XCTestCase {
    func test_dashesAndEllipsis() {
        XCTAssertEqual(SmartTypography.apply("en--dash em---dash ..."), "en\u{2013}dash em\u{2014}dash \u{2026}")
    }

    func test_symbols() {
        XCTAssertEqual(SmartTypography.apply("(c) (tm) (r)"), "\u{00A9} \u{2122} \u{00AE}")
    }

    func test_doubleQuotes() {
        XCTAssertEqual(SmartTypography.apply("\"smart quotes,\""), "\u{201C}smart quotes,\u{201D}")
    }

    func test_apostrophe() {
        XCTAssertEqual(SmartTypography.apply("don't"), "don\u{2019}t")
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/SmartTypographyTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'SmartTypography'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/SmartTypography.swift`. The `---` before `--` ordering matters (longest first).

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// markdown-it `typographer:true` equivalent: smart quotes, dashes, ellipsis,
/// and the (c)/(tm)/(r) symbols. Applied to plain text runs during lexing.
enum SmartTypography {
    static func apply(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "(c)", with: "\u{00A9}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "(tm)", with: "\u{2122}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "(r)", with: "\u{00AE}", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "---", with: "\u{2014}")
        s = s.replacingOccurrences(of: "--", with: "\u{2013}")
        s = s.replacingOccurrences(of: "...", with: "\u{2026}")
        // Paired double quotes → “ … ”
        s = s.replacing(/"([^"]*)"/) { match in "\u{201C}\(match.1)\u{201D}" }
        // Opening single quote after start / whitespace / opening bracket → ‘
        s = s.replacing(/(^|[\s(\[{])'/) { match in "\(match.1)\u{2018}" }
        // Any remaining straight apostrophe → ’
        s = s.replacingOccurrences(of: "'", with: "\u{2019}")
        return s
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/SmartTypographyTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): smart typography transform

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Inline lexer — extensions over text runs

**Files:**
- Create: `SpudMarkdownKit/Parsing/InlineLexer.swift`
- Create: `SpudMarkdownKitTests/InlineLexerTests.swift`

`InlineLexer.parse` runs on the string of a single swift-markdown `Text` node, so `**bold**`, `*italic*`, `` `code` ``, `[t](u)`, `~~strike~~` are already gone (handled structurally in Task 6). The lexer only catches what swift-markdown leaves as literal text: `[^n]`, `==mark==`, `^sup^`, `~sub~`, `::custom::`, `:emoji:`, `!community@inst`, `@user@inst`, and bare-URL/`www.` autolinks. Plain runs get `SmartTypography.apply`. Rule order matters (longest/most-specific first; `::` before `:`; mention/community before autolink).

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/InlineLexerTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class InlineLexerTests: XCTestCase {
    func test_plainTextGetsSmartTypography() {
        XCTAssertEqual(InlineLexer.parse("a--b"), [.text("a\u{2013}b")])
    }

    func test_highlight() {
        XCTAssertEqual(InlineLexer.parse("see ==this=="), [.text("see "), .highlight([.text("this")])])
    }

    func test_superscriptAndSubscript() {
        XCTAssertEqual(InlineLexer.parse("E=mc^2^"), [.text("E=mc"), .superscript([.text("2")])])
        XCTAssertEqual(InlineLexer.parse("H~2~O"), [.text("H"), .subscript([.text("2")]), .text("O")])
    }

    func test_mentionAndCommunity() {
        XCTAssertEqual(
            InlineLexer.parse("ping @glidergun@lemmy.world in !linux_gaming@lemmy.world"),
            [
                .text("ping "),
                .mention(name: "glidergun", instance: "lemmy.world"),
                .text(" in "),
                .community(name: "linux_gaming", instance: "lemmy.world"),
            ]
        )
    }

    func test_footnoteReference() {
        XCTAssertEqual(InlineLexer.parse("welcome[^1]"), [.text("welcome"), .footnoteReference("1")])
    }

    func test_autolink() {
        let result = InlineLexer.parse("see https://lemmy.world/post/42 now")
        guard case let .link(text, url) = result[1] else { return XCTFail("expected link, got \(result)") }
        XCTAssertEqual(url, URL(string: "https://lemmy.world/post/42"))
        XCTAssertEqual(text, [.text("https://lemmy.world/post/42")])
    }

    func test_knownEmojiAndCustomEmoji() {
        XCTAssertEqual(InlineLexer.parse(":penguin:"), [.emoji("\u{1F427}")])
        XCTAssertEqual(InlineLexer.parse("::potato::"), [.customEmoji(shortcode: "potato")])
    }

    func test_unknownEmojiStaysLiteral() {
        XCTAssertEqual(InlineLexer.parse(":not_an_emoji:"), [.text(":not_an_emoji:")])
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/InlineLexerTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'InlineLexer'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/InlineLexer.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lexes the inline extensions Lemmy adds on top of CommonMark, operating on the
/// plain string of one swift-markdown `Text` node (structural inlines like bold,
/// links, and `~~strike~~` are already consumed by swift-markdown).
enum InlineLexer {
    static func parse(_ string: String) -> [MarkdownInline] {
        var out: [MarkdownInline] = []
        var buffer = ""

        func flushText() {
            if !buffer.isEmpty {
                out.append(.text(SmartTypography.apply(buffer)))
                buffer = ""
            }
        }

        var index = string.startIndex
        while index < string.endIndex {
            let rest = string[index...]
            if let (inline, consumed) = match(rest) {
                flushText()
                out.append(inline)
                index = string.index(index, offsetBy: consumed)
            } else {
                buffer.append(string[index])
                index = string.index(after: index)
            }
        }
        flushText()
        return out
    }

    /// Tries each extension rule, anchored at the start of `rest`. Returns the
    /// produced inline and the number of Characters consumed.
    private static func match(_ rest: Substring) -> (MarkdownInline, Int)? {
        func count(_ upper: Substring.Index) -> Int { rest.distance(from: rest.startIndex, to: upper) }

        if let m = rest.prefixMatch(of: /\[\^([\w-]+)\]/) {
            return (.footnoteReference(String(m.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /==([^=]+)==/) {
            return (.highlight(parse(String(m.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /::([a-zA-Z0-9_+\-]+)::/) {
            return (.customEmoji(shortcode: String(m.1)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /:([a-zA-Z0-9_+\-]+):/) {
            let name = String(m.1)
            if let scalar = Emoji.map[name] {
                return (.emoji(scalar), count(m.range.upperBound))
            }
            return nil  // unknown shortcode → fall through to literal text
        }
        if let m = rest.prefixMatch(of: /\^([^\^\s]+)\^/) {
            return (.superscript(parse(String(m.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /~([^~\s]+)~/) {
            return (.subscript(parse(String(m.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /!([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/) {
            return (.community(name: String(m.1), instance: String(m.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /@([a-zA-Z0-9_]+)@([a-zA-Z0-9.\-]+)/) {
            return (.mention(name: String(m.1), instance: String(m.2)), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /https?:\/\/[^\s)<]+[^\s).,;:!?'"<]/) {
            let raw = String(m.0)
            if let url = URL(string: raw) {
                return (.link(text: [.text(raw)], url: url), count(m.range.upperBound))
            }
            return nil
        }
        if let m = rest.prefixMatch(of: /www\.[^\s)<]+[^\s).,;:!?'"<]/) {
            let raw = String(m.0)
            if let url = URL(string: "https://\(raw)") {
                return (.link(text: [.text(raw)], url: url), count(m.range.upperBound))
            }
            return nil
        }
        return nil
    }
}
```

- [ ] **Step 4: Add the emoji map** in the same file (append after the `InlineLexer` enum), a small subset ported from `md-content.jsx` (extend later as needed):

```swift
/// Minimal `:shortcode:` → unicode table. Unknown shortcodes render literally.
enum Emoji {
    static let map: [String: String] = [
        "smile": "\u{1F604}", "grinning": "\u{1F600}", "joy": "\u{1F602}", "wave": "\u{1F44B}",
        "rocket": "\u{1F680}", "tada": "\u{1F389}", "fire": "\u{1F525}", "eyes": "\u{1F440}",
        "heart": "\u{2764}\u{FE0F}", "+1": "\u{1F44D}", "-1": "\u{1F44E}", "thinking": "\u{1F914}",
        "sob": "\u{1F62D}", "sweat_smile": "\u{1F605}", "sparkles": "\u{2728}", "penguin": "\u{1F427}",
        "bulb": "\u{1F4A1}", "warning": "\u{26A0}\u{FE0F}", "white_check_mark": "\u{2705}",
        "potato": "\u{1F954}", "robot": "\u{1F916}", "zap": "\u{26A1}", "tv": "\u{1F4FA}",
        "sound": "\u{1F50A}",
    ]
}
```

Note: `:potato:` is in the emoji map, so `:potato:` lexes to `.emoji`. Custom emoji uses the **double-colon** form `::potato::` (per the reference), which is matched earlier and yields `.customEmoji`.

- [ ] **Step 5: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/InlineLexerTests test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

**If `test_superscriptAndSubscript` fails because the `~2~` was already consumed by swift-markdown** — it cannot here, because this test calls `InlineLexer.parse` directly on a raw string (swift-markdown is not involved). The interaction is checked end-to-end in Task 10; if a single-tilde subscript in real markdown is swallowed by swift-markdown's strikethrough there, the fix is to sentinel-escape `^…^` and `~…~` in a pre-pass before `Document(parsing:)` and restore them in the lexer. That contingency is called out again in Task 10.

- [ ] **Step 6: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): inline lexer for Lemmy extensions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Media detector

**Files:**
- Create: `SpudMarkdownKit/Parsing/MediaDetector.swift`
- Create: `SpudMarkdownKitTests/MediaDetectorTests.swift`

Classifies a URL by file extension so a body image/link to media becomes an `audio`/`video` block (Lemmy renders body media links as players).

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/MediaDetectorTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MediaDetectorTests: XCTestCase {
    func test_image() {
        XCTAssertEqual(MediaDetector.kind(of: URL(string: "https://x/y.jpg")!), .image)
        XCTAssertEqual(MediaDetector.kind(of: URL(string: "https://x/y.PNG")!), .image)
    }

    func test_audio() {
        XCTAssertEqual(MediaDetector.kind(of: URL(string: "https://x/clip.mp3")!), .audio)
    }

    func test_video() {
        XCTAssertEqual(MediaDetector.kind(of: URL(string: "https://x/clip.mp4")!), .video)
    }

    func test_unknownDefaultsToImage() {
        // A bare image link with no extension is treated as a still image.
        XCTAssertEqual(MediaDetector.kind(of: URL(string: "https://x/pictrs/image/abc")!), .image)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MediaDetectorTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'MediaDetector'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/MediaDetector.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum MediaKind: Equatable, Sendable { case image, audio, video }

/// Classifies a media URL by file extension. Defaults to `.image` (a bare
/// image link with no extension is the common pict-rs case).
enum MediaDetector {
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac"]
    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv"]

    static func kind(of url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        return .image
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MediaDetectorTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): media URL classifier

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Block parser — swift-markdown walk

**Files:**
- Create: `SpudMarkdownKit/Parsing/BlockParser.swift`
- Create: `SpudMarkdownKitTests/BlockParserTests.swift`

Walks a swift-markdown `Document` into `[MarkdownBlock]`: paragraphs, headings, thematic breaks, code blocks, lists (nested), blockquotes (nested), tables, and standalone images (→ image/audio/video via `MediaDetector`). Inline children convert to `[MarkdownInline]`, with `Text` nodes handed to `InlineLexer`.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/BlockParserTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class BlockParserTests: XCTestCase {
    func test_paragraphWithBoldAndExtension() {
        let blocks = BlockParser.document("Valve **finally** shipped ==SteamOS==")
        XCTAssertEqual(blocks, [
            .paragraph([
                .text("Valve "),
                .strong([.text("finally")]),
                .text(" shipped "),
                .highlight([.text("SteamOS")]),
            ]),
        ])
    }

    func test_headings() {
        XCTAssertEqual(BlockParser.document("# Title"), [.heading(level: 1, [.text("Title")])])
        XCTAssertEqual(BlockParser.document("### Topic"), [.heading(level: 3, [.text("Topic")])])
    }

    func test_thematicBreak() {
        XCTAssertEqual(BlockParser.document("---"), [.thematicBreak])
    }

    func test_codeBlock() {
        let blocks = BlockParser.document("```bash\necho hi\n```")
        XCTAssertEqual(blocks, [.codeBlock(language: "bash", code: "echo hi")])
    }

    func test_orderedListWithStart() {
        let blocks = BlockParser.document("3. first\n4. second")
        XCTAssertEqual(blocks, [
            .orderedList(start: 3, [
                MarkdownListItem(blocks: [.paragraph([.text("first")])]),
                MarkdownListItem(blocks: [.paragraph([.text("second")])]),
            ]),
        ])
    }

    func test_nestedUnorderedList() {
        let blocks = BlockParser.document("- a\n    - b")
        XCTAssertEqual(blocks, [
            .unorderedList([
                MarkdownListItem(blocks: [
                    .paragraph([.text("a")]),
                    .unorderedList([MarkdownListItem(blocks: [.paragraph([.text("b")])])]),
                ]),
            ]),
        ])
    }

    func test_nestedBlockQuote() {
        let blocks = BlockParser.document("> outer\n>\n> > inner")
        XCTAssertEqual(blocks, [
            .blockQuote([
                .paragraph([.text("outer")]),
                .blockQuote([.paragraph([.text("inner")])]),
            ]),
        ])
    }

    func test_table() {
        let source = """
        | Sub | OK |
        |:---|---:|
        | Suspend | yes |
        """
        XCTAssertEqual(BlockParser.document(source), [
            .table(MarkdownTable(
                alignments: [.left, .right],
                head: [[.text("Sub")], [.text("OK")]],
                rows: [[[.text("Suspend")], [.text("yes")]]]
            )),
        ])
    }

    func test_standaloneImage() {
        let blocks = BlockParser.document("![a cat](https://x/cat.jpg)")
        XCTAssertEqual(blocks, [.image(MarkdownImage(url: URL(string: "https://x/cat.jpg")!, altText: "a cat"))])
    }

    func test_standaloneVideoLinkBecomesVideoBlock() {
        let blocks = BlockParser.document("![clip](https://x/clip.mp4)")
        XCTAssertEqual(blocks, [.video(url: URL(string: "https://x/clip.mp4")!)])
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/BlockParserTests test 2>&1 | tail -30
```

Expected: compile failure — `cannot find 'BlockParser'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/BlockParser.swift`. (If a swift-markdown accessor name differs, the compile error in Step 4 will pinpoint it — adjust per the API note at the top of this plan.)

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Markdown

/// Converts a swift-markdown `Document` (CommonMark + GFM) into our block tree.
/// Lemmy's inline extensions are applied to `Text` runs via `InlineLexer`; its
/// block-level extensions (spoilers, footnotes) are handled before this stage.
enum BlockParser {
    static func document(_ source: String) -> [MarkdownBlock] {
        let document = Document(parsing: source)
        return document.children.compactMap { convertBlock($0) }
    }

    // MARK: Blocks

    static func convertBlock(_ markup: Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            if let media = mediaBlock(from: paragraph) { return media }
            return .paragraph(inlineChildren(paragraph))
        case let heading as Heading:
            return .heading(level: heading.level, inlineChildren(heading))
        case is ThematicBreak:
            return .thematicBreak
        case let code as CodeBlock:
            return .codeBlock(language: normalizedLanguage(code.language), code: trimTrailingNewline(code.code))
        case let quote as BlockQuote:
            return .blockQuote(quote.children.compactMap { convertBlock($0) })
        case let list as UnorderedList:
            return .unorderedList(list.listItems.map { listItem($0) })
        case let list as OrderedList:
            return .orderedList(start: Int(list.startIndex), list.listItems.map { listItem($0) })
        case let table as Markdown.Table:
            return convertTable(table)
        default:
            // HTMLBlock (html:false upstream) and anything unknown are dropped.
            return nil
        }
    }

    private static func listItem(_ item: ListItem) -> MarkdownListItem {
        MarkdownListItem(blocks: item.children.compactMap { convertBlock($0) })
    }

    private static func mediaBlock(from paragraph: Paragraph) -> MarkdownBlock? {
        // A paragraph whose only meaningful inline child is an image becomes a
        // media block (image / audio / video).
        let images = paragraph.children.compactMap { $0 as? Markdown.Image }
        guard images.count == 1, paragraph.childCount == 1, let image = images.first,
              let source = image.source, let url = URL(string: source) else { return nil }
        switch MediaDetector.kind(of: url) {
        case .image: return .image(MarkdownImage(url: url, altText: image.plainText))
        case .audio: return .audio(url: url)
        case .video: return .video(url: url)
        }
    }

    private static func convertTable(_ table: Markdown.Table) -> MarkdownBlock {
        let alignments = table.columnAlignments.map { mapAlignment($0) }
        let head = cells(in: table.head).map { inlineChildren($0) }
        let rows = table.body.children
            .compactMap { $0 as? Markdown.Table.Row }
            .map { row in cells(in: row).map { inlineChildren($0) } }
        return .table(MarkdownTable(alignments: alignments, head: head, rows: rows))
    }

    private static func cells(in container: Markup) -> [Markdown.Table.Cell] {
        container.children.compactMap { $0 as? Markdown.Table.Cell }
    }

    private static func mapAlignment(_ alignment: Markdown.Table.ColumnAlignment?) -> MarkdownTable.Alignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return .left
        }
    }

    private static func normalizedLanguage(_ language: String?) -> String? {
        guard let language, !language.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return language
    }

    private static func trimTrailingNewline(_ code: String) -> String {
        var result = code
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }

    // MARK: Inlines

    static func inlineChildren(_ markup: Markup) -> [MarkdownInline] {
        markup.children.flatMap { convertInline($0) }
    }

    private static func convertInline(_ markup: Markup) -> [MarkdownInline] {
        switch markup {
        case let text as Markdown.Text:
            return InlineLexer.parse(text.string)
        case let strong as Strong:
            return [.strong(inlineChildren(strong))]
        case let emphasis as Emphasis:
            return [.emphasis(inlineChildren(emphasis))]
        case let strike as Strikethrough:
            return [.strikethrough(inlineChildren(strike))]
        case let code as InlineCode:
            return [.code(code.code)]
        case let link as Markdown.Link:
            if let destination = link.destination, let url = URL(string: destination) {
                return [.link(text: inlineChildren(link), url: url)]
            }
            return inlineChildren(link)
        case let image as Markdown.Image:
            // An inline image inside text (rare) → a link to the image.
            if let source = image.source, let url = URL(string: source) {
                return [.link(text: [.text(image.plainText)], url: url)]
            }
            return []
        case is SoftBreak, is LineBreak:
            return [.text(" ")]
        case let html as InlineHTML:
            return [.text(html.rawHTML)]  // html:false upstream → show literally
        default:
            let text = markup.plainText
            return text.isEmpty ? [] : [.text(text)]
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/BlockParserTests test 2>&1 | tail -40
```

Expected: `** TEST SUCCEEDED **`. If a swift-markdown name mismatches (e.g. `Table.Row`/`Table.Cell` access), the compiler names it — adjust the cast/accessor and re-run.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): swift-markdown block walk

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Footnote extraction

**Files:**
- Create: `SpudMarkdownKit/Parsing/FootnoteExtractor.swift`
- Create: `SpudMarkdownKitTests/FootnoteExtractorTests.swift`

Lifts `[^label]: text` definition lines out of the raw source (swift-markdown would otherwise render them as a stray paragraph). Returns the cleaned source plus the raw definitions; `MarkdownParser` (Task 9) turns them into a `footnotes` block via `InlineLexer`. The `[^label]` *references* stay in the prose for the lexer.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/FootnoteExtractorTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class FootnoteExtractorTests: XCTestCase {
    func test_extractsDefinitionsAndLeavesReferences() {
        let source = "Thanks.[^1]\n\n[^1]: Re-download over wired."
        let result = FootnoteExtractor.extract(source)
        XCTAssertEqual(result.source.trimmingCharacters(in: .whitespacesAndNewlines), "Thanks.[^1]")
        XCTAssertEqual(result.definitions.count, 1)
        XCTAssertEqual(result.definitions.first?.label, "1")
        XCTAssertEqual(result.definitions.first?.text, "Re-download over wired.")
    }

    func test_noFootnotes() {
        let result = FootnoteExtractor.extract("Just text.")
        XCTAssertEqual(result.source, "Just text.")
        XCTAssertTrue(result.definitions.isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/FootnoteExtractorTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'FootnoteExtractor'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/FootnoteExtractor.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lifts `[^label]: text` footnote definitions out of the source. References
/// (`[^label]`) are left in place for the inline lexer. Single-line definitions
/// only (Phase 1).
enum FootnoteExtractor {
    struct Definition: Equatable { var label: String; var text: String }
    struct Result { var source: String; var definitions: [Definition] }

    static func extract(_ source: String) -> Result {
        var definitions: [Definition] = []
        var kept: [Substring] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = line.wholeMatch(of: /\[\^([\w-]+)\]:\s?(.*)/) {
                definitions.append(Definition(label: String(match.1), text: String(match.2)))
            } else {
                kept.append(line)
            }
        }
        return Result(source: kept.joined(separator: "\n"), definitions: definitions)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/FootnoteExtractorTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): footnote definition extraction

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Spoiler preprocessing

**Files:**
- Create: `SpudMarkdownKit/Parsing/SpoilerPreprocessor.swift`
- Create: `SpudMarkdownKitTests/SpoilerPreprocessorTests.swift`

Lemmy spoilers use a markdown-it container swift-markdown can't see:

```
::: spoiler Title text
inner markdown
:::
```

The preprocessor replaces each top-level spoiler with a unique sentinel line (a token swift-markdown parses as a one-word paragraph) and returns a map of sentinel-id → (title, inner source). `MarkdownParser` (Task 9) swaps the sentinel paragraphs back for real `spoiler` blocks, recursively parsing the inner source (so nested spoilers work). Sentinel uses Private-Use-Area scalars so it never collides with real content.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/SpoilerPreprocessorTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class SpoilerPreprocessorTests: XCTestCase {
    func test_extractsSpoilerWithTitleAndInner() {
        let source = "Intro\n\n::: spoiler Benchmarks\nLocked 60 fps.\n:::\n\nOutro"
        let result = SpoilerPreprocessor.preprocess(source)

        // One spoiler captured.
        XCTAssertEqual(result.spoilers.count, 1)
        let spoiler = result.spoilers.values.first
        XCTAssertEqual(spoiler?.title, "Benchmarks")
        XCTAssertEqual(spoiler?.inner.trimmingCharacters(in: .whitespacesAndNewlines), "Locked 60 fps.")

        // The fence lines are gone, replaced by a sentinel; prose is preserved.
        XCTAssertFalse(result.source.contains("::: spoiler"))
        XCTAssertTrue(result.source.contains("Intro"))
        XCTAssertTrue(result.source.contains("Outro"))
        // The sentinel id appears as a standalone token in the cleaned source.
        let id = result.spoilers.keys.first!
        XCTAssertTrue(result.source.contains(SpoilerPreprocessor.sentinel(for: id)))
    }

    func test_emptyTitle() {
        let result = SpoilerPreprocessor.preprocess("::: spoiler\nhidden\n:::")
        XCTAssertEqual(result.spoilers.values.first?.title, "")
    }

    func test_noSpoiler() {
        let result = SpoilerPreprocessor.preprocess("plain text")
        XCTAssertEqual(result.source, "plain text")
        XCTAssertTrue(result.spoilers.isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/SpoilerPreprocessorTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'SpoilerPreprocessor'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/SpoilerPreprocessor.swift`. Depth counting on `:::` fences supports nesting (the outer `:::` closes only at depth 0).

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Lifts `::: spoiler <title>` … `:::` containers out of the source, replacing
/// each with a sentinel paragraph that swift-markdown parses as plain text.
/// `MarkdownParser` swaps the sentinel back for a real spoiler block, recursively
/// parsing the captured inner source.
enum SpoilerPreprocessor {
    struct Spoiler { var title: String; var inner: String }
    struct Result { var source: String; var spoilers: [String: Spoiler] }

    /// The standalone token written into the cleaned source for spoiler `id`.
    /// Wrapped in Private-Use-Area scalars so it can't collide with content.
    static func sentinel(for id: String) -> String { "\u{E000}spoiler:\(id)\u{E001}" }

    static func preprocess(_ source: String) -> Result {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var spoilers: [String: Spoiler] = [:]
        var nextID = 0

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let title = openingTitle(line) {
                // Collect until the matching closing fence (depth-aware).
                var inner: [String] = []
                var depth = 1
                index += 1
                while index < lines.count {
                    let current = lines[index]
                    if openingTitle(current) != nil {
                        depth += 1
                        inner.append(current)
                    } else if isClosingFence(current) {
                        depth -= 1
                        if depth == 0 { break }
                        inner.append(current)
                    } else {
                        inner.append(current)
                    }
                    index += 1
                }
                let id = String(nextID)
                nextID += 1
                spoilers[id] = Spoiler(title: title, inner: inner.joined(separator: "\n"))
                // Blank lines around the sentinel keep it a standalone paragraph.
                output.append("")
                output.append(sentinel(for: id))
                output.append("")
            } else {
                output.append(line)
            }
            index += 1
        }

        return Result(source: output.joined(separator: "\n"), spoilers: spoilers)
    }

    /// The title if `line` opens a spoiler (`::: spoiler [title]`), else nil.
    private static func openingTitle(_ line: String) -> String? {
        guard let match = line.wholeMatch(of: /\s*:::\s*spoiler\s?(.*)/) else { return nil }
        return String(match.1).trimmingCharacters(in: .whitespaces)
    }

    private static func isClosingFence(_ line: String) -> Bool {
        line.wholeMatch(of: /\s*:::\s*/) != nil
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/SpoilerPreprocessorTests test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): spoiler container preprocessing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Top-level parser orchestrator

**Files:**
- Create: `SpudMarkdownKit/Parsing/MarkdownParser.swift`
- Create: `SpudMarkdownKitTests/MarkdownParserTests.swift`

The public entry point stitches the pipeline: extract footnotes → preprocess spoilers → block-parse → re-inject spoiler blocks → append the footnotes block.

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/MarkdownParserTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MarkdownParserTests: XCTestCase {
    func test_spoilerBecomesSpoilerBlockWithParsedChildren() {
        let blocks = MarkdownParser.parse("::: spoiler Numbers\nLocked **60** fps.\n:::")
        XCTAssertEqual(blocks, [
            .spoiler(title: [.text("Numbers")], children: [
                .paragraph([.text("Locked "), .strong([.text("60")]), .text(" fps.")]),
            ]),
        ])
    }

    func test_footnotesAppendedAsBlock() {
        let blocks = MarkdownParser.parse("Thanks.[^1]\n\n[^1]: Over wired.")
        XCTAssertEqual(blocks, [
            .paragraph([.text("Thanks."), .footnoteReference("1")]),
            .footnotes([MarkdownFootnote(label: "1", content: [.text("Over wired.")])]),
        ])
    }

    func test_emptySourceProducesNoBlocks() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
    }

    func test_plainParagraph() {
        XCTAssertEqual(MarkdownParser.parse("Hello world"), [.paragraph([.text("Hello world")])])
    }
}
```

- [ ] **Step 2: Run it to verify it fails.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MarkdownParserTests test 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'MarkdownParser'`.

- [ ] **Step 3: Implement** `SpudMarkdownKit/Parsing/MarkdownParser.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The public markdown → block-tree entry point for Spud bodies. Pure and
/// synchronous, so it can run off the main thread and be cached by the host.
public enum MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        guard !source.isEmpty else { return [] }

        let footnoteResult = FootnoteExtractor.extract(source)
        let spoilerResult = SpoilerPreprocessor.preprocess(footnoteResult.source)

        var blocks = BlockParser.document(spoilerResult.source)
        blocks = reinjectSpoilers(blocks, spoilers: spoilerResult.spoilers)

        if !footnoteResult.definitions.isEmpty {
            let footnotes = footnoteResult.definitions.map {
                MarkdownFootnote(label: $0.label, content: InlineLexer.parse($0.text))
            }
            blocks.append(.footnotes(footnotes))
        }

        return blocks
    }

    /// Replaces each sentinel paragraph with a real spoiler block whose children
    /// are the recursively-parsed inner source.
    private static func reinjectSpoilers(
        _ blocks: [MarkdownBlock],
        spoilers: [String: SpoilerPreprocessor.Spoiler]
    ) -> [MarkdownBlock] {
        blocks.map { block in
            switch block {
            case let .paragraph(inlines):
                if let id = spoilerID(in: inlines), let spoiler = spoilers[id] {
                    return .spoiler(
                        title: InlineLexer.parse(spoiler.title),
                        children: parse(spoiler.inner)
                    )
                }
                return block
            case let .blockQuote(children):
                return .blockQuote(reinjectSpoilers(children, spoilers: spoilers))
            default:
                return block
            }
        }
    }

    /// If `inlines` is exactly a spoiler sentinel (`…spoiler:<id>…`), the id.
    private static func spoilerID(in inlines: [MarkdownInline]) -> String? {
        guard inlines.count == 1, case let .text(text) = inlines[0] else { return nil }
        guard let match = text.wholeMatch(of: /\u{E000}spoiler:([0-9]+)\u{E001}/) else { return nil }
        return String(match.1)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MarkdownParserTests test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

Note: `spoilerID` matches the sentinel after `SmartTypography`/`InlineLexer` have passed the text through — the PUA scalars and `spoiler:<id>` are untouched by both, so the sentinel survives intact.

- [ ] **Step 5: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "feat(markdown): top-level parser orchestrator

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Kitchen-sink golden integration test

**Files:**
- Create: `SpudMarkdownKitTests/Fixtures/KitchenSink.swift`
- Modify: `SpudMarkdownKitTests/MarkdownParserTests.swift` (add the golden test)

The kitchen-sink markdown (ported from `md-content.jsx`) exercises every element in one parse. Rather than assert the entire tree, assert the *structural shape* (the sequence of block kinds) plus a few spot-checks — robust to inline detail while proving the whole pipeline. This is also where the `~sub~` vs swift-markdown-strikethrough interaction is verified on real markdown.

- [ ] **Step 1: Create the fixture** at `SpudMarkdownKitTests/Fixtures/KitchenSink.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A realistic Lemmy post exercising every supported element, ported from the
/// design reference (`md-content.jsx`). Used as the parser's golden fixture.
enum KitchenSink {
    static let post = """
    Valve **finally** shipped a flashable SteamOS image, so I put it on a Legion Go. Short version: it's *very* good, with ~~three~~ two real rough edges. Ping me (@glidergun@lemmy.world) or drop into !linux_gaming@lemmy.world. :penguin:

    Tested build: `steamos-3.7.8`. Recovery image: https://store.steampowered.com/steamos/download

    # H1 — Section title
    ## H2 — Subsection

    You'll want, in rough order:

    - A USB-C drive, **8 GB or larger**.
    - The official `rufus` flasher.
        - Save files sync via cloud.
        - Screenshot your BIOS first.

    Steps:

    1. Disable Secure Boot.
    2. Flash the recovery image.
    3. Choose **Reimage** or **Repair**.

    | Subsystem | Claimed | Measured | OK? |
    |:---|---:|---:|:---:|
    | Suspend/resume | < 2s | 1.4s | yes |
    | Fingerprint | Yes | No driver | no |

    Drop this in your config:

    ```bash
    export ALSA_CARD=acp
    pactl set-sink-volume @DEFAULT_SINK@ 140%
    ```

    > Third-party support is **best-effort**.
    >
    > > The fingerprint reader may never work.

    ![SteamOS desktop on the Legion Go](https://lemmy.world/pictrs/image/desktop.png)

    ![suspend clip](https://lemmy.world/pictrs/video/suspend.mp4)

    ::: spoiler Cyberpunk 2077 — ultra
    :::

    ::: spoiler Elden Ring — settled numbers
    Locked **60 fps** at 800p medium.
    :::

    ---

    Formatting test: H~2~O, E=mc^2^, "smart quotes," en--dashes, em---dashes, ellipsis... Corrections welcome.[^1]

    [^1]: If the checksum doesn't match, **stop** — re-download over a wired connection.
    """
}
```

- [ ] **Step 2: Write the failing golden test.** Append to `SpudMarkdownKitTests/MarkdownParserTests.swift` (inside the class):

```swift
    func test_kitchenSinkStructuralShape() {
        let blocks = MarkdownParser.parse(KitchenSink.post)

        // Helper: the case name of each top-level block.
        func kind(_ block: MarkdownBlock) -> String {
            switch block {
            case .paragraph: return "paragraph"
            case .heading: return "heading"
            case .unorderedList: return "unorderedList"
            case .orderedList: return "orderedList"
            case .blockQuote: return "blockQuote"
            case .codeBlock: return "codeBlock"
            case .table: return "table"
            case .image: return "image"
            case .audio: return "audio"
            case .video: return "video"
            case .spoiler: return "spoiler"
            case .footnotes: return "footnotes"
            case .thematicBreak: return "thematicBreak"
            }
        }
        let kinds = blocks.map(kind)

        // Every block kind the post exercises is present.
        for expected in ["paragraph", "heading", "unorderedList", "orderedList",
                         "table", "codeBlock", "blockQuote", "image", "video",
                         "spoiler", "thematicBreak", "footnotes"] {
            XCTAssertTrue(kinds.contains(expected), "missing \(expected) in \(kinds)")
        }

        // The footnotes block is last and has one entry.
        guard case let .footnotes(notes) = blocks.last else {
            return XCTFail("last block should be footnotes, got \(kinds)")
        }
        XCTAssertEqual(notes.map(\.label), ["1"])

        // The video link became a video block (not an image).
        XCTAssertTrue(blocks.contains { if case .video = $0 { return true }; return false })

        // The body-less spoiler (Cyberpunk, empty children) is preserved.
        let emptyBodySpoiler = blocks.contains {
            if case let .spoiler(_, children) = $0 { return children.isEmpty }
            return false
        }
        XCTAssertTrue(emptyBodySpoiler, "body-less spoiler should be present")
    }

    func test_kitchenSinkSubscriptSurvives() {
        // Guards the swift-markdown single-tilde-strikethrough interaction: the
        // formatting-test paragraph must still contain a subscript for H~2~O.
        let blocks = MarkdownParser.parse(KitchenSink.post)
        let hasSubscript = blocks.contains { block in
            if case let .paragraph(inlines) = block { return containsSubscript(inlines) }
            return false
        }
        XCTAssertTrue(hasSubscript, "H~2~O subscript was lost (swift-markdown likely ate single tildes)")
    }

    private func containsSubscript(_ inlines: [MarkdownInline]) -> Bool {
        for inline in inlines {
            switch inline {
            case .subscript: return true
            case let .strong(children), let .emphasis(children), let .highlight(children),
                 let .superscript(children), let .strikethrough(children):
                if containsSubscript(children) { return true }
            default: break
            }
        }
        return false
    }
```

- [ ] **Step 3: Run the golden tests.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MarkdownParserTests/test_kitchenSinkStructuralShape \
  -only-testing:SpudMarkdownKitTests/MarkdownParserTests/test_kitchenSinkSubscriptSurvives test 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4 (contingency — only if `test_kitchenSinkSubscriptSurvives` FAILS):** swift-markdown consumed the single tilde as strikethrough. Add a sentinel pre-pass so sub/superscript survive parsing. Create `SpudMarkdownKit/Parsing/SubSupPreprocessor.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Protects `^x^` superscript and `~x~` subscript from swift-markdown (whose
/// strikethrough extension can consume single tildes) by replacing them with
/// PUA-wrapped sentinels before parsing. `InlineLexer` restores them.
enum SubSupPreprocessor {
    static func protectText(_ source: String) -> String {
        var s = source
        s = s.replacing(/\^([^\^\s]+)\^/) { "\u{E010}sup:\($0.1)\u{E011}" }
        s = s.replacing(/(?<![~])~([^~\s]+)~(?![~])/) { "\u{E010}sub:\($0.1)\u{E011}" }
        return s
    }
}
```

Then: (a) in `MarkdownParser.parse`, call `SubSupPreprocessor.protectText` on `spoilerResult.source` before `BlockParser.document`; (b) in `InlineLexer.match`, add two rules **before** the existing sup/sub rules that restore the sentinels:

```swift
        if let m = rest.prefixMatch(of: /\u{E010}sup:([^\u{E011}]+)\u{E011}/) {
            return (.superscript(parse(String(m.1))), count(m.range.upperBound))
        }
        if let m = rest.prefixMatch(of: /\u{E010}sub:([^\u{E011}]+)\u{E011}/) {
            return (.subscript(parse(String(m.1))), count(m.range.upperBound))
        }
```

Re-run Step 3; both golden tests pass. (The direct `InlineLexerTests` still pass — they exercise the raw `^x^`/`~x~` rules, which remain.)

- [ ] **Step 5: Run the FULL test target to confirm nothing regressed.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`, all `SpudMarkdownKitTests` green.

- [ ] **Step 6: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "test(markdown): kitchen-sink golden parser test

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: MarkdownLab — live parse-tree dump

**Files:**
- Modify: `MarkdownLab/MarkdownLabApp.swift`
- Create: `MarkdownLab/BlockTreeDump.swift`

The Lab becomes working software: paste/edit markdown on the left, see the parsed block tree on the right. Phase 2 swaps the dump for the real rendered body. No test (it's a dev harness); verified by build + boot.

- [ ] **Step 1: Implement the dump formatter** at `MarkdownLab/BlockTreeDump.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudMarkdownKit

/// Renders a parsed block tree as indented debug lines for the Lab.
enum BlockTreeDump {
    static func lines(_ blocks: [MarkdownBlock], indent: Int = 0) -> [String] {
        let pad = String(repeating: "  ", count: indent)
        var out: [String] = []
        for block in blocks {
            switch block {
            case let .paragraph(inlines):
                out.append("\(pad)paragraph: \(inlineSummary(inlines))")
            case let .heading(level, inlines):
                out.append("\(pad)h\(level): \(inlineSummary(inlines))")
            case let .unorderedList(items):
                out.append("\(pad)ul (\(items.count))")
                for item in items { out += lines(item.blocks, indent: indent + 1) }
            case let .orderedList(start, items):
                out.append("\(pad)ol start=\(start) (\(items.count))")
                for item in items { out += lines(item.blocks, indent: indent + 1) }
            case let .blockQuote(children):
                out.append("\(pad)quote")
                out += lines(children, indent: indent + 1)
            case let .codeBlock(language, _):
                out.append("\(pad)code[\(language ?? "text")]")
            case let .table(table):
                out.append("\(pad)table \(table.head.count)x\(table.rows.count)")
            case let .image(image):
                out.append("\(pad)image \(image.url.lastPathComponent)")
            case let .audio(url):
                out.append("\(pad)audio \(url.lastPathComponent)")
            case let .video(url):
                out.append("\(pad)video \(url.lastPathComponent)")
            case let .spoiler(title, children):
                out.append("\(pad)spoiler \"\(inlineSummary(title))\"")
                out += lines(children, indent: indent + 1)
            case let .footnotes(notes):
                out.append("\(pad)footnotes (\(notes.count))")
            case .thematicBreak:
                out.append("\(pad)hr")
            }
        }
        return out
    }

    private static func inlineSummary(_ inlines: [MarkdownInline]) -> String {
        inlines.map { inline in
            switch inline {
            case let .text(s): return s
            case let .strong(c): return "**\(inlineSummary(c))**"
            case let .emphasis(c): return "*\(inlineSummary(c))*"
            case let .strikethrough(c): return "~~\(inlineSummary(c))~~"
            case let .highlight(c): return "==\(inlineSummary(c))=="
            case let .code(s): return "`\(s)`"
            case let .superscript(c): return "^\(inlineSummary(c))^"
            case let .subscript(c): return "~\(inlineSummary(c))~"
            case let .link(t, url): return "[\(inlineSummary(t))](\(url.absoluteString))"
            case let .mention(name, instance): return "@\(name)@\(instance)"
            case let .community(name, instance): return "!\(name)@\(instance)"
            case let .emoji(s): return s
            case let .customEmoji(shortcode): return "::\(shortcode)::"
            case let .footnoteReference(label): return "[^\(label)]"
            }
        }.joined()
    }
}
```

- [ ] **Step 2: Replace the Lab app** `MarkdownLab/MarkdownLabApp.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import SwiftUI

@main
struct MarkdownLabApp: App {
    var body: some Scene {
        WindowGroup { LabView() }
    }
}

private let defaultSample = """
Valve **finally** shipped SteamOS. Ping @glidergun@lemmy.world or !linux_gaming@lemmy.world. :penguin:

# Heading
- one
- two

::: spoiler Numbers
Locked **60 fps**.
:::

Thanks.[^1]

[^1]: Over a wired connection.
"""

struct LabView: View {
    @State private var source = defaultSample

    private var dump: String {
        BlockTreeDump.lines(MarkdownParser.parse(source)).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxHeight: 240)
                    .border(.separator)
                Divider()
                ScrollView {
                    Text(dump)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("MarkdownLab")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

- [ ] **Step 3: Regenerate and build + boot the Lab.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. Then boot it to eyeball the dump (optional, requires a booted sim):

```bash
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /tmp/mdlab-dd build 2>&1 | tail -5
xcrun simctl install booted "$(find /tmp/mdlab-dd -name MarkdownLab.app -type d | head -1)"
xcrun simctl launch booted info.ddenis.MarkdownLab
```

Expected: the Lab launches showing the editor over the indented block-tree dump (paragraph / h1 / ul / spoiler / footnotes).

- [ ] **Step 4: Commit.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
mint run swiftformat MarkdownLab
git add MarkdownLab
git commit -m "feat(markdown): MarkdownLab live parse-tree dump

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Run the full `SpudMarkdownKit` test target.**

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` — SmartTypography, InlineLexer, MediaDetector, BlockParser, FootnoteExtractor, SpoilerPreprocessor, Model, MarkdownParser (incl. kitchen-sink) all green.

- [ ] **Confirm the main Spud app still builds** (the new targets are additive, but verify `make project` didn't disturb it).

```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro" 2>&1 | tail -15
```

Expected: build succeeds (warnings unchanged from baseline).

---

## Done criteria for Phase 1

- `SpudMarkdownKit` framework builds; `MarkdownParser.parse` converts markdown → `[MarkdownBlock]`.
- Every supported element parses (verified by the kitchen-sink golden test): inline formatting, headings H1–H6, lists (nested), tables (aligned), code blocks, blockquotes (nested), images, audio/video media links, spoilers (incl. empty title), footnotes, thematic breaks, and the inline extensions (mark, sub/sup, mentions, communities, emoji, footnote refs, smart typography, autolinks).
- `MarkdownLab` runs and shows the live parse tree.
- Full `SpudMarkdownKitTests` target green; main Spud app still builds.

## Next (separate plans)

- **Phase 2** — `ProseBlockView` (TextKit 2) + inline → `NSAttributedString` rendering; `MarkdownContext` sizing (post/comment × Dynamic Type × density); SpudUIKit token wiring; Lab renders the text-only kitchen sink.
- **Phase 3** — `CodeBlockView`, `TableBlockView`, `SpoilerBlockView`, `FootnotesBlockView`.
- **Phase 4** — `ImageBlockView` (states/zoom/caption), `AudioBlockView`, `VideoBlockView` (placeholder media in the Lab) + `MarkdownBodyDelegate`.
- **Phase 5** — snapshot suite (kitchen-sink + edge cases) reusing Spud's snapshot infra.
- **Phase 6** — integration: replace `BodyTextView`/`LinkLabel` at post + comment body call sites; wire real media/navigation/haptics.
</content>
