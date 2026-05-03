//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.postContentDetectorService

public protocol PostContentDetectorServiceType: AnyObject {
    /// Attempt to detect the content type of the url that the given post contains.
    /// The main point is to detect if the url points to an image.
    func contentTypeForUrl(in post: LemmyPostInfo) -> PostContentType

    /// Same detection but driven by raw post fields rather than the legacy
    /// Core Data type. Use from GRDB-backed snapshots in Stage 5+ scenes.
    func contentTypeForUrl(
        url: URL?,
        thumbnailUrl: URL?,
        embedTitle: String?,
        embedDescription: String?
    ) -> PostContentType
}

@MainActor
public protocol HasPostContentDetectorService {
    var postContentDetectorService: PostContentDetectorServiceType { get }
}

public class PostContentDetectorService: PostContentDetectorServiceType {
    public init() { }

    public func contentTypeForUrl(in postInfo: LemmyPostInfo) -> PostContentType {
        contentTypeForUrl(
            url: postInfo.url,
            thumbnailUrl: postInfo.thumbnailUrl,
            embedTitle: postInfo.urlEmbedTitle,
            embedDescription: postInfo.urlEmbedDescription
        )
    }

    public func contentTypeForUrl(
        url: URL?,
        thumbnailUrl: URL?,
        embedTitle: String?,
        embedDescription: String?
    ) -> PostContentType {
        guard let url else {
            return .textOrEmpty
        }

        // TODO: we could do more offline checks here:
        // - check if the domain is in Core Data as LemmySite (i.e. link to pictrs resource).
        // - check if popular image hosting like imgur.

        let externalLink = PostContentType.externalLink(.init(
            url: url,
            embedTitle: embedTitle,
            embedDescription: embedDescription
        ))
        let image = PostContentType.image(.init(
            thumbnailUrl: thumbnailUrl,
            imageUrl: url
        ))

        let path = url.safePath
        let hasKnownImageExtension = [
            ".jpg",
            ".jpeg",
            ".png",
            ".webp",
        ].first { substr in
            path.endsWith(substr)
        } != nil

        if hasKnownImageExtension {
            return image
        }

        return externalLink
    }
}
