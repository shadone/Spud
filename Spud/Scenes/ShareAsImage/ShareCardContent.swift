//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit

/// Immutable, render-agnostic snapshot of what a share card needs to draw —
/// either a post card (``kind`` `.post`) or a comment-chain card (``kind``
/// `.comment``). Built once at the entry point (feed/search post menu,
/// post-detail header menu, or post-detail comment menu) from whichever row
/// type that surface already holds in memory (``PostListRow``,
/// ``PostDetailHeaderRow``, ``PostDetailCommentRow``), so building content
/// never triggers a network fetch or touches `PreferencesService` — the
/// entry point resolves the permalink (via `LinkURL.forPost`/`.forComment`,
/// honoring the user's link-instance preference) and passes it in.
struct ShareCardContent: Equatable {
    /// A post's rendered fields for the post card, or the optional
    /// post-header context shown above a comment chain's ancestor list.
    struct PostSummary: Equatable {
        let title: String
        /// Plain-text body preview (`MarkdownPlainText.preview(from:)`), or
        /// `nil` for a post with no body.
        let bodyPlain: String?
        /// The community's display name (its `title` when the source row
        /// carries one, else its bare slug) — the bold text in the
        /// community lockup.
        let communityName: String
        /// The monospaced "c/name@instance" handle, derived from the
        /// community's actor id. Falls back to a bare "c/name" when the
        /// actor id can't be parsed to a host.
        let communityHandle: String
        /// Always `nil` from the current builders: neither `PostListRow` nor
        /// `PostDetailHeaderRow` carries a community icon URL. The card view
        /// falls back to its initial-on-tint placeholder circle. Reserved
        /// for a future builder that joins the community's icon.
        let communityIconUrl: URL?
        /// The "u/name@instance" handle, or `nil` when the row carries no
        /// creator name.
        let creatorHandle: String?
        let score: Int64
        let commentCount: Int64
        let published: Date
        /// The card footer's permalink for a `.post` card. For a `.comment`
        /// card that includes this post header, this mirrors the SAME
        /// permalink passed to the comment builder (the comment's, not the
        /// post's) — the header is context only, never itself a tap target,
        /// so the footer always uses ``ChainItem/permalink`` of the chain's
        /// destination item instead. See the type-level guardrail note on
        /// ``ShareCardContent``.
        let permalink: URL
        /// The post's image URL, when the post's link content is detected as
        /// an image (`PostContentDetectorService`). `nil` for a text/link/video
        /// post.
        let mediaUrl: URL?
        /// `true` when the image's aspect ratio is wider than 4:3 (from
        /// `imageWidth`/`imageHeight`, when the source row reports them) —
        /// the card relaxes its media height for wide images. `false` when
        /// dimensions are unknown (e.g. every `PostListRow`-built summary,
        /// which carries no image dimensions at all).
        let mediaAspectIsWide: Bool
        let isNsfw: Bool
    }

    /// One line in a comment chain: an ancestor, or the shared comment itself
    /// (the "destination", ``isDestination`` `true`).
    struct ChainItem: Equatable {
        /// The "u/name@instance" handle, or `nil` when the row carries no
        /// creator name (e.g. a deleted account).
        let authorHandle: String?
        let score: Int64
        /// Plain-text body preview, or `nil` for a removed/deleted comment.
        let bodyPlain: String?
        let published: Date?
        /// `true` for exactly one item: the comment the user chose to share.
        /// Rendered emphasized (teal rail, "SHARED" tag, own timestamp).
        let isDestination: Bool
        /// Non-`nil` only when ``isDestination`` is `true` — the shared
        /// comment's permalink, which the chain card's footer uses. Ancestor
        /// items never carry a permalink; they aren't independently
        /// shareable in this card.
        let permalink: URL?
    }

    /// What kind of content the card renders. A `.comment` card's footer
    /// permalink is always the shared comment's, never the (optional)
    /// post header's.
    enum Kind: Equatable {
        case post
        case comment
    }

    /// The post card's content (`.post`), or a chain card's optional
    /// post-header context (`.comment` with `includePostInChain`), or `nil`
    /// (a `.comment` card built with no header).
    let post: PostSummary?
    /// Empty for `.post`. For `.comment`, every ancestor followed by the
    /// shared comment (``ChainItem/isDestination`` `true`), root-most first.
    let chain: [ChainItem]
    let kind: Kind
}

// MARK: - Builders

extension ShareCardContent {
    /// Builds post-card content from a feed/search row. `permalink` is
    /// precomputed by the entry point (`LinkURL.forPost`) — this builder
    /// never touches `PreferencesService`, keeping it a pure function of its
    /// inputs.
    init(postRow row: PostListRow, permalink: URL) {
        post = PostSummary(
            title: row.title,
            bodyPlain: row.body.map { MarkdownPlainText.preview(from: $0) },
            communityName: row.communityName,
            communityHandle: ShareCardHandle.community(name: row.communityName, actorId: row.communityActorId),
            communityIconUrl: nil,
            creatorHandle: row.creatorName.map {
                ShareCardHandle.person(name: $0, actorId: row.creatorActorId)
            },
            score: row.score,
            commentCount: row.numberOfComments,
            published: row.published,
            permalink: permalink,
            mediaUrl: ShareCardContent.detectedImageUrl(
                url: row.url,
                thumbnailUrl: row.thumbnailUrl,
                embedTitle: row.urlEmbedTitle,
                embedDescription: row.urlEmbedDescription
            ),
            // PostListRow carries no image dimensions.
            mediaAspectIsWide: false,
            isNsfw: row.isNsfw
        )
        chain = []
        kind = .post
    }

