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
    case spoiler(title: [MarkdownInline], children: [MarkdownBlock]) // title empty => render fallback label
    case footnotes([MarkdownFootnote])
    case thematicBreak
}

/// One list item; its content is itself a sequence of blocks (typically a
/// paragraph, optionally followed by a nested list).
public struct MarkdownListItem: Equatable, Sendable {
    public var blocks: [MarkdownBlock]
    public init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}
