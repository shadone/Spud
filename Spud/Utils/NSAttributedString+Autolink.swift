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

        // Linkify Lemmy mention shorthands (`!c@i`, `@u@i`). These are not URLs,
        // so NSDataDetector never sees them; they carry the instance inline and
        // need no known-instance allowlist. Stored as the internal-scheme URL so
        // LinkLabel routes them through `url.spud` like any other internal link.
        for mention in LemmyURLParser.mentions(in: string) {
            let range = mention.range
            guard range.location < length, NSMaxRange(range) <= length else { continue }

            // Don't overlap an existing link (URL autolink or explicit markdown).
            if attribute(.link, at: range.location, effectiveRange: nil) != nil {
                continue
            }
            // Don't linkify inside code spans/blocks (matches the URL pass).
            if let font = attribute(.font, at: range.location, effectiveRange: nil) as? UIFont,
               font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            {
                continue
            }

            // `addAttribute` replaces any prior `.link` on sub-ranges within the
            // mention (the URL pass above may have linkified the inner `host` or
            // `user@host` fragment), so the internal link covers the full mention
            // span atomically — no split links. The skip check above reads `self`,
            // whose mention prefix (`!`/`@`) the URL pass never linkifies.
            result.addAttribute(.link, value: mention.link.url, range: range)
            result.addAttribute(.foregroundColor, value: linkColor, range: range)
        }

        return result
    }
}
