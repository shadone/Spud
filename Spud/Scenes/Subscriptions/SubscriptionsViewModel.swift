//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit

protocol SubscriptionsViewModelInputs {
    func loadFeed(_ value: SubscriptionsViewItemType)
}

protocol SubscriptionsViewModelOutputs {
    var account: CurrentValueSubject<LemmyAccount, Never> { get }

    var isSignedIn: AnyPublisher<Bool, Never> { get }

    var feedRequested: AnyPublisher<LemmyFeed, Never> { get }
    var followCommunities: AnyPublisher<[LemmyCommunity], Never> { get }
}

protocol SubscriptionsViewModelType: ObservableObject {
    var inputs: SubscriptionsViewModelInputs { get }
    var outputs: SubscriptionsViewModelOutputs { get }
}

class SubscriptionsViewModel:
    SubscriptionsViewModelType,
    SubscriptionsViewModelInputs,
    SubscriptionsViewModelOutputs
{
    typealias OwnDependencies =
        HasAccountService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)

    var accountService: AccountServiceType { dependencies.own.accountService }

    // MARK: Private

    private var disposables = Set<AnyCancellable>()

    // MARK: Functions

    init(
        account: LemmyAccount,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)

        self.account = CurrentValueSubject<LemmyAccount, Never>(account)

        isSignedIn = self.account
            .map { !$0.isSignedOutAccountType }
            .eraseToAnyPublisher()

        feedRequested = loadFeedSubject
            .map { itemType in
                switch itemType {
                case let .listing(listingType):
                    dependencies.accountService
                        .lemmyService(for: account)
                        .createFeed(listingType: listingType)

                case let .community(communityInfo):
                    dependencies.accountService
                        .lemmyService(for: account)
                        .createFeed(.community(
                            communityName: communityInfo.name,
                            instance: communityInfo.instanceActorId,
                            sortType: .active
                        ))
                }
            }
            .eraseToAnyPublisher()

        followCommunities = self.account
            .flatMap { account -> AnyPublisher<LemmyAccountInfo?, Never> in
                account.publisher(for: \.accountInfo)
                    .eraseToAnyPublisher()
            }
            .ignoreNil()
            .flatMap { accountInfo in
                accountInfo.publisher(for: \.followCommunities)
                    .eraseToAnyPublisher()
            }
            .map {
                Array($0)
                    .sorted { lhs, rhs in
                        let left = lhs.communityInfo?.name ?? ""
                        let right = rhs.communityInfo?.name ?? ""
                        return left.caseInsensitiveCompare(right) == .orderedAscending
                    }
            }
            .eraseToAnyPublisher()
    }

    // MARK: Type

    var inputs: SubscriptionsViewModelInputs { self }
    var outputs: SubscriptionsViewModelOutputs { self }

    // MARK: Outputs

    let account: CurrentValueSubject<LemmyAccount, Never>
    let isSignedIn: AnyPublisher<Bool, Never>
    let feedRequested: AnyPublisher<LemmyFeed, Never>
    let followCommunities: AnyPublisher<[LemmyCommunity], Never>

    // MARK: Inputs

    var loadFeedSubject: PassthroughSubject<SubscriptionsViewItemType, Never> = .init()
    func loadFeed(_ value: SubscriptionsViewItemType) {
        loadFeedSubject.send(value)
    }
}
