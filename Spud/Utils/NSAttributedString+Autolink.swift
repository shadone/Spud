//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension NSAttributedString {
    /// Returns a copy with `.link` attributes added over bare URLs that the
    /// Markdown parser left as plain text.
    ///
    /// Down renders through Apple's swift-markdown (cmark-gfm), which only enables
    /// the `table`, `strikethrough` and `tasklist` GFM extensions and exposes no
    /// option to enable `autolink`. As a result a bare URL such as
    /// `https://youtu.be/0ORqQPk7kjs` is parsed as plain text and never receives a
    /// `.link` attribute, so `LinkLabel` has nothing to make tappable. Lemmy's web
    /// renderer linkifies bare URLs (markdown-it `linkify`); this restores parity
    /// by detecting URLs in the already-rendered text and attaching the link
    /// attribute (as a `URL`, which `LinkLabel` opens directly).
    ///
    /// Ranges that already carry a `.link` (explicit `[text](url)` links) and
    /// ranges rendered as code (monospace font) are left untouched, matching
    /// markdown-it, which does not linkify inside code spans or blocks.
    func addingAutolinks(linkColor: UIColor = .link) -> NSAttributedString {
        guard length > 0 else { return self }
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return self
        }

        let fullRange = NSRange(location: 0, length: length)
        let matches = detector.matches(in: string, options: [], range: fullRange)
        guard !matches.isEmpty else { return self }

        let result = NSMutableAttributedString(attributedString: self)
        for match in matches {
            guard let url = match.url else { continue }
            let range = match.range
            guard range.location < length else { continue }

            // Leave explicit markdown links (which already carry `.link`) alone.
            if attribute(.link, at: range.location, effectiveRange: nil) != nil {
                continue
            }

            // Don't linkify URLs rendered as code; markdown-it doesn't either.
            if let font = attribute(.font, at: range.location, effectiveRange: nil) as? UIFont,
               font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            {
                continue
            }

            result.addAttribute(.link, value: url, range: range)
            result.addAttribute(.foregroundColor, value: linkColor, range: range)
        }
        return result
    }
}
