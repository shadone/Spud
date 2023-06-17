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

    var body: AnyPublisher<AttributedString, Never> {
        post.publisher(for: \.body)
            .map { AttributedString($0 ?? "") }
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

    // MARK: Functions

    init(post: LemmyPost) {
        self.post = post
    }
}
