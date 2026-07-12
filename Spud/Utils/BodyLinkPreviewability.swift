//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Whether a body link may carry a browser-style preview in its long-press menu.
///
/// A preview is safe ONLY for a genuine `http(s)` web URL. Internal links (the
/// app's own `info.ddenis.spud://` scheme and the `SpudMarkdownKit`
/// `spud-markdown://` mention/community/object links) and any other non-`http(s)`
/// scheme (e.g. `mailto:`) MUST NOT get a preview: the system link / Safari
/// preview traps when asked to preview a non-`http(s)` URL. That trap is the
/// mention long-press crash this type exists to prevent, so the classification is
/// shared by both the inline-text link menu and the link-preview card menu.
enum BodyLinkPreviewability: Equatable {
    /// A genuine `http(s)` web URL — safe to show a link / Safari preview.
    case previewable
    /// An internal link or a non-`http(s)` scheme — menu only, never a preview.
    case notPreviewable

    /// Classifies `url` for menu preview eligibility. Internal links and any
    /// non-`http(s)` scheme are `.notPreviewable`; only `http`/`https` URLs are
    /// `.previewable`.
    static func classify(_ url: URL) -> BodyLinkPreviewability {
        // The app scheme (`url.spud`) or a `spud-markdown://` mention/community/
        // object link opens in-app only — there is nothing to peek in a browser,
        // and its scheme would trap a preview.
        if url.spud != nil || MarkdownInternalLink.resolve(url) != nil {
            return .notPreviewable
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .notPreviewable
        }
        return .previewable
    }
}
