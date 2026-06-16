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
