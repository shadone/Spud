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
            // HTMLBlock and anything unknown are dropped.
            return nil
        }
    }

    private static func listItem(_ item: ListItem) -> MarkdownListItem {
        MarkdownListItem(blocks: item.children.compactMap { convertBlock($0) })
    }

    private static func mediaBlock(from paragraph: Paragraph) -> MarkdownBlock? {
        // A paragraph whose only meaningful inline child is an image becomes a
        // media block (image / audio / video).
        let children = Array(paragraph.children)
        guard children.count == 1, let image = children.first as? Markdown.Image,
              let source = image.source, let url = URL(string: source) else { return nil }
        switch MediaDetector.kind(of: url) {
        case .image: return .image(MarkdownImage(url: url, altText: image.plainText))
        case .audio: return .audio(url: url)
        case .video: return .video(url: url)
        }
    }

    private static func convertTable(_ table: Markdown.Table) -> MarkdownBlock {
        let alignments = table.columnAlignments.map { mapAlignment($0) }
        let head = tableCells(in: table.head).map { inlineChildren($0) }
        let rows: [[[MarkdownInline]]] = table.body.rows.map { row in
            tableCells(in: row).map { inlineChildren($0) }
        }
        return .table(MarkdownTable(alignments: alignments, head: head, rows: rows))
    }

    private static func tableCells(in container: Markup) -> [Markdown.Table.Cell] {
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
        while result.hasSuffix("\n") {
            result.removeLast()
        }
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
            if let source = image.source, let url = URL(string: source) {
                return [.link(text: [.text(image.plainText)], url: url)]
            }
            return []
        case is SoftBreak, is LineBreak:
            return [.text(" ")]
        case let html as InlineHTML:
            return [.text(html.rawHTML)]
        default:
            let text = (markup as? PlainTextConvertibleMarkup)?.plainText ?? ""
            return text.isEmpty ? [] : [.text(text)]
        }
    }
}
