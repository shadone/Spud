# Markdown Renderer — Phase 3 (Structural / Interactive Blocks) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the structural/interactive blocks — fenced code (copy + horizontal scroll), tables (aligned, scrollable), spoilers (disclosure of nested blocks), footnotes (section + return links) — and true nested lists, replacing the Phase-2 placeholders, shown in `MarkdownLab` and snapshot-locked.

**Architecture:** Extract a shared `@MainActor MarkdownBlockRenderer` from `MarkdownBodyView` (block→view dispatch + the prose/heading attributed-string helpers + an `onTapLink`/`onContentSizeChange` seam) so spoilers and lists can render nested child blocks. Each structural block becomes a dedicated `UIView` wired into the renderer's switch (replacing its `PlaceholderBlockView`). Deterministic pieces stay unit-tested; the views are verified by snapshot + Lab eyeball.

**Tech Stack:** Swift 6, UIKit (TextKit 2, `UIScrollView`, Auto Layout self-sizing), `SpudUIKit.Haptics`, swift-snapshot-testing, XcodeGen.

---

## Scope

Phase 3 = the four structural block VIEWS + true nested lists, built on a shared renderer. **Out of scope:** rounded mention/community chips (deferred — rounded pills behind wrapping text in a UITextView is high-effort/low-payoff; the rectangular chip from Phase 2 stays); media block views (`image`/`audio`/`video` — Phase 4); full smooth-scroll footnote jump (Phase 3 renders the section + a return affordance and fires a best-effort scroll; precise ref↔def scrolling is refined at integration). Builds on Phases 1–2 (`docs/superpowers/specs/2026-06-15-markdown-renderer-design.md`, the two prior plans).

## Reference (from `md-render.jsx`)

- **Code block:** rounded container (radius 12 post / 9 comment), 0.5px border, header row (lang label lowercased in `secondaryLabel` + a teal "Copy" affordance) over a horizontal-scrolling monospaced `pre` (no wrap), code at `context.inlineCodeFont`-ish size.
- **Table:** horizontal-scroll wrapper, radius 10/8, `separator` border; header row tinted (`tertiarySystemFill`), 1px header bottom rule, hairline cell separators; per-column alignment; comment context forces a `minWidth` (≈360) so it scrolls under the rail.
- **Spoiler:** `secondarySystemFill`-ish container (radius 10/8), a disclosure row (chevron `chevron.right`/`chevron.down` in teal + bold-ish title; empty title → muted italic "Spoiler"); collapsed hides body, expanded reveals nested blocks under a hairline.
- **Footnotes:** top divider + a "Footnotes" H6-style header (uppercase secondary), an ordered list, each item ending with a teal ↩ return affordance.
- **Nested lists:** ul disc↔circle by depth, ol decimal; item gap 5/3 pt; indent 22/17 pt per level; mixed nesting + multi-block items.

## File Structure

```
SpudMarkdownKit/Rendering/
  MarkdownBlockRenderer.swift   ← NEW: extracted block→view dispatch (+ prose/heading helpers, onTapLink/onContentSizeChange)
  MarkdownBodyView.swift        ← MODIFIED: thin wrapper around the renderer
  CodeBlockView.swift           ← NEW
  TableBlockView.swift          ← NEW
  SpoilerBlockView.swift        ← NEW
  FootnotesBlockView.swift      ← NEW
  ListBlockView.swift           ← NEW (true nested lists; replaces the flat listAttributed)
SpudMarkdownKitTests/
  MarkdownBlockRendererTests.swift   ← dispatch returns the right view type per block
SpudMarkdownKitSnapshotTests/
  MarkdownStructuralSnapshotTests.swift ← code/table/spoiler(collapsed+expanded)/footnotes/nested-list, post/comment x light/dark
MarkdownLab/
  MarkdownLabApp.swift          ← MODIFIED: richer default sample (code/table/spoiler/footnotes/nested list)
```

## Conventions (every task)

BSD-2-Clause header on every new file:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
```

**MUST `make project` before every build/test** (XcodeGen picks up new files only on regeneration). Canonical unit-test command:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/<CLASS> test 2>&1 | tail -30
```
(iPhone 17 or 17 Pro — whichever is available.) Format before commit: `mint run swiftformat <dirs>`. `git status -uall`; stage explicit paths. All view types `@MainActor`.

