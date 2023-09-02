//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Down
import LemmyKit
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger(.app)

class PostDetailHeaderViewModel {
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

    var subtitleScore: AnyPublisher<NSAttributedString, Never> {
        postInfo.publisher(for: \.score)
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
    }

    var subtitleComments: AnyPublisher<NSAttributedString, Never> {
        postInfo.publisher(for: \.numberOfComments)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfComments: $0, attributes: $1) }
            .eraseToAnyPublisher()
    }

    var subtitleAge: AnyPublisher<NSAttributedString, Never> {
        postInfo.publisher(for: \.published)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(relativeDate: $0, attributes: $1) }
            .eraseToAnyPublisher()
    }

    var attribution: AnyPublisher<NSAttributedString, Never> {
        let inString = Just("in ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let communityName = communityName
            .combineLatest(secondaryHighlightedAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let byString = Just(" by ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let creator = creator
            .combineLatest(secondaryHighlightedAttributes)
            .map { tuple -> NSAttributedString in
                let creator = tuple.0
                var attributes = tuple.1

                attributes[.link] = URL.SpudInternalLink.person(
                    personId: creator.personId,
                    instance: creator.site.instance.actorId
                ).url

                let name = creator.personInfo?.name ?? creator.name
                assert(name != nil)

                return NSAttributedString(string: name ?? "", attributes: attributes)
            }
            .eraseToAnyPublisher()

        return Just(NSAttributedString())
            .combineLatest([
                inString,
                communityName,
                byString,
                creator,
            ])
            .map { $0.joined() }
            .eraseToAnyPublisher()
    }

    var postContentType: AnyPublisher<PostContentType, Never> {
        postContentDetectorService
            .contentTypeForUrl(in: postInfo)
    }

    var image: AnyPublisher<ImageLoadingState, Never> {
        postContentType
            .removeDuplicates()
            .combineLatest(
                postInfo.publisher(for: \.thumbnailUrl)
                    .removeDuplicates()
            )
            .flatMap { tuple -> AnyPublisher<ImageLoadingState, Never> in
                let postContentType = tuple.0
                let thumbnailUrl = tuple.1

                switch postContentType {
                case .textOrEmpty, .externalLink:
                    return .empty(completeImmediately: false)

                case let .image(image):
                    return self.imageService
                        .fetch(image.imageUrl, thumbnail: thumbnailUrl)
                }
            }
            .eraseToAnyPublisher()
    }

    var body: AnyPublisher<NSAttributedString, Never> {
        postInfo.publisher(for: \.body)
            .replaceNil(with: "")
            .combineLatest(appearance.bodyStylerConfiguration)
            .map { text, stylerConfiguration in
                guard
                    let attributedString = try? Down(markdownString: text)
                    .toAttributedString(styler: DownStyler(configuration: stylerConfiguration))
                else {
                    logger.assertionFailure()
                    return NSAttributedString(string: text)
                }

                return attributedString
            }
            .eraseToAnyPublisher()
    }

    var linkPreviewThumbnail: AnyPublisher<(URL, ImageLoadingState)?, Never> {
        postContentType
            .combineLatest(
                postInfo.publisher(for: \.thumbnailUrl),
                postInfo.publisher(for: \.url)
            )
            .flatMap { tuple -> AnyPublisher<(URL, ImageLoadingState)?, Never> in
                let postContentType = tuple.0
                let thumbnailUrl = tuple.1
                let url = tuple.2

                guard let thumbnailUrl, let url else {
                    return .just(nil)
                }

                switch postContentType {
                case .externalLink:
                    return self.imageService
                        .fetch(thumbnailUrl)
                        .map { (url, $0) }
                        .eraseToAnyPublisher()
                case .image, .textOrEmpty:
                    return .just(nil)
                }
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .foregroundColor: UIColor.label,
                    .font: UIFont.scaledSystemFont(
                        style: .title2,
                        relativeSize: 5 + textSizeAdjustment,
                        weight: .medium
                    ),
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

    private var secondaryHighlightedAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: -1 + textSizeAdjustment,
                        weight: .medium
                    ),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var creator: AnyPublisher<LemmyPerson, Never> {
        postInfo.publisher(for: \.creator)
            .eraseToAnyPublisher()
    }

    private var creatorInfo: AnyPublisher<LemmyPersonInfo?, Never> {
        creator
            .flatMap { person -> AnyPublisher<LemmyPersonInfo?, Never> in
                person.publisher(for: \.personInfo)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private var creatorName: AnyPublisher<String, Never> {
        creatorInfo
            .map { personInfo in
                personInfo?.name ?? ""
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

    private let postInfo: LemmyPostInfo

    private var appearance: PostDetailAppearanceType {
        appearanceService.postDetail
    }

    // MARK: Functions

    init(
        postInfo: LemmyPostInfo,
        dependencies: Dependencies
    ) {
        self.postInfo = postInfo
        self.dependencies = (own: dependencies, nested: dependencies)
    }
}
