//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension [MarkdownInline] {
    /// The inline run flattened to plain text (e.g. a link's anchor text). Styling
    /// is dropped; mentions/communities render as `name@instance`.
    var plainText: String {
        map(\.plainText).joined()
    }
}

public extension MarkdownInline {
    var plainText: String {
        switch self {
        case let .text(s), let .code(s), let .emoji(s):
            return s
        case let .customEmoji(shortcode):
            return ":\(shortcode):"
        case let .strong(children),
             let .emphasis(children),
             let .strikethrough(children),
             let .highlight(children),
             let .superscript(children),
             let .subscript(children):
            return children.plainText
        case let .link(text, _):
            return text.plainText
        case let .mention(name, instance), let .community(name, instance):
            return "\(name)@\(instance)"
        case let .footnoteReference(label):
            return "[\(label)]"
        }
    }
}