---

## Task 1: Extract MarkdownBlockRenderer (refactor)

**Files:** Create `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift`; Modify `SpudMarkdownKit/Rendering/MarkdownBodyView.swift`; Create `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift`

Move the block→view dispatch + prose/heading/list helpers out of `MarkdownBodyView` into a reusable renderer. Behavior-preserving (the existing prose snapshots must still pass). The renderer gains an `onContentSizeChange` seam (used by spoilers later).

- [ ] **Step 1: Write the failing test** at `SpudMarkdownKitTests/MarkdownBlockRendererTests.swift`:
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
final class MarkdownBlockRendererTests: XCTestCase {
    private func renderer() -> MarkdownBlockRenderer {
        MarkdownBlockRenderer(context: MarkdownContext(kind: .post))
    }

    func test_paragraphRendersProseBlockView() {
        let view = renderer().view(for: .paragraph([.text("hi")]))
        XCTAssertTrue(view is ProseBlockView)
    }

    func test_thematicBreakRendersThematicBreakView() {
        XCTAssertTrue(renderer().view(for: .thematicBreak) is ThematicBreakView)
    }

    func test_blockQuoteRendersQuoteBlockView() {
        let view = renderer().view(for: .blockQuote([.paragraph([.text("q")])]))
        XCTAssertTrue(view is QuoteBlockView)
    }

    func test_viewsForBlocksReturnsOnePerBlock() {
        let views = renderer().views(for: [.paragraph([.text("a")]), .thematicBreak])
        XCTAssertEqual(views.count, 2)
    }
}
```

- [ ] **Step 2: Run to verify it fails** (`-only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests`). Expected: `cannot find 'MarkdownBlockRenderer'`.

- [ ] **Step 3: Create** `SpudMarkdownKit/Rendering/MarkdownBlockRenderer.swift` — move the dispatch + helpers here. (Lists still use the flat `listAttributed` for now; Task 4 replaces it.)
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Builds a `UIView` for each `MarkdownBlock`, in a given context. Shared by
/// `MarkdownBodyView` and by nesting block views (spoilers, lists) so child
/// blocks render through the same path. `onTapLink` forwards body link taps;
/// `onContentSizeChange` lets an interactive child (a spoiler) ask the host to
/// re-measure after it grows/shrinks.
@MainActor
final class MarkdownBlockRenderer {
    let context: MarkdownContext
    var onTapLink: ((URL) -> Void)?
    var onContentSizeChange: (() -> Void)?

    init(context: MarkdownContext) { self.context = context }

    func views(for blocks: [MarkdownBlock]) -> [UIView] { blocks.map { view(for: $0) } }

    func view(for block: MarkdownBlock) -> UIView {
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

    func prose(_ attributed: NSAttributedString) -> ProseBlockView {
        let view = ProseBlockView()
        let m = NSMutableAttributedString(attributedString: attributed)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = context.lineHeightMultiple
        m.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: m.length))
        view.attributedText = m
        view.onTapLink = { [weak self] url in self?.onTapLink?(url) }
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
                attributes: [.font: font, .foregroundColor: color]
            ))
        }
        return m
    }

    private func listAttributed(_ items: [MarkdownListItem], ordered: Bool, start: Int) -> NSAttributedString {
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

- [ ] **Step 4: Rewrite** `SpudMarkdownKit/Rendering/MarkdownBodyView.swift` to delegate to the renderer:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Renders a parsed markdown body (`[MarkdownBlock]`) as a self-sizing vertical
/// stack of block views, in a given context, via `MarkdownBlockRenderer`.
@MainActor
public final class MarkdownBodyView: UIView {
    public weak var delegate: MarkdownBodyDelegate?
    private let stack = UIStackView()
    private let renderer: MarkdownBlockRenderer

    public init(context: MarkdownContext) {
        renderer = MarkdownBlockRenderer(context: context)
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
        renderer.onTapLink = { [weak self] url in self?.delegate?.markdownBody(didTapLink: url) }
        renderer.onContentSizeChange = { [weak self] in
            self?.setNeedsLayout()
            self?.invalidateIntrinsicContentSize()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Replaces the rendered content with `blocks`.
    public func setBlocks(_ blocks: [MarkdownBlock]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for view in renderer.views(for: blocks) { stack.addArrangedSubview(view) }
    }
}
```

