//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudMarkdownKit
import SpudUtilKit

/// A previewable link found in a comment body, rendered below the text as a
/// `LinkPreviewView` card.
///
/// `displayURL` is the human-readable URL the card shows (host + path).
/// `tapURL` is what firing the card reproduces: for a plain web link it is the
/// link itself (external open / in-app classification); for a `!community@host`
/// shorthand it is the synthetic `info.ddenis.spud://` URL the post-detail link
/// handler decodes into in-app navigation.
struct CommentLinkPreview: Equatable {
    let displayURL: URL
    let tapURL: URL
}

extension [MarkdownBlock] {
    /// The previewable links in the comment body, in document order,
    /// de-duplicated by `tapURL` and capped at `limit`.
    ///
    /// Walks the parsed block tree: plain `http(s)` links and `!community@host`
    /// shorthands each get a card. Mentions (people) are skipped — matching the
    /// original feature — as are code blocks, media, tables and footnotes, whose
    /// links are not body prose.
    func commentLinkPreviews(limit: Int) -> [CommentLinkPreview] {
        guard limit > 0 else { return [] }
        var result: [CommentLinkPreview] = []
        var seen = Set<String>()
        for block in self {
            collectLinkPreviews(in: block, into: &result, seen: &seen, limit: limit)
            if result.count >= limit { break }
        }
        return result
    }
}

private func collectLinkPreviews(
    in block: MarkdownBlock,
    into result: inout [CommentLinkPreview],
    seen: inout Set<String>,
    limit: Int
) {
    guard result.count < limit else { return }
    switch block {
    case let .paragraph(inlines), let .heading(_, inlines):
        collectLinkPreviews(in: inlines, into: &result, seen: &seen, limit: limit)

    case let .unorderedList(items), let .orderedList(_, items):
        for item in items {
            for child in item.blocks {
                collectLinkPreviews(in: child, into: &result, seen: &seen, limit: limit)
                if result.count >= limit { return }
            }
        }

    case let .blockQuote(children), let .spoiler(_, children):
        for child in children {
            collectLinkPreviews(in: child, into: &result, seen: &seen, limit: limit)
            if result.count >= limit { return }
        }

    case .codeBlock, .table, .image, .audio, .video, .footnotes, .thematicBreak:
        break
    }
}

private func collectLinkPreviews(
    in inlines: [MarkdownInline],
    into result: inout [CommentLinkPreview],
    seen: inout Set<String>,
    limit: Int
) {
    for inline in inlines {
        guard result.count < limit else { return }
        collectLinkPreviews(in: inline, into: &result, seen: &seen, limit: limit)
    }
}

private func collectLinkPreviews(
    in inline: MarkdownInline,
    into result: inout [CommentLinkPreview],
    seen: inout Set<String>,
    limit: Int
) {
    guard result.count < limit else { return }
    switch inline {
    case let .link(_, url):
        if let preview = webLinkPreview(for: url) {
            appendPreview(preview, into: &result, seen: &seen)
        }

    case let .community(name, instance):
        if let preview = communityLinkPreview(name: name, instance: instance) {
            appendPreview(preview, into: &result, seen: &seen)
        }

    case let .strong(children),
         let .emphasis(children),
         let .strikethrough(children),
         let .highlight(children),
         let .superscript(children),
         let .subscript(children):
        collectLinkPreviews(in: children, into: &result, seen: &seen, limit: limit)

    case .text, .code, .mention, .emoji, .customEmoji, .footnoteReference:
        break
    }
}

private func appendPreview(
    _ preview: CommentLinkPreview,
    into result: inout [CommentLinkPreview],
    seen: inout Set<String>
) {
    guard seen.insert(preview.tapURL.absoluteString).inserted else { return }
    result.append(preview)
}

/// A card for a plain `http(s)` link: it both displays and taps as itself.
private func webLinkPreview(for url: URL) -> CommentLinkPreview? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return nil
    }
    return CommentLinkPreview(displayURL: url, tapURL: url)
}

/// A card for a `!community@instance` shorthand: it displays the canonical
/// `https://instance/c/name` web URL and taps the synthetic internal link the
/// post-detail handler decodes into in-app navigation.
private func communityLinkPreview(name: String, instance: String) -> CommentLinkPreview? {
    guard
        let instanceActorId = InstanceActorId(from: instance),
        instanceActorId.isValid,
        let displayURL = URL(string: "\(instanceActorId.actorId)/c/\(name)")
    else {
        return nil
    }
    let tapURL = URL.SpudInternalLink.community(name: name, instance: instanceActorId).url
    return CommentLinkPreview(displayURL: displayURL, tapURL: tapURL)
}
