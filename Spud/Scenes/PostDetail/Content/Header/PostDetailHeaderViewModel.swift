//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import LemmyKit
import UIKit

class PostDetailHeaderViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.title)
            .combineLatest(titleAttributes)
            .map { title, attributes in
                AttributedString(title, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var subtitleScore: AnyPublisher<NSAttributedString, Never> {
        post.publisher(for: \.score)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfUpvotes: $0, attributes: $1) }
            .eraseToAnyPublisher()
    }

    var subtitleComments: AnyPublisher<NSAttributedString, Never> {
        post.publisher(for: \.numberOfComments)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfComments: $0, attributes: $1) }
            .eraseToAnyPublisher()
    }

    var subtitleAge: AnyPublisher<NSAttributedString, Never> {
        post.publisher(for: \.published)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(relativeDate: $0, attributes: $1) }
            .eraseToAnyPublisher()
    }

    var attribution: AnyPublisher<NSAttributedString, Never> {
        let inString = Just("in ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let subreddit = post.publisher(for: \.communityName)
            .combineLatest(secondaryHighlightedAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let byString = Just(" by ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let creator = post.publisher(for: \.creatorName)
            .combineLatest(secondaryHighlightedAttributes)
            .map { tuple -> NSAttributedString in
                let creator = tuple.0
                let attributes = tuple.1

                return NSAttributedString(string: creator, attributes: attributes)
            }
            .eraseToAnyPublisher()

        return Just(NSAttributedString())
            .combineLatest([
                inString,
                subreddit,
                byString,
                creator,
            ])
            .map { $0.joined() }
            .eraseToAnyPublisher()
    }

    var image: AnyPublisher<ImageLoadingState, Never> {
        post.publisher(for: \.url)
            .removeDuplicates()
            .flatMap { url -> AnyPublisher<PostContentType, Never> in
                self.postContentDetectorService.contentType(for: self.post)
            }
            .flatMap { postContentType -> AnyPublisher<ImageLoadingState, Never> in
                switch postContentType {
                case .textOrEmpty, .externalLink:
                    return .empty(completeImmediately: false)

                case let .image(image):
                    return self.imageService.fetch(image.imageUrl)
                }
            }
            .eraseToAnyPublisher()
    }

    var body: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.body)
            .map { AttributedString($0 ?? "") }
            .eraseToAnyPublisher()
    }

    enum ThumbnailType {
        /// Thumbnail is an image.
        case image(UIImage)
        /// Image failed to load, we display a broken image icon.
        case imageFailure
        /// Used before we have an image set.
        case none
    }

    var linkPreviewThumbnail: AnyPublisher<ThumbnailType, Never> {
        post.publisher(for: \.thumbnailUrl)
            .flatMap { imageUrl -> AnyPublisher<ThumbnailType, Never> in
                guard let imageUrl else {
                    return .just(.none)
                }
                return self.imageService.get(imageUrl)
                    .map { .image($0)}
                    .replaceError(with: .imageFailure)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    var url: AnyPublisher<URL, Never> {
        post.publisher(for: \.url)
            .ignoreNil()
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .foregroundColor: UIColor.label,
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 5 + textSizeAdjustment, weight: .medium),
                ]
            }
            .eraseToAnyPublisher()
    }

    private var secondaryAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var secondaryHighlightedAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .medium),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            }
            .eraseToAnyPublisher()
    }

    private let post: LemmyPost
    private let imageService: ImageServiceType
    private let postContentDetectorService: PostContentDetectorServiceType

    // MARK: Functions

    init(
        post: LemmyPost,
        imageService: ImageServiceType,
        postContentDetectorService: PostContentDetectorServiceType
    ) {
        self.post = post
        self.imageService = imageService
        self.postContentDetectorService = postContentDetectorService
    }
}