- [ ] **Step 5: Run the renderer tests + the existing prose snapshots** to confirm the refactor preserved behavior:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitTests/MarkdownBlockRendererTests \
  -only-testing:SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **` — the 4 renderer tests pass AND the 4 prose snapshots still match (refactor preserved output). If a prose snapshot now differs, the refactor changed rendering — fix until they match the committed references (do NOT re-record).

- [ ] **Step 6: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit SpudMarkdownKitTests
git add SpudMarkdownKit SpudMarkdownKitTests
git commit -m "refactor(markdown): extract MarkdownBlockRenderer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: CodeBlockView (copy + horizontal scroll)

**Files:** Create `SpudMarkdownKit/Rendering/CodeBlockView.swift`; Modify `MarkdownBlockRenderer.swift` (wire `.codeBlock`)

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/CodeBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit

/// A fenced code block: a rounded container with a header (language label + a
/// Copy affordance) over a horizontally-scrolling, non-wrapping monospaced body.
final class CodeBlockView: UIView {
    private let code: String

    init(language: String?, code: String, context: MarkdownContext) {
        self.code = code
        super.init(frame: .zero)

        backgroundColor = .secondarySystemFill
        layer.cornerRadius = context.kind == .post ? 12 : 9
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let lang = UILabel()
        lang.text = (language ?? "text").lowercased()
        lang.font = .monospacedSystemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        lang.textColor = .secondaryLabel
        lang.translatesAutoresizingMaskIntoConstraints = false

        let copy = UIButton(type: .system)
        copy.setTitle("Copy", for: .normal)
        copy.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copy.titleLabel?.font = .systemFont(ofSize: context.smallFont.pointSize * 0.92, weight: .semibold)
        copy.tintColor = context.accentColor
        copy.translatesAutoresizingMaskIntoConstraints = false
        copy.addAction(UIAction { [weak self] _ in self?.copyCode() }, for: .touchUpInside)

        header.addSubview(lang)
        header.addSubview(copy)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let body = UILabel()
        body.numberOfLines = 0
        body.text = code
        body.font = context.inlineCodeFont
        body.textColor = .label
        body.lineBreakMode = .byClipping
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(divider)
        addSubview(scroll)

        let hPad: CGFloat = context.kind == .post ? 12 : 10
        let vPad: CGFloat = context.kind == .post ? 7 : 5
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            lang.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: hPad),
            lang.topAnchor.constraint(equalTo: header.topAnchor, constant: vPad),
            lang.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -vPad),
            copy.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -hPad),
            copy.centerYAnchor.constraint(equalTo: lang.centerYAnchor),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: vPad + 3),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -(vPad + 3)),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: hPad),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: hPad),
            scroll.heightAnchor.constraint(equalTo: body.heightAnchor, constant: (vPad + 3) * 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    private func copyCode() {
        UIPasteboard.general.string = code
        Haptics.tap()
    }
}
```

- [ ] **Step 2: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .codeBlock: return PlaceholderBlockView(label: "code")` with:
```swift
        case let .codeBlock(language, code):
            return CodeBlockView(language: language, code: code, context: context)
