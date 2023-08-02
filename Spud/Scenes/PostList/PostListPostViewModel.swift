//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class PostListPostViewModel {
    typealias OwnDependencies =
        HasImageService &
        HasAppearanceService &
        HasPostContentDetectorService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = OwnDependencies & NestedDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

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

        let score = post.publisher(for: \.score)
            .combineLatest(post.voteStatusPublisher, secondaryAttributes)
            .map { tuple in
                let score = tuple.0
                let voteStatus = tuple.1
                let attributes = tuple.2
                return IconValueFormatter.attributedString(
                    numberOfVotesOrScore: score,
                    voteStatus: voteStatus,
                    attributes: attributes,
                    appearance: self.dependencies.own.appearanceService.general
                )
            }
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
                score,
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
        case image(ImageLoadingState)
        /// Text post, we display an icon.
        case text
    }

    var postContentType: AnyPublisher<PostContentType, Never> {
        dependencies.own.postContentDetectorService
            .contentTypeForUrl(in: post)
    }

    var thumbnail: AnyPublisher<ThumbnailType, Never> {
        postContentType
            .flatMap { postContentType -> AnyPublisher<ThumbnailType, Never> in
                switch postContentType {
                case .externalLink:
                    // TODO: display a link icon / overlay.
                    fallthrough

                case .textOrEmpty:
                    return .just(.text)

                case let .image(image):
                    // TODO: is it ok to fetch image url when thumbnail is not available?
                    // It happens for posts with imgur links e.g.
                    // ```json
                    //   "post": {
                    //     "id": 595454,
                    //     "url": "https://i.imgur.com/7sOcLD8.jpg",
                    //     "ap_id": "https://lemmy.ml/post/1865618",
                    //     ...
                    //   },
                    // ```
                    let thumbnailUrl = image.thumbnailUrl ?? image.imageUrl
                    return self.dependencies.own.imageService
                        .fetch(thumbnailUrl)
                        .map { .image($0) }
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment, weight: .medium),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var communityNameAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var secondaryAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            }
            .eraseToAnyPublisher()
    }

    private let post: LemmyPost
    private var appearance: PostListAppearanceType {
        dependencies.own.appearanceService.postList
    }

    // MARK: Functions

    init(post: LemmyPost, dependencies: Dependencies) {
        self.post = post
        self.dependencies = (own: dependencies, nested: dependencies)
    }
}
