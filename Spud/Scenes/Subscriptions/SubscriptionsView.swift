//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

private extension ListingType {
    struct ItemForSubscriptions {
        let iconName: String
        let iconTint: Color
        let title: String
        let subtitle: String
    }

    var itemForSubscriptions: ItemForSubscriptions {
        switch self {
        case .subscribed:
            return .init(
                iconName: "newspaper",
                iconTint: .red,
                title: "Subscribed",
                subtitle: "Posts from your subscriptions"
            )
        case .local:
            return .init(
                iconName: "house",
                iconTint: .blue,
                title: "Local",
                subtitle: "Posts from your home instance"
            )
        case .all:
            return .init(
                iconName: "rectangle.stack",
                iconTint: .green,
                title: "All",
                subtitle: "Posts from all federated instances"
            )
        case .moderatorView:
            return .init(
                iconName: "crown",
                iconTint: .purple,
                title: "Moderator view",
                subtitle: "Content that you can moderate"
            )
        }
    }
}

struct SubscriptionsListingView: View {
    @State var listingType: ListingType

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: listingType.itemForSubscriptions.iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(listingType.itemForSubscriptions.iconTint)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text(listingType.itemForSubscriptions.title)
                    .foregroundStyle(Color(.label))
                Text(listingType.itemForSubscriptions.subtitle)
                    .foregroundStyle(Color(.secondaryLabel))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
    }
}

struct SubscriptionsCommunityIconView: View {
    @State var communityName: String

    var letter: String {
        communityName.first
            .map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        ZStack {
            Circle()
                .foregroundColor(.cyan)
                .frame(width: 32, height: 32)
            Text(letter)
        }
    }
}

struct SubscriptionsCommunityView: View {
    @State var community: String

    var body: some View {
        HStack(spacing: 16) {
            SubscriptionsCommunityIconView(communityName: community)
            Text(community)
                .foregroundStyle(Color(.label))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

struct SubscriptionsView<ViewModel>: View
    where ViewModel: SubscriptionsViewModelType
{
    @StateObject var viewModel: ViewModel

    @State var isSignedIn = false
    @State var followCommunities: [LemmyCommunity] = []

    var body: some View {
        List {
            if isSignedIn {
                SubscriptionsListingView(listingType: .subscribed)
                    .onTapGesture {
                        viewModel.inputs.loadFeed(.listing(.subscribed))
                    }
            }
            SubscriptionsListingView(listingType: .local)
                .onTapGesture {
                    viewModel.inputs.loadFeed(.listing(.local))
                }
            SubscriptionsListingView(listingType: .all)
                .onTapGesture {
                    viewModel.inputs.loadFeed(.listing(.all))
                }

            if !followCommunities.isEmpty {
                Section("Subscribed communities") {
                    ForEach(followCommunities) { community in
                        if let communityInfo = community.communityInfo {
                            SubscriptionsCommunityView(community: communityInfo.name)
                                .onTapGesture {
                                    viewModel.inputs.loadFeed(.community(communityInfo))
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onReceive(viewModel.outputs.isSignedIn) { value in
            isSignedIn = value
        }
        .onReceive(viewModel.outputs.followCommunities) { value in
            followCommunities = value
        }
    }
}

#Preview {
    class ViewModel:
        SubscriptionsViewModelType,
        SubscriptionsViewModelInputs,
        SubscriptionsViewModelOutputs
    {
        var inputs: SubscriptionsViewModelInputs { self }
        var outputs: SubscriptionsViewModelOutputs { self }

        // MARK: Inputs

        func loadFeed(_ value: SubscriptionsViewItemType) { }

        // MARK: Outputs

        var account: CurrentValueSubject<LemmyAccount, Never> = .init(
            LemmyAccount()
        )

        var isSignedIn: AnyPublisher<Bool, Never> = .just(true)

        var feedRequested: AnyPublisher<LemmyFeed, Never> = .empty(completeImmediately: false)

        var followCommunities: AnyPublisher<[LemmyCommunity], Never> = .just([])
    }

    return SubscriptionsView(viewModel: ViewModel())
}