```

- [ ] **Step 3: Build to verify** (canonical build, `... build`). Expected `** BUILD SUCCEEDED **`. (Visual correctness verified in Task 7's Lab + snapshots.)

- [ ] **Step 4: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): CodeBlockView (copy + horizontal scroll)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: TableBlockView

**Files:** Create `SpudMarkdownKit/Rendering/TableBlockView.swift`; Modify `MarkdownBlockRenderer.swift` (wire `.table`)

A horizontally-scrolling grid built from a `UIStackView` of column stacks (so per-column alignment + intrinsic column widths work), with a tinted header row and hairline separators.

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/TableBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A markdown table: a horizontally-scrolling grid with a tinted header row,
/// per-column alignment, and hairline separators. In a comment context the grid
/// is given a minimum width so it scrolls under the thread rail rather than
/// crushing columns.
final class TableBlockView: UIView {
    init(table: MarkdownTable, context: MarkdownContext) {
        super.init(frame: .zero)
        layer.cornerRadius = context.kind == .post ? 10 : 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // Build a vertical stack of rows; each row is a horizontal stack of cells.
        let grid = UIStackView()
        grid.axis = .vertical
        grid.translatesAutoresizingMaskIntoConstraints = false

        let allRows = [table.head] + table.rows
        for (r, cells) in allRows.enumerated() {
            let isHeader = r == 0
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            if isHeader { row.backgroundColor = .tertiarySystemFill }
            for (c, cell) in cells.enumerated() {
                let label = ProseBlockView()
                let attributed = NSMutableAttributedString(
                    attributedString: InlineAttributedStringBuilder.build(cell, context: context))
                let style = NSMutableParagraphStyle()
                style.alignment = nsAlignment(table.alignments[safe: c] ?? .left)
                attributed.addAttributes(
                    [.paragraphStyle: style,
                     .font: isHeader ? context.bodyFont.withTraits(.traitBold) : context.bodyFont,
                     .foregroundColor: isHeader ? context.labelColor : context.secondaryColor],
                    range: NSRange(location: 0, length: attributed.length))
                label.attributedText = attributed
                label.isSelectable = false
                let cellPad: CGFloat = context.kind == .post ? 10 : 7
                label.textContainerInset = UIEdgeInsets(top: cellPad * 0.7, left: cellPad, bottom: cellPad * 0.7, right: cellPad)
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
                row.addArrangedSubview(label)
                if c < cells.count - 1 { row.addArrangedSubview(hairline(vertical: true)) }
            }
            grid.addArrangedSubview(row)
            if r < allRows.count - 1 { grid.addArrangedSubview(hairline(vertical: false)) }
        }

        scroll.addSubview(grid)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            scroll.heightAnchor.constraint(equalTo: grid.heightAnchor),
        ])
        if context.kind == .comment {
            grid.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    private func hairline(vertical: Bool) -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        (vertical ? line.widthAnchor : line.heightAnchor).constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    private func nsAlignment(_ a: MarkdownTable.Alignment) -> NSTextAlignment {
        switch a { case .left: return .left; case .center: return .center; case .right: return .right }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
```

- [ ] **Step 2: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .table: return PlaceholderBlockView(label: "table")` with:
```swift
        case let .table(table):
            return TableBlockView(table: table, context: context)
```

- [ ] **Step 3: Build to verify** (canonical build). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): TableBlockView (aligned, horizontally scrollable)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: ListBlockView (true nested lists)

**Files:** Create `SpudMarkdownKit/Rendering/ListBlockView.swift`; Modify `MarkdownBlockRenderer.swift` (replace the flat `listAttributed` path with `ListBlockView`)

A view-based list: each item is a horizontal pair (marker label + an indented vertical stack of the item's child block views, rendered through the renderer). This handles arbitrary nesting and multi-block items. Bullet style alternates disc/circle by depth.

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/ListBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A list (ordered or unordered) rendered as a vertical stack of items; each
/// item is a marker beside an indented stack of its child block views, so
/// nested lists and multi-block items render correctly.
final class ListBlockView: UIView {
    init(items: [MarkdownListItem], ordered: Bool, start: Int, depth: Int,
         context: MarkdownContext, renderer: MarkdownBlockRenderer) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = context.kind == .post ? 5 : 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        for (i, item) in items.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 6

            let marker = UILabel()
            marker.text = ordered ? "\(start + i)." : (depth % 2 == 0 ? "\u{2022}" : "\u{25E6}")
            marker.font = context.bodyFont
            marker.textColor = context.secondaryColor
            marker.setContentHuggingPriority(.required, for: .horizontal)
            marker.widthAnchor.constraint(equalToConstant: context.listIndent).isActive = true
            marker.textAlignment = .left

            let content = UIStackView()
            content.axis = .vertical
            content.spacing = context.kind == .post ? 5 : 3
            for child in itemViews(item, depth: depth, context: context, renderer: renderer) {
                content.addArrangedSubview(child)
            }

            row.addArrangedSubview(marker)
            row.addArrangedSubview(content)
            stack.addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    /// Renders an item's blocks; a nested list recurses with `depth + 1`.
    private func itemViews(_ item: MarkdownListItem, depth: Int,
                           context: MarkdownContext, renderer: MarkdownBlockRenderer) -> [UIView] {
        item.blocks.map { block in
            switch block {
            case let .unorderedList(sub):
                return ListBlockView(items: sub, ordered: false, start: 1, depth: depth + 1,
                                     context: context, renderer: renderer)
            case let .orderedList(s, sub):
                return ListBlockView(items: sub, ordered: true, start: s, depth: depth + 1,
                                     context: context, renderer: renderer)
            default:
                return renderer.view(for: block)
            }
        }
    }
}
```

