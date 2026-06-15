//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// One transform in the ``URLSanitizer`` pipeline. A step that does not apply
/// (its feature is off, or the URL does not match) returns `url` unchanged.
public protocol URLRewriteStep: Sendable {
    func apply(_ url: URL, config: URLSanitizerConfig) -> URL
}
