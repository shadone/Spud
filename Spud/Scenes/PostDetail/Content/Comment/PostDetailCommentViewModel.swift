//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import UIKit

class PostDetailCommentViewModel {
    // MARK: Public

    var author: AnyPublisher<NSAttributedString, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }
        return commentValue
            .publisher(for: \.creatorName)
            .combineLatest(authorAttributes)
            .map { tuple in
                let title = tuple.0
                let attributes = tuple.1

                return NSAttributedString(string: title, attributes: attributes)
            }
            .eraseToAnyPublisher()
    }

    var body: AnyPublisher<NSAttributedString, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }

        return commentValue
            .publisher(for: \.body)
            .map { text in
                return NSAttributedString(string: text)
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

    let indentationRibbonWidth: CGFloat = 2

    var indentationRibbonLeadingMargin: AnyPublisher<CGFloat, Never> {
        let leadingMargin: CGFloat = 4
        return commentElement.publisher(for: \.depth)
            .map { indentationLevel in
                (self.indentationRibbonWidth + 4) * CGFloat(indentationLevel) + leadingMargin
            }
            .eraseToAnyPublisher()
    }

    var indentationRibbonColor: AnyPublisher<UIColor, Never> {
        commentElement.publisher(for: \.depth)
            .combineLatest(appearance.commentRibbonThemePublisher)
            .map { indentationLevel, theme in
                let colors = theme.colors
                return colors[Int(indentationLevel) % colors.count]
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString, Never> {
        guard let commentValue else {
            return .empty(completeImmediately: false)
        }

        let upvotes = commentValue
            .publisher(for: \.numberOfUpvotes)
            .combineLatest(secondaryAttributes)
            .map { IconValueFormatter.attributedString(numberOfUpvotes: $0, attributes: $1) }
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
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment, weight: .medium),
                ]
            }
            .eraseToAnyPublisher()
    }

    private var bodyAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment, weight: .regular),
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

    private var moreTextAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 1 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.link,
                ]
            }
            .eraseToAnyPublisher()
    }

    private let post: LemmyPost
    private let commentElement: LemmyCommentElement
    private let commentValue: LemmyComment?

    private let appearance: PostDetailAppearanceType

    // MARK: Functions

    init(
        comment commentElement: LemmyCommentElement,
        appearance: PostDetailAppearanceType
    ) {
        self.appearance = appearance
        self.commentElement = commentElement
        commentValue = commentElement.comment
        post = commentElement.post
    }
}
