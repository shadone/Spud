//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Host callback for taps inside a rendered markdown body. The host resolves
/// web links (in-app vs Safari per preference) and `spud-markdown://`
/// mention/community URLs (via the app's own routing).
@MainActor
public protocol MarkdownBodyDelegate: AnyObject {
    func markdownBody(didTapLink url: URL)
}
