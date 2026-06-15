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
