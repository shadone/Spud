//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import OSLog

private let logger = Logger.offlineDownloadService

/// One post the offline downloader will predownload: its server id plus the
/// image URLs to warm into the durable disk cache. `imageUrl` is the post's
/// `url` only when it points at an image (link/text posts leave it nil), and
/// `externalLinkUrl` is the post's `url` only when it points at an external web
/// page (image/text/video posts leave it nil).
///
/// A small Sendable value type so it can cross the `OfflineDownloadService`
/// actor boundary to the per-item `TaskGroup`.
public struct OfflineDownloadTarget: Sendable, Equatable {
    /// Server-assigned post id (`PostRecord.postId`), passed to
    /// `LemmyServiceType.fetchComments`.
    public let serverPostId: Int64
    /// The post's thumbnail image, when present.
    public let thumbnailUrl: URL?
    /// The post's full image, when the post is an image post; nil for
    /// link/text/video posts.
    public let imageUrl: URL?
    /// The post's external link target, when the post is an external-link post;
    /// nil for image/text/video posts. Captured as a web archive when the
    /// download's `archiveLinks` option is on (best-effort, opt-in).
    public let externalLinkUrl: URL?

    public init(serverPostId: Int64, thumbnailUrl: URL?, imageUrl: URL?, externalLinkUrl: URL? = nil) {
        self.serverPostId = serverPostId
        self.thumbnailUrl = thumbnailUrl
        self.imageUrl = imageUrl
        self.externalLinkUrl = externalLinkUrl
    }
}

public extension AppDatabase {
    /// Synchronous count of distinct posts currently persisted for the feed
    /// identified by `feedKey`, in the same join the post list uses
    /// (`feed -> page -> pageElement -> post`). Returns 0 before the first
    /// `appendFeedPage` lazily creates the feed row.
    ///
    /// Drives the page-fetch loop's stop condition (stop once the cap is
    /// reached) and the `postsFetched` progress counter. Synchronous to match
    /// the existing `*Sync` helper convention (e.g. `feedRowIdSync`).
    func offlineFeedPostCountSync(feedKey: String) -> Int {
        do {
            return try writer.read { db in
                try Int.fetchOne(db, sql: """
                        SELECT COUNT(DISTINCT post.id)
                        FROM post
                        JOIN pageElement ON pageElement.postId = post.id
                        JOIN page        ON page.id = pageElement.pageId
                        JOIN feed        ON feed.id = page.feedId
                        WHERE feed.feedKey = ?
                    """, arguments: [feedKey]) ?? 0
            }
        } catch {
            logger.error("Failed to count offline feed posts: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    /// Synchronous read of up to `limit` download targets for the feed
    /// identified by `feedKey`, in feed display order
    /// (`page.position`, `pageElement.position`).
    ///
    /// For each post it returns the thumbnail URL (when present) and resolves
    /// `imageUrl` to the post's `url` only when that url is detected as an image
    /// (via ``PostContentDetectorService``), so the downloader warms the full
    /// image for image posts but not for link/text/video posts. Symmetrically it
    /// resolves `externalLinkUrl` to the post's `url` only when that url is an
    /// external web page, so the downloader can web-archive link posts (opt-in)
    /// but not image/text/video ones. Distinct posts only (a post that appears on
    /// two pages is returned once, at its earliest position).
    ///
    /// Synchronous to match the existing `*Sync` helper convention.
    func offlineDownloadTargetsSync(feedKey: String, limit: Int) -> [OfflineDownloadTarget] {
        // Stateless; allocate once and capture rather than per-row inside the
        // read closure.
        let detector = PostContentDetectorService()
        do {
            return try writer.read { db in
                let rows = try Row.fetchAll(db, sql: """
                        SELECT
                            post.postId               AS serverPostId,
                            post.thumbnailUrl         AS thumbnailUrl,
                            post.url                  AS url,
                            post.urlEmbedTitle        AS urlEmbedTitle,
                            post.urlEmbedDescription  AS urlEmbedDescription,
                            MIN(page.position)        AS pagePosition,
                            MIN(pageElement.position) AS elementPosition
                        FROM post
                        JOIN pageElement ON pageElement.postId = post.id
                        JOIN page        ON page.id = pageElement.pageId
                        JOIN feed        ON feed.id = page.feedId
                        WHERE feed.feedKey = ?
                        GROUP BY post.id
                        ORDER BY pagePosition ASC, elementPosition ASC
                        LIMIT ?
                    """, arguments: [feedKey, limit])

                return rows.map { row -> OfflineDownloadTarget in
                    let serverPostId: Int64 = row["serverPostId"]
                    // Single column subscripts only — never chain two with `??`
                    // (the GRDB double-optional footgun; see CLAUDE.md).
                    let thumbnailString: String? = row["thumbnailUrl"]
                    let urlString: String? = row["url"]
                    let embedTitle: String? = row["urlEmbedTitle"]
                    let embedDescription: String? = row["urlEmbedDescription"]

                    let thumbnailUrl = thumbnailString.flatMap(URL.init(string:))
                    let postUrl = urlString.flatMap(URL.init(string:))

                    // Reuse the production content-detection heuristic rather
                    // than a duplicate extension check, so "is this an image /
                    // external-link post" stays consistent with the feed /
                    // post-detail rendering path. An image post warms its full
                    // image; an external-link post becomes a web-archive target.
                    let imageUrl: URL?
                    let externalLinkUrl: URL?
                    switch detector.contentTypeForUrl(
                        url: postUrl,
                        thumbnailUrl: thumbnailUrl,
                        embedTitle: embedTitle,
                        embedDescription: embedDescription
                    ) {
                    case let .image(image):
                        imageUrl = image.imageUrl
                        externalLinkUrl = nil
                    case let .externalLink(link):
                        imageUrl = nil
                        externalLinkUrl = link.url
                    // A recognized video-host post (e.g. streamable) now classifies as `.video`
                    // rather than `.externalLink`, so — like other videos — its page is not
                    // web-archived for offline reading (the stream itself isn't predownloaded either).
                    case .textOrEmpty, .video:
                        imageUrl = nil
                        externalLinkUrl = nil
                    }

                    return OfflineDownloadTarget(
                        serverPostId: serverPostId,
                        thumbnailUrl: thumbnailUrl,
                        imageUrl: imageUrl,
                        externalLinkUrl: externalLinkUrl
                    )
                }
            }
        } catch {
            logger.error("Failed to read offline download targets: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
