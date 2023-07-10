//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import os.log

protocol PostContentDetectorServiceType: AnyObject {
    /// Attempt to detect the content type of the url that the given post contains.
    /// The main point is to detect if the url points to an image.
    func contentTypeForUrl(in post: LemmyPost) -> AnyPublisher<PostContentType, Never>
}

protocol HasPostContentDetectorService {
    var postContentDetectorService: PostContentDetectorServiceType { get }
}

class PostContentDetectorService: PostContentDetectorServiceType {
    /// Local in-memory cache of the detected content types that involved network (async) calls.
    /// This is to avoid doing too many network requests (and load remote servers) as well as improve user experience
    /// when opening the same post requires the same work of detecting post content type.
    var cache: [URL: PostContentType] = [:]

    func contentTypeForUrl(in post: LemmyPost) -> AnyPublisher<PostContentType, Never> {
        guard let url = post.url else {
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

        let externalLink = PostContentType.externalLink(link: .init(
            url: url,
            embedTitle: post.urlEmbedTitle,
            embedDescription: post.urlEmbedDescription
        ))
        let image = PostContentType.image(image: .init(
            thumbnailUrl: post.thumbnailUrl,
            imageUrl: url
        ))

        let session = URLSession.shared

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        return session.dataTaskPublisher(for: request)
            .flatMap { (data: Data, response: URLResponse) -> AnyPublisher<PostContentType, URLError> in
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
                    os_log("The server does not allow HEAD requests for url %{public}@",
                           log: .postContentDetectorService, type: .debug,
                           url.absoluteString)

                    // fallback to retry the same request but this time as a GET request.
                    let request = URLRequest(url: url)
                    return session.dataTaskPublisher(for: request)
                        .flatMap { (data: Data, response: URLResponse) -> AnyPublisher<PostContentType, URLError> in
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
                    os_log("Failed to detect content type. Received HTTP status %{public}d for url %{public}@",
                           log: .postContentDetectorService, type: .error,
                           httpUrlResponse.statusCode, url.absoluteString)
                    // We could not detect the content type, lets assume this is an external link,
                    // but no need to cache this response.
                    return .just(externalLink)
                }
            }
            .map { postContentType in
                os_log("Detected content type %{public}@ for url %{public}@",
                       log: .postContentDetectorService, type: .debug,
                       postContentType.debugDescription, url.absoluteString)
                return postContentType
            }
            .catch { urlError -> AnyPublisher<PostContentType, Never> in
                os_log("An error occurred while trying to detect content type for url %{public}@: %{public}@",
                       log: .postContentDetectorService, type: .error,
                       url.absoluteString, urlError.localizedDescription)

                return .just(externalLink)
            }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
}
