//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Down
import OSLog
import SpudDataKit
import UIKit

private let logger = Logger.app

@MainActor
class PostDetailCommentViewModel {
    typealias OwnDependencies =
        HasAppearanceService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var appearanceService: AppearanceServiceType { dependencies.own.appearanceService }

    // MARK: Public

    var author: AnyPublisher<NSAttributedString, Never> {
        creator
            .combineLatest(authorAttributes)
            .map { tuple in
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
    }

    var body: AnyPublisher<NSAttributedString, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }

        return commentValue
            .publisher(for: \.body)
            .combineLatest(appearance.bodyStylerConfiguration)
            .map { text, stylerConfiguration in
                Down(markdownString: text)
                    .toAttributedString(styler: DownStyler(configuration: stylerConfiguration))
            }
            .eraseToAnyPublisher()
    }

    var moreText: AnyPublisher<NSAttributedString, Never> {
        commentElement.publisher(for: \.moreChildCount)
            .ignoreNil()
            .combineLatest(moreTextAttributes)
            .map { numberOfReplies, attributes in
                // TODO: use NSLocalizedString thingie for pluralizing string.
                if numberOfReplies == 1 {
                    return NSAttributedString(string: "1 more reply", attributes: attributes)
                } else {
                    return NSAttributedString(string: "\(numberOfReplies) more replies", attributes: attributes)
                }
            }
            .eraseToAnyPublisher()
    }

    var isTopLevelComment: Bool {
        commentElement.depth == 0
    }

    private let indentationRibbonStandardWidth: CGFloat = 2

    var indentationRibbonWidth: AnyPublisher<CGFloat, Never> {
        commentElement.publisher(for: \.depth)
            .map { indentationLevel in
                indentationLevel == 1 ? 0 : self.indentationRibbonStandardWidth
            }
            .eraseToAnyPublisher()
    }

    var indentationRibbonLeadingMargin: AnyPublisher<CGFloat, Never> {
        let leadingMargin: CGFloat = 4
        return commentElement.publisher(for: \.depth)
            .map { indentationLevel in
                (self.indentationRibbonStandardWidth + 4) * CGFloat(indentationLevel - 1) + leadingMargin
            }
            .eraseToAnyPublisher()
    }

    var indentationRibbonColor: AnyPublisher<UIColor, Never> {
        commentElement.publisher(for: \.depth)
            .combineLatest(appearance.commentRibbonThemePublisher)
            .map { indentationLevel, theme in
                let colors = theme.colors
                let index = max(0, Int(indentationLevel - 1) % colors.count)
                return colors[index]
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }

        let upvotes = commentValue
            .publisher(for: \.score)
            .combineLatest(commentValue.voteStatusPublisher, secondaryAttributes)
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
        let age = commentValue
            .publisher(for: \.published)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(relativeDate: $0, attributes: $1) }
            .eraseToAnyPublisher()
        let space = Just("  ")
            .combineLatest(secondaryAttributes)
            .map { NSAttributedString(string: $0, attributes: $1) }
            .eraseToAnyPublisher()

        return Just(NSAttributedString())
            .combineLatest([
                upvotes,
                space,
                age,
            ])
            .map { $0.joined() }
            .eraseToAnyPublisher()
    }

//    var voteStatusPublisher: AnyPublisher<VoteStatus, Never> {
//        guard let commentValue else {
//            return .empty(completeImmediately: false)
//        }
//
//        return commentValue.voteStatusPublisher
//    }
//
//    var isUpvoted: AnyPublisher<Bool, Never> {
//        guard let commentValue else {
//            return .empty(completeImmediately: false)
//        }
//
//        return commentValue
//            .publisher(for: \.voteStatus.isUp)
//            .eraseToAnyPublisher()
//    }
//
//    var isDownvoted: AnyPublisher<Bool, Never> {
//        guard let commentValue else {
//            return .empty(completeImmediately: false)
//        }
//
//        return commentValue
//            .publisher(for: \.voteStatus.isDown)
//            .eraseToAnyPublisher()
//    }

    // MARK: Private

    private var authorAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: textSizeAdjustment,
                        weight: .medium
                    ),
                ]
            }
            .eraseToAnyPublisher()
    }

    private var bodyAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: textSizeAdjustment,
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

    private var moreTextAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        appearance.textSizeAdjustmentPublisher
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.scaledSystemFont(
                        style: .body,
                        relativeSize: -1 + textSizeAdjustment,
                        weight: .regular
                    ),
                    .foregroundColor: UIColor.link,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var creator: AnyPublisher<LemmyPerson, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }

        return commentValue.publisher(for: \.creator)
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

    private let post: LemmyPost
    private let commentElement: LemmyCommentElement
    private let commentValue: LemmyComment?

    private var appearance: PostDetailAppearanceType {
        appearanceService.postDetail
    }

    // MARK: Functions

    init(
        comment commentElement: LemmyCommentElement,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.commentElement = commentElement
        commentValue = commentElement.comment
        post = commentElement.post
    }
}