- [ ] **Step 2: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace the two flat list cases:
```swift
        case let .unorderedList(items):
            return ListBlockView(items: items, ordered: false, start: 1, depth: 0, context: context, renderer: self)
        case let .orderedList(start, items):
            return ListBlockView(items: items, ordered: true, start: start, depth: 0, context: context, renderer: self)
```
Then delete the now-unused `listAttributed(_:ordered:start:)` method from `MarkdownBlockRenderer`.

- [ ] **Step 3: Build + re-run the prose snapshots** (the prose snapshot exercises lists — they WILL change shape now, so this is a re-record):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:SpudMarkdownKitSnapshotTests/MarkdownProseSnapshotTests test 2>&1 | tail -15
```
The list rendering changed, so the 4 prose snapshots will FAIL against the old refs. **Delete the 4 old `MarkdownProseSnapshotTests` reference PNGs, re-run to record the new ones, eyeball them (the lists should now show proper markers + indented content, nested items indented further), then re-run to verify green.** Build alone should also succeed.

- [ ] **Step 4: Commit** (code + the re-recorded prose snapshot PNGs).
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit SpudMarkdownKitSnapshotTests
git commit -m "feat(markdown): ListBlockView for true nested lists

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: SpoilerBlockView (disclosure of nested blocks)

**Files:** Create `SpudMarkdownKit/Rendering/SpoilerBlockView.swift`; Modify `MarkdownBlockRenderer.swift` (wire `.spoiler`)

A disclosure container: a tappable header row (chevron + title) over a collapsible stack of the spoiler's nested block views. Toggling adds/removes the body from the stack (Auto Layout re-lays out the parent), and fires `renderer.onContentSizeChange` so the host re-measures.

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/SpoilerBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A spoiler: a tappable disclosure header over a collapsible stack of the
/// spoiler's nested block views. Starts collapsed.
final class SpoilerBlockView: UIView {
    private let bodyStack = UIStackView()
    private let chevron = UIImageView()
    private var expanded = false
    private let onContentSizeChange: (() -> Void)?

    init(title: [MarkdownInline], children: [MarkdownBlock],
         context: MarkdownContext, renderer: MarkdownBlockRenderer) {
        onContentSizeChange = renderer.onContentSizeChange
        super.init(frame: .zero)
        backgroundColor = .secondarySystemFill
        layer.cornerRadius = context.kind == .post ? 10 : 8
        clipsToBounds = true

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        let hPad: CGFloat = context.kind == .post ? 13 : 10
        let vPad: CGFloat = context.kind == .post ? 10 : 8
        header.layoutMargins = UIEdgeInsets(top: vPad, left: hPad, bottom: vPad, right: hPad)
        header.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = context.accentColor
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        if title.isEmpty {
            titleLabel.text = "Spoiler"
            titleLabel.font = .italicSystemFont(ofSize: context.bodyFont.pointSize)
            titleLabel.textColor = context.secondaryColor
        } else {
            titleLabel.attributedText = InlineAttributedStringBuilder.build(title, context: context)
            titleLabel.font = context.bodyFont.withTraits(.traitBold)
            titleLabel.textColor = context.labelColor
        }
        header.addArrangedSubview(chevron)
        header.addArrangedSubview(titleLabel)

        bodyStack.axis = .vertical
        bodyStack.spacing = context.interBlockGap
        bodyStack.isLayoutMarginsRelativeArrangement = true
        bodyStack.layoutMargins = UIEdgeInsets(top: 0, left: hPad, bottom: vPad, right: hPad)
        for view in renderer.views(for: children) { bodyStack.addArrangedSubview(view) }
        bodyStack.isHidden = true

        let container = UIStackView(arrangedSubviews: [header, bodyStack])
        container.axis = .vertical
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        header.isUserInteractionEnabled = true
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    @objc private func toggle() {
        expanded.toggle()
        bodyStack.isHidden = !expanded
        chevron.image = UIImage(systemName: expanded ? "chevron.down" : "chevron.right")
        onContentSizeChange?()
    }
}
```

