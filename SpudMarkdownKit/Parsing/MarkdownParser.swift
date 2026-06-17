//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The public markdown -> block-tree entry point for Spud bodies. Pure and
/// synchronous, so it can run off the main thread and be cached by the host.
public enum MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        guard !source.isEmpty else { return [] }

        let footnoteResult = FootnoteExtractor.extract(source)
        let spoilerResult = SpoilerPreprocessor.preprocess(footnoteResult.source)

        let protectedSource = SubSupPreprocessor.protectText(spoilerResult.source)
        var blocks = BlockParser.document(protectedSource)
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
            case let .unorderedList(items):
                return .unorderedList(reinjectSpoilers(in: items, spoilers: spoilers))
            case let .orderedList(start, items):
                return .orderedList(start: start, reinjectSpoilers(in: items, spoilers: spoilers))
            default:
                return block
            }
        }
    }

    private static func reinjectSpoilers(
        in items: [MarkdownListItem],
        spoilers: [String: SpoilerPreprocessor.Spoiler]
    ) -> [MarkdownListItem] {
        items.map { MarkdownListItem(blocks: reinjectSpoilers($0.blocks, spoilers: spoilers)) }
    }

    /// If `inlines` is exactly a spoiler sentinel (`…spoiler:<id>…`), the id.
    private static func spoilerID(in inlines: [MarkdownInline]) -> String? {
        guard inlines.count == 1, case let .text(text) = inlines[0] else { return nil }
        guard let match = text.wholeMatch(of: /\u{E000}spoiler:([0-9]+)\u{E001}/) else { return nil }
        return String(match.1)
    }
}
