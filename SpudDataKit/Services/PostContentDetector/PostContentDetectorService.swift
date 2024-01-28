//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import OSLog

private let logger = Logger(.postContentDetectorService)

public protocol PostContentDetectorServiceType: AnyObject {
    /// Attempt to detect the content type of the url that the given post contains.
    /// The main point is to detect if the url points to an image.
    func contentTypeForUrl(in post: LemmyPostInfo) -> AnyPublisher<PostContentType, Never>
}

public protocol HasPostContentDetectorService {
    var postContentDetectorService: PostContentDetectorServiceType { get }
}

public class PostContentDetectorService: PostContentDetectorServiceType {
    public init() { }

    public func contentTypeForUrl(in postInfo: LemmyPostInfo) -> AnyPublisher<PostContentType, Never> {
        guard let url = postInfo.url else {
            return .just(.textOrEmpty)
        }

        // TODO: we could do more offline checks here:
        // - check if the domain is in Core Data as LemmySite (i.e. link to pictrs resource).
        // - check if popular image hosting like imgur.

        func isImageMimeType(_ response: URLResponse) -> Bool {
            response.mimeType?.starts(with: "image/") ?? false
        }

        let externalLink = PostContentType.externalLink(.init(
            url: url,
            embedTitle: postInfo.urlEmbedTitle,
            embedDescription: postInfo.urlEmbedDescription
        ))
        let image = PostContentType.image(.init(
            thumbnailUrl: postInfo.thumbnailUrl,
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
            return .just(image)
        }

        return .just(externalLink)
    }
}