- [ ] **Step 2: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .spoiler: return PlaceholderBlockView(label: "spoiler")` with:
```swift
        case let .spoiler(title, children):
            return SpoilerBlockView(title: title, children: children, context: context, renderer: self)
```

- [ ] **Step 3: Build + boot the Lab to test the toggle interactively** (a spoiler must visibly expand/collapse on tap):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -10
```
Expected `** BUILD SUCCEEDED **`. (Interactive expand/collapse is eyeballed in Task 7's Lab; here just confirm it builds and the tap target is wired.)

- [ ] **Step 4: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): SpoilerBlockView (disclosure of nested blocks)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: FootnotesBlockView

**Files:** Create `SpudMarkdownKit/Rendering/FootnotesBlockView.swift`; Modify `MarkdownBlockRenderer.swift` (wire `.footnotes`)

A footnotes section: a top divider + a "FOOTNOTES" header + an ordered list of items, each ending with a ↩ return affordance. (The ref↔def smooth-scroll jump is a Phase-6/integration refinement; Phase 3 renders the section + affordance.)

- [ ] **Step 1: Implement** `SpudMarkdownKit/Rendering/FootnotesBlockView.swift`:
```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// The footnotes section at the end of a body: a divider, a small uppercase
/// "Footnotes" header, and the numbered notes (each with a return affordance).
final class FootnotesBlockView: UIView {
    init(footnotes: [MarkdownFootnote], context: MarkdownContext) {
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = context.kind == .post ? 7 : 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)

        let header = UILabel()
        header.text = "FOOTNOTES"
        header.font = context.headingFont(level: 6)
        header.textColor = context.secondaryColor
        stack.addArrangedSubview(header)

        for note in footnotes {
            let label = ProseBlockView()
            let m = NSMutableAttributedString(string: "\(note.label). ", attributes: [
                .font: context.smallFont.withTraits(.traitBold), .foregroundColor: context.secondaryColor,
            ])
            m.append(InlineAttributedStringBuilder.build(note.content, context: context))
            m.append(NSAttributedString(string: " \u{21A9}", attributes: [
                .font: context.smallFont, .foregroundColor: context.accentColor,
            ]))
            label.attributedText = m
            stack.addArrangedSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }
}
```

- [ ] **Step 2: Wire it** in `MarkdownBlockRenderer.view(for:)` — replace `case .footnotes: return PlaceholderBlockView(label: "footnotes")` with:
```swift
        case let .footnotes(footnotes):
            return FootnotesBlockView(footnotes: footnotes, context: context)
```

- [ ] **Step 3: Build to verify** (canonical build). Expected `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit.**
```bash
make project && mint run swiftformat SpudMarkdownKit
git add SpudMarkdownKit
git commit -m "feat(markdown): FootnotesBlockView

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Lab sample + structural snapshots (visual checkpoint)

**Files:** Modify `MarkdownLab/MarkdownLabApp.swift` (richer sample); Create `SpudMarkdownKitSnapshotTests/MarkdownStructuralSnapshotTests.swift`

