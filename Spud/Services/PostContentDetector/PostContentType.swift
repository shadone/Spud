//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum PostContentType {
    struct Image {
        let thumbnailUrl: URL?
        let imageUrl: URL
    }

    struct Link {
        let url: URL
        let embedTitle: String?
        let embedDescription: String?
    }

    /// Post with title and optional body text. No external link, no image.
    ///
    /// ```
    /// {
    ///   "name": "We never wash our belts, although they are the first thing we touch when leaving the toilet, even before we wash our hands",
    ///   "ap_id": "https://feddit.de/post/1380221",
    ///   ...
    /// }
    /// ```
    ///
    /// or
    ///
    /// ```
    /// {
    ///   "body": "I'm tired about reading about reddit here.\n\nWe left. Let's move on.",
    ///   "ap_id": "https://lemmy.fmhy.ml/post/684818",
    ///   ...
    /// }
    /// ```
    case textOrEmpty

    /// Post with image, title and optional body text.
    ///
    /// The image could be from Lemmy:
    ///
    /// ```
    /// {
    ///   "url": "https://lemmy.ca/pictrs/image/2faf34ee-3ed3-4f06-8cc7-337f06d1d8bf.jpeg",
    ///   "thumbnail_url": "https://discuss.tchncs.de/pictrs/image/7be52bdc-13cd-4d64-ac0e-fca9c4fbbbb8.jpeg",
    ///   "ap_id": "https://lemmy.ca/post/1165975",
    ///   ...
    /// }
    /// ```
    ///
    /// or image from an external service:
    ///
    /// ```
    /// {
    ///   "url": "https://i.imgur.com/JpizWGy.jpg",
    ///   "ap_id": "https://lemmy.world/post/1153658",
    ///   ...
    /// }
    /// ```
    ///
    /// body may or may not be present:
    ///
    /// ```
    /// {
    ///   "url": "https://lemmy.world/pictrs/image/fa385ad0-05e2-4bcb-ac7b-eede66bbfd0b.jpeg",
    ///   "body": "SimilarWeb has just released traffic estimates for June.",
    ///   "thumbnail_url": "https://lemmy.world/pictrs/image/a21cf39f-318d-4633-b5b7-5f93750c7f12.jpeg",
    ///   "ap_id": "https://lemmy.world/post/1094374",
    ///   ...
    /// }
    /// ```
    case image(image: Image)

    /// The post contains a link to an external service (and optionally body etc).
    ///
    /// ```
    /// {
    ///   "url": "https://www.vice.com/en/article/qjvjmq/you-cant-look-at-porn-on-any-reddit-third-party-app-now",
    ///   "embed_title": "You Can't Look at Porn on Any Reddit Third-Party App Now",
    ///   "embed_description": "Following changes to its API access, users are forced to log in on the official Reddit app if they want to view NSFW content on mobile.",
    ///   "thumbnail_url": "https://discuss.tchncs.de/pictrs/image/50c11439-0596-4cc1-ba2a-b18d4010bfb0.jpeg",
    ///   "ap_id": "https://lemmy.world/post/1113629",
    ///   ...
    /// }
    /// ```
    case externalLink(link: Link)
}

extension PostContentType: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .textOrEmpty:
            return "textOrEmpty"
        case .image:
            return "image"
        case .externalLink:
            return "externalLink"
        }
    }
}
