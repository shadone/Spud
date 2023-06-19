//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostListPostViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.title)
            .combineLatest(titleAttributes)
            .map { title, attributes in
                AttributedString(title, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString, Never> {
        let communityName = post.publisher(for: \.communityName)
            .combineLatest(communityNameAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let numberOfUpvotes = post.publisher(for: \.numberOfUpvotes)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfUpvotes: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let numberOfComments = post.publisher(for: \.numberOfComments)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfComments: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let age = post.publisher(for: \.published)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(relativeDate: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let space = Just("  ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()

        return Just(NSAttributedString())
            .combineLatest([
                communityName,
                space,
                numberOfUpvotes,
                space,
                numberOfComments,
                space,
                age,
            ])
            .removeDuplicates()
            .map { $0.joined() }
            .eraseToAnyPublisher()
    }

    enum ThumbnailType {
        /// Thumbnail is an image.
        case image(UIImage)
        /// Image failed to load, we display a broken image icon.
        case imageFailure
        /// Text post, we display an icon.
        case text
    }

    var thumbnail: AnyPublisher<ThumbnailType, Never> {
        post.thumbnailType
            .flatMap { thumbnailType -> AnyPublisher<ThumbnailType, Never> in
                switch thumbnailType {
                case let .image(imageUrl):
                    return self.imageService.get(imageUrl)
                        .map { .image($0)}
                        .replaceError(with: .imageFailure)
                        .eraseToAnyPublisher()

                case .text:
                    return Just(.text)
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment, weight: .medium),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var communityNameAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.label,
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

    private let post: LemmyPost
    private let imageService: ImageServiceType

    // MARK: Functions

    init(post: LemmyPost, imageService: ImageServiceType) {
        self.post = post
        self.imageService = imageService
    }
}
