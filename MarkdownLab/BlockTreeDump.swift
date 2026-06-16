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
                for item in items {
                    out += lines(item.blocks, indent: indent + 1)
                }
            case let .orderedList(start, items):
                out.append("\(pad)ol start=\(start) (\(items.count))")
                for item in items {
                    out += lines(item.blocks, indent: indent + 1)
                }
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