- [ ] **Step 1: Expand the Lab `defaultSample`** in `MarkdownLab/MarkdownLabApp.swift` to include a fenced code block, a table, two spoilers (one empty body), a nested list, and a footnote, so the live Lab exercises everything. Replace the `defaultSample` string with:
```swift
private let defaultSample = """
Valve **finally** shipped SteamOS. Ping @glidergun@lemmy.world or !linux_gaming@lemmy.world.

- A USB-C drive, **8 GB or larger**.
    - Save files sync via cloud.
    - Screenshot your BIOS first.
- The official `rufus` flasher.

1. Disable Secure Boot.
2. Flash the recovery image.

| Subsystem | Claimed | Measured |
|:---|---:|---:|
| Suspend | < 2s | 1.4s |
| Battery | 6h | 5h42m |

```bash
export ALSA_CARD=acp
pactl set-sink-volume @DEFAULT_SINK@ 140%
```

> Third-party support is **best-effort**.

::: spoiler Benchmarks
Locked **60 fps** at 800p medium.
:::

Thanks for reading.[^1]

[^1]: Re-download over a wired connection if the checksum fails.
"""
```
(Note: the triple-backtick fence inside a Swift multiline string is fine — Swift doesn't treat backticks specially inside `"""`.)

- [ ] **Step 2: Build + boot + screenshot the Lab** (visual checkpoint — the screenshot is reviewed):
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
rm -rf /tmp/mdlab-dd
xcodebuild -project Spud.xcodeproj -scheme MarkdownLab \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation \
  -derivedDataPath /tmp/mdlab-dd build 2>&1 | tail -8
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator; sleep 3
xcrun simctl install booted "$(find /tmp/mdlab-dd -name MarkdownLab.app -type d | head -1)"
xcrun simctl launch booted info.ddenis.MarkdownLab; sleep 3
xcrun simctl io booted screenshot /tmp/mdlab-phase3.png
echo "screenshot: /tmp/mdlab-phase3.png"
```
Expected: the rendered body shows a real code block (lang label + Copy + monospaced body), a bordered table with a tinted header, a nested bullet list (sub-items indented further), the spoiler row "Benchmarks" (collapsed, chevron right), and the footnotes section. Confirm `/tmp/mdlab-phase3.png` is > 10KB. Report what you see.

- [ ] **Step 3: Write structural snapshot tests** at `SpudMarkdownKitSnapshotTests/MarkdownStructuralSnapshotTests.swift` — render a structural sample (code + table + nested list + spoiler-collapsed + footnotes) in post/comment × light/dark, using the same pinned-width `render` helper pattern as `MarkdownProseSnapshotTests` (copy that helper's container-sizing approach). Use this sample:
```
| A | B |
|:--|--:|
| 1 | 2 |

```text
line one
line two
```

- item
    - nested

::: spoiler Hidden
secret
:::

note.[^1]

[^1]: a footnote.
```
Add 4 tests (`test_structuralPostLight/Dark`, `test_structuralCommentLight/Dark`) following the exact structure of `MarkdownProseSnapshotTests` (the `@MainActor render(kind:width:)` helper + `assertSnapshot(of:as:.image(traits:))`).

- [ ] **Step 4: Record + verify the structural snapshots** (first run records + fails; eyeball the 4 PNGs under `SpudMarkdownKitSnapshotTests/__Snapshots__/MarkdownStructuralSnapshotTests/`; re-run to verify green). They MUST be real renders showing the code block, table, nested list, collapsed spoiler, and footnotes.

- [ ] **Step 5: FINAL VERIFICATION** — full target + Spud app:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/enumerated-rolling-plum
make project
xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test 2>&1 | tail -20
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation build 2>&1 | tail -12
```
Expected: SpudMarkdownKit target `** TEST SUCCEEDED **` (all prior tests + the new renderer tests + prose snapshots + 4 structural snapshots) and Spud app `** BUILD SUCCEEDED **`. Report the total test count.

- [ ] **Step 6: Commit** (Lab sample + structural snapshot test + recorded PNGs):
```bash
make project && mint run swiftformat MarkdownLab SpudMarkdownKitSnapshotTests
git add MarkdownLab SpudMarkdownKitSnapshotTests
git commit -m "test(markdown): structural block snapshots + richer Lab sample

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Done criteria for Phase 3

- Code blocks (copy + h-scroll), tables (aligned + scrollable), spoilers (tap to expand/collapse nested blocks), and footnotes render as real interactive views — no more placeholders for those four kinds.
- Lists nest properly (sub-lists indented, multi-block items) via `ListBlockView`.
- The Lab shows the full kitchen sink live; structural snapshots are recorded + eyeballed for post/comment × light/dark; full target + Spud app green.

## Known limitations carried forward

- Rounded mention/community chips (still rectangular); full smooth-scroll footnote ref↔def jump; fence-aware preprocessors; spoiler-in-list extraction; H6 inline-formatting preservation; the small Phase-2 cleanup items (`context` let, a few test-coverage gaps).

## Next

- **Phase 4** — media block views: `ImageBlockView` (loading/failed/zoom/caption), `AudioBlockView`, `VideoBlockView` + the media delegate methods.
- **Phase 5** — snapshot-suite breadth + edge cases (the kitchen-sink edge redlines).
- **Phase 6** — integration into Spud (replace `BodyTextView`/`LinkLabel`) + wire the delegate to real navigation/media/haptics + fix the carried parser limitations + rounded chips + footnote jump.
```
