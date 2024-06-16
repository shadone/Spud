//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import UIKit

@MainActor
class PostListPostViewModel {
    typealias OwnDependencies =
        HasAppearanceService &
        HasImageService &
        HasPostContentDetectorService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var imageService: ImageServiceType { dependencies.own.imageService }
    var appearanceService: AppearanceServiceType { dependencies.own.appearanceService }
    var postContentDetectorService: PostContentDetectorServiceType { dependencies.own.postContentDetectorService }

    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        postInfo.publisher(for: \.title)
            .combineLatest(titleAttributes)
            .map { title, attributes in
                AttributedString(title, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString, Never> {
        let communityName = communityName
            .combineLatest(communityNameAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let score = postInfo.publisher(for: \.score)
            .combineLatest(postInfo.voteStatusPublisher, secondaryAttributes)
            .map { tuple in
                let score = tuple.0
                let voteStatus = tuple.1
                let attributes = tuple.2
                return IconValueFormatter.attributedString(
                    numberOfVotesOrScore: score,
                    voteStatus: voteStatus,
                    attributes: attributes,
                    appearance: self.appearanceService.general
                )
            }
            .eraseToAnyPublisher()

        let numberOfComments = postInfo.publisher(for: \.numberOfComments)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfComments: $0, attributes: $1) }
            .eraseToAnyPublisher()

        let age = postInfo.publisher(for: \.published)
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
        postContentDetectorService
            .contentTypeForUrl(in: postInfo)
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
                    return self.imageService
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
            .combineLatest(isRead)
            .map { textSizeAdjustment, isRead -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .title2,
                        relativeSize: textSizeAdjustment,
                        weight: .medium
                    ),
                    .foregroundColor: isRead ? UIColor.secondaryLabel : UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var communityNameAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: -1 + textSizeAdjustment,
                        weight: .regular
                    ),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var secondaryAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: -1 + textSizeAdjustment,
                        weight: .regular
                    ),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var community: AnyPublisher<LemmyCommunity, Never> {
        postInfo.publisher(for: \.community)
            .eraseToAnyPublisher()
    }

    private var communityInfo: AnyPublisher<LemmyCommunityInfo?, Never> {
        community
            .flatMap { community -> AnyPublisher<LemmyCommunityInfo?, Never> in
                community.publisher(for: \.communityInfo)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private var communityName: AnyPublisher<String, Never> {
        communityInfo
            .map { communityInfo in
                communityInfo?.name ?? ""
            }
            .eraseToAnyPublisher()
    }

    private var isRead: AnyPublisher<Bool, Never> {
        postInfo.publisher(for: \.isRead)
            .eraseToAnyPublisher()
    }

    private let postInfo: LemmyPostInfo
    private var appearance: PostListAppearanceType {
        appearanceService.postList
    }

    // MARK: Functions

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.postInfo = postInfo
        self.dependencies = (own: dependencies, nested: dependencies)
    }
}
