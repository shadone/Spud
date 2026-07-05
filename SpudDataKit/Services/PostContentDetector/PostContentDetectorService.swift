//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.postContentDetectorService

public protocol PostContentDetectorServiceType: AnyObject {
    /// Attempt to detect the content type of the post's url. The main point
    /// is to detect if the url points to an image.
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
    private let videoHostRecognizer: VideoHostRecognizing

    public init(videoHostRecognizer: VideoHostRecognizing = VideoHostRegistry()) {
        self.videoHostRecognizer = videoHostRecognizer
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
        // - check if the domain is in known image-hosting domains
        // - check if popular image hosting like imgur.

        let externalLink = PostContentType.externalLink(.init(
            url: url,
            embedTitle: embedTitle,
            embedDescription: embedDescription
        ))

        // A Lemmy instance with image_proxy enabled rewrites image post urls to
        // `{instance}/api/v3/image_proxy?url={original}`, whose own path has no
        // file extension. Match the extension against the embedded original so a
        // proxied image is still detected as an image instead of a link.
        //
        // The proxy `url` itself stays the imageUrl/videoUrl so the media keeps
        // loading through the instance's proxy (the privacy-preserving path).
        // ImageService sends a plain User-Agent so the proxy host's nginx does
        // not 403 the request (see ImageService.userAgent).
        let path = (url.lemmyImageProxyOriginalUrl ?? url).safePath
        let matchedImageExtension = [
            ".jpg",
            ".jpeg",
            ".png",
            ".webp",
            ".avif",
            ".gif",
        ].first { substr in
            path.endsWith(substr)
        }

        if let matchedImageExtension {
            return .image(.init(
                thumbnailUrl: thumbnailUrl,
                imageUrl: url,
                isAnimated: matchedImageExtension == ".gif"
            ))
        }

        // AVFoundation-playable containers only. webm/mkv are intentionally
        // absent — AVFoundation cannot decode them, so they stay external links.
        let hasPlayableVideoExtension = [
            ".mp4",
            ".mov",
            ".m4v",
        ].contains { path.endsWith($0) }

        if hasPlayableVideoExtension {
            return .video(.init(videoUrl: url, thumbnailUrl: thumbnailUrl))
        }

        // A recognized video-host page (e.g. streamable) is a playable video post.
        // The page URL is carried as videoUrl; the app resolves it to a stream at
        // tap time. The poster comes from the server thumbnail (thumbnailUrl).
        if videoHostRecognizer.recognize(url) != nil {
            return .video(.init(videoUrl: url, thumbnailUrl: thumbnailUrl))
        }

        return externalLink
    }
}
