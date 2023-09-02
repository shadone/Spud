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
    /// Local in-memory cache of the detected content types that involved network (async) calls.
    /// This is to avoid doing too many network requests (and load remote servers) as well as improve user experience
    /// when opening the same post requires the same work of detecting post content type.
    var cache: [URL: PostContentType] = [:]

    public init() { }

    public func contentTypeForUrl(in postInfo: LemmyPostInfo) -> AnyPublisher<PostContentType, Never> {
        guard let url = postInfo.url else {
            return .just(.textOrEmpty)
        }

        // TODO: we could do more offline checks here:
        // - check if the domain is in Core Data as LemmySite (i.e. link to pictrs resource).
        // - check if popular image hosting like imgur.

        if let contentTypeFromCache = cache[url] {
            return .just(contentTypeFromCache)
        }

        func addToCache(_ contentType: PostContentType) {
            cache[url] = contentType
        }

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

        let session = URLSession.shared

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return session.dataTaskPublisher(for: request)
            .flatMap { (_: Data, response: URLResponse) -> AnyPublisher<PostContentType, URLError> in
                guard let httpUrlResponse = response as? HTTPURLResponse else {
                    fatalError("Not HTTP?")
                }

                switch httpUrlResponse.statusCode {
                case 200..<299: // Success
                    if isImageMimeType(response) {
                        addToCache(image)
                        return .just(image)
                    }

                    addToCache(externalLink)
                    return .just(externalLink)

                case 405: // HTTP 405: Method Not Allowed
                    logger.debug("The server does not allow HEAD requests for url \(url.absoluteString, privacy: .public)")

                    // fallback to retry the same request but this time as a GET request.
                    let request = URLRequest(url: url)
                    return session.dataTaskPublisher(for: request)
                        .flatMap { (_: Data, response: URLResponse) -> AnyPublisher<PostContentType, URLError> in
                            guard let httpUrlResponse = response as? HTTPURLResponse else {
                                fatalError("Not HTTP?")
                            }

                            switch httpUrlResponse.statusCode {
                            case 200..<299: // Success
                                if isImageMimeType(response) {
                                    addToCache(image)
                                    return .just(image)
                                }

                                addToCache(externalLink)
                                return .just(externalLink)

                            default:
                                addToCache(externalLink)
                                return .just(externalLink)
                            }
                        }
                        .eraseToAnyPublisher()

                default:
                    logger.error("""
                        Failed to detect content type. \
                        Received HTTP status \(httpUrlResponse.statusCode, privacy: .public) \
                        for url \(url.absoluteString, privacy: .public)
                        """)
                    // We could not detect the content type, lets assume this is an external link,
                    // but no need to cache this response.
                    return .just(externalLink)
                }
            }
            .map { postContentType in
                logger.debug("""
                    Detected content type \(postContentType.debugDescription, privacy: .public) \
                    for url \(url.absoluteString, privacy: .public)
                    """)
                return postContentType
            }
            .catch { urlError -> AnyPublisher<PostContentType, Never> in
                logger.error("""
                    An error occurred while trying to detect content type \
                    for url \(url.absoluteString, privacy: .public): \
                    \(urlError.localizedDescription, privacy: .public)
                    """)

                return .just(externalLink)
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
