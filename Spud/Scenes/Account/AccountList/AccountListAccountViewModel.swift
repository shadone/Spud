//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import UIKit

class AccountListAccountViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        site
            .flatMap { site in
                site.publisher(for: \.normalizedInstanceUrl)
            }
            .map { normalizedInstanceUrl in
                URL(string: normalizedInstanceUrl)?.safeHost ?? ""
            }
            .combineLatest(titleAttributes)
            .map { description, attributes in
                AttributedString(description, attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString?, Never> {
        account.publisher(for: \.isSignedOutAccountType)
            .combineLatest(subtitleAttributes)
            .map { isSignedOutAccountType, attributes in
                guard isSignedOutAccountType else {
                    return nil
                }
                return NSAttributedString(
                    string: "signed out (anonymous browsing)",
                    attributes: attributes
                )
            }
            .eraseToAnyPublisher()
    }

    var defaultAccountAccessoryType: AnyPublisher<UITableViewCell.AccessoryType, Never> {
        account.publisher(for: \.isDefaultAccount)
            .map { isDefaultAccount in
                return isDefaultAccount ? .checkmark : .none
            }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private var titleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2 + textSizeAdjustment, weight: .medium),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private var subtitleAttributes: AnyPublisher<[NSAttributedString.Key: Any], Never> {
        Just(0)
            .map { textSizeAdjustment -> [NSAttributedString.Key: Any] in
                [
                    .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2 + textSizeAdjustment, weight: .regular),
                    .foregroundColor: UIColor.label,
                ]
            }
            .eraseToAnyPublisher()
    }

    private let account: LemmyAccount

    private var site: AnyPublisher<LemmySite, Never> {
        account.publisher(for: \.site)
            .eraseToAnyPublisher()
    }

    // MARK: Functions

    init(account: LemmyAccount) {
        self.account = account
    }
}
