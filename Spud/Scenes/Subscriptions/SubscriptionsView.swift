//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI

private extension Components.Schemas.ListingType {
    struct ItemForSubscriptions {
        let iconName: String
        let iconTint: Color
        let title: String
        let subtitle: String
    }

    var itemForSubscriptions: ItemForSubscriptions {
        switch self {
        case .Subscribed:
            return .init(
                iconName: "newspaper",
                iconTint: .red,
                title: "Subscribed",
                subtitle: "Posts from your subscriptions"
            )
        case .Local:
            return .init(
                iconName: "house",
                iconTint: .blue,
                title: "Local",
                subtitle: "Posts from your home instance"
            )
        case .All:
            return .init(
                iconName: "rectangle.stack",
                iconTint: .green,
                title: "All",
                subtitle: "Posts from all federated instances"
            )
        case .ModeratorView:
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
    @State var listingType: Components.Schemas.ListingType

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

struct SubscriptionsView: View {
    @Bindable var viewModel: SubscriptionsViewModel

    var body: some View {
        List {
            if viewModel.isSignedIn {
                SubscriptionsListingView(listingType: .Subscribed)
                    .onTapGesture {
                        viewModel.loadFeed(.listing(.Subscribed))
                    }
            }
            SubscriptionsListingView(listingType: .Local)
                .onTapGesture {
                    viewModel.loadFeed(.listing(.Local))
                }
            SubscriptionsListingView(listingType: .All)
                .onTapGesture {
                    viewModel.loadFeed(.listing(.All))
                }

            if !viewModel.followCommunities.isEmpty {
                Section("Subscribed communities") {
                    ForEach(viewModel.followCommunities) { community in
                        SubscriptionsCommunityView(community: community.name)
                            .onTapGesture {
                                viewModel.loadFeed(.community(community))
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
