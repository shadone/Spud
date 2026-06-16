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
    case text(String) // already smart-typographed
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case highlight([MarkdownInline]) // ==mark==
    case code(String) // inline code, never wraps
    case superscript([MarkdownInline]) // ^x^
    case `subscript`([MarkdownInline]) // ~x~
    case link(text: [MarkdownInline], url: URL)
    case mention(name: String, instance: String) // @user@instance
    case community(name: String, instance: String) // !community@instance
    case emoji(String) // resolved unicode
    case customEmoji(shortcode: String) // ::shortcode:: (server emoji)
    case footnoteReference(String) // [^label]
}
