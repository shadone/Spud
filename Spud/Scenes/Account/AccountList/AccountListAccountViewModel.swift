//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import SpudDataKit
import UIKit

class AccountListAccountViewModel {
    // MARK: Public

    var title: AnyPublisher<AttributedString, Never> {
        instanceHostname
            .combineLatest(nickname, titleAttributes)
            .map { tuple in
                let description = tuple.0
                let nickname = tuple.1
                let attributes = tuple.2

                guard let nickname else {
                    return AttributedString(description, attributes: .init(attributes))
                }

                return AttributedString("\(nickname)@\(description)", attributes: .init(attributes))
            }
            .eraseToAnyPublisher()
    }

    var subtitle: AnyPublisher<NSAttributedString?, Never> {
        account.publisher(for: \.isSignedOutAccountType)
            .combineLatest(subtitleAttributes, email)
            .map { tuple in
                let isSignedOutAccountType = tuple.0
                let attributes = tuple.1
                let email = tuple.2

                guard !isSignedOutAccountType else {
                    return NSAttributedString(
                        string: "signed out (anonymous browsing)",
                        attributes: attributes
                    )
                }

                guard let email else {
                    return nil
                }

                return NSAttributedString(
                    string: email,
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

    private var instance: AnyPublisher<Instance, Never> {
        site
            .flatMap { site in
                site.publisher(for: \.instance)
            }
            .eraseToAnyPublisher()
    }

    private var instanceHostname: AnyPublisher<String, Never> {
        instance
            .flatMap { instance in
                instance.instanceHostnamePublisher
            }
            .eraseToAnyPublisher()
    }

    private var accountInfo: AnyPublisher<LemmyAccountInfo?, Never> {
        account.publisher(for: \.accountInfo)
            .eraseToAnyPublisher()
    }

    private var email: AnyPublisher<String?, Never> {
        accountInfo
            .flatMap { accountInfo -> AnyPublisher<String?, Never> in
                guard let accountInfo else {
                    return .just(nil)
                }
                return accountInfo.publisher(for: \.email)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private var person: AnyPublisher<LemmyPerson?, Never> {
        accountInfo
            .flatMap { accountInfo -> AnyPublisher<LemmyPerson?, Never> in
                guard let accountInfo else {
                    return .just(nil)
                }
                return accountInfo.publisher(for: \.person)
                    .wrapInOptional()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private var personInfo: AnyPublisher<LemmyPersonInfo?, Never> {
        person
            .flatMap { person -> AnyPublisher<LemmyPersonInfo?, Never> in
                guard let person else {
                    return .just(nil)
                }
                return person.publisher(for: \.personInfo)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private var nickname: AnyPublisher<String?, Never> {
        personInfo
            .flatMap { personInfo -> AnyPublisher<String?, Never> in
                guard let personInfo else {
                    return .just(nil)
                }
                return personInfo.publisher(for: \.name)
                    .wrapInOptional()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    // MARK: Functions

    init(account: LemmyAccount) {
        self.account = account
    }
}