    /// Builds post-card content from the post-detail header row.
    /// `permalink` is precomputed by the entry point (`LinkURL.forPost`).
    init(headerRow row: PostDetailHeaderRow, permalink: URL) {
        post = PostSummary(headerRow: row, permalink: permalink)
        chain = []
        kind = .post
    }

    /// Builds comment-chain content: `ancestors` (root-most first, e.g. from
    /// ``ShareCardAncestry/ancestors(of:in:)``) followed by `comment` itself,
    /// marked the chain's destination. `header` is the optional post-header
    /// context (`nil` omits it — see ``includePostInChain``, applied by the
    /// caller before this builder runs, not stored on the content). Both
    /// `comment` and `header` come from `PostDetailViewModel` state already
    /// in memory; `permalink` is precomputed by the entry point
    /// (`LinkURL.forComment`).
    init(
        comment: PostDetailCommentRow,
        ancestors: [PostDetailCommentRow],
        header: PostDetailHeaderRow?,
        permalink: URL
    ) {
        post = header.map { PostSummary(headerRow: $0, permalink: permalink) }
        let ancestorItems = ancestors.map { ChainItem(row: $0, isDestination: false, permalink: nil) }
        let destinationItem = ChainItem(row: comment, isDestination: true, permalink: permalink)
        chain = ancestorItems + [destinationItem]
        kind = .comment
    }
}

private extension ShareCardContent.PostSummary {
    init(headerRow row: PostDetailHeaderRow, permalink: URL) {
        let displayName = (row.communityTitle?.isEmpty == false) ? row.communityTitle! : row.communityName
        self.init(
            title: row.title,
            bodyPlain: row.body.map { MarkdownPlainText.preview(from: $0) },
            communityName: displayName,
            communityHandle: ShareCardHandle.community(name: row.communityName, actorId: row.communityActorId),
            communityIconUrl: nil,
            creatorHandle: ShareCardHandle.person(name: row.creatorName, actorId: row.creatorActorId),
            score: row.score,
            commentCount: row.numberOfComments,
            published: row.published,
            permalink: permalink,
            mediaUrl: ShareCardContent.detectedImageUrl(
                url: row.url,
                thumbnailUrl: row.thumbnailUrl,
                embedTitle: row.urlEmbedTitle,
                embedDescription: row.urlEmbedDescription
            ),
            mediaAspectIsWide: ShareCardContent.isWideAspect(width: row.imageWidth, height: row.imageHeight),
            isNsfw: row.isNsfw
        )
    }
}

private extension ShareCardContent.ChainItem {
    init(row: PostDetailCommentRow, isDestination: Bool, permalink: URL?) {
        self.init(
            authorHandle: row.creatorName.map { ShareCardHandle.person(name: $0, actorId: row.creatorActorId) },
            score: row.score,
            bodyPlain: row.body.map { MarkdownPlainText.preview(from: $0) },
            published: row.published,
            isDestination: isDestination,
            permalink: isDestination ? permalink : nil
        )
    }
}

// MARK: - Media detection

private extension ShareCardContent {
    /// Classifies `url` via `PostContentDetectorService` (the app's single
    /// source of truth for "is this post's link an image") and returns its
    /// image URL when it is one. A fresh detector is constructed per call
    /// (it's a small stateless-per-call helper) rather than cached in static
    /// state, so this stays a plain function with no concurrency-safety
    /// requirements of its own.
    static func detectedImageUrl(
        url: String?,
        thumbnailUrl: String?,
        embedTitle: String?,
        embedDescription: String?
    ) -> URL? {
        let detector = PostContentDetectorService()
        let contentType = detector.contentTypeForUrl(
            url: url.flatMap(URL.init(string:)),
            thumbnailUrl: thumbnailUrl.flatMap(URL.init(string:)),
            embedTitle: embedTitle,
            embedDescription: embedDescription
        )
        guard case let .image(image) = contentType else {
            return nil
        }
        return image.imageUrl
    }

    /// `true` when `width`/`height` are both known and the aspect ratio is
    /// wider than 4:3 — the card visual spec's threshold for relaxing the
    /// media block's height. `false` when either dimension is unknown.
    static func isWideAspect(width: Int?, height: Int?) -> Bool {
        guard let width, let height, height > 0 else { return false }
        return Double(width) / Double(height) > 4.0 / 3.0
    }
}

// MARK: - Handle formatting

/// Builds the "c/name@instance" / "u/name@instance" qualified handles the
/// card renders, matching the `@instance` suffix convention used elsewhere in
/// the app (`CrossPostSummary.qualifiedCommunityHandle`,
/// `PostListViewController.qualifiedCommunityHandle(for:)`). Falls back to
/// the bare "c/name" / "u/name" when the actor id can't be parsed to a host.
private enum ShareCardHandle {
    static func community(name: String, actorId: String?) -> String {
        qualified(prefix: "c", name: name, actorId: actorId)
    }

    static func person(name: String, actorId: String?) -> String {
        qualified(prefix: "u", name: name, actorId: actorId)
    }

    private static func qualified(prefix: String, name: String, actorId: String?) -> String {
        guard let actorId, let host = InstanceActorId(from: actorId)?.host else {
            return "\(prefix)/\(name)"
        }
        return "\(prefix)/\(name)@\(host)"
    }
}
