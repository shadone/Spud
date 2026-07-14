//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SwiftUI
import UIKit

private extension Lemmy.ListingType {
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
    @State var listingType: Lemmy.ListingType

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

struct SubscriptionsSavedView: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "bookmark")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text("Saved")
                    .foregroundStyle(Color(.label))
                Text("Posts you have saved")
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
    let row: SubscriptionsCommunityRow

    var body: some View {
        HStack(spacing: 16) {
            SubscriptionsCommunityIconView(communityName: row.name)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .foregroundStyle(Color(.label))
                    if row.isMeta {
                        MetaCommunityBadge()
                    }
                }
                // The instance handle stays quiet, like the feed cell.
                Text("@\(row.instanceActorId.host)")
                    .foregroundStyle(Color(.tertiaryLabel))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.isFavorite {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favorite", comment: "Accessibility label for the favorited-community star"))
            }
        }
        .contentShape(Rectangle())
    }
}

/// Entry point into the Discover (Community Explorer) screen, sitting above the
/// subscribed feeds.
struct SubscriptionsDiscoverView: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkle.magnifyingglass")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.teal)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading) {
                Text("Discover communities")
                    .foregroundStyle(Color(.label))
                Text("Find new communities across the fediverse")
                    .foregroundStyle(Color(.secondaryLabel))
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
    }
}

struct SubscriptionsView: View {
    @Bindable var viewModel: SubscriptionsViewModel

    var body: some View {
        List {
            // The standard feeds are navigation, not search results, so they
            // step aside while the user is filtering communities.
            if viewModel.searchText.isEmpty {
                SubscriptionsDiscoverView()
                    .onTapGesture {
                        viewModel.explore()
                    }

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

                if viewModel.isSignedIn {
                    SubscriptionsSavedView()
                        .onTapGesture {
                            viewModel.loadFeed(.saved)
                        }
                }
            }

            if !viewModel.displayedCommunities.isEmpty {
                Section("Subscribed communities") {
                    ForEach(viewModel.displayedCommunities) { community in
                        SubscriptionsCommunityView(row: community)
                            .onTapGesture {
                                viewModel.loadFeed(.community(community))
                            }
                            .contextMenu {
                                Button {
                                    viewModel.loadFeed(.community(community))
                                } label: {
                                    Label("Open", systemImage: "arrow.up.forward")
                                }
                                if let url = community.shareURL {
                                    Button {
                                        UIPasteboard.general.url = url
                                    } label: {
                                        Label("Copy link", systemImage: "doc.on.doc")
                                    }
                                    ShareLink(item: url) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                    }
                }
            } else if !viewModel.searchText.isEmpty {
                Section("Subscribed communities") {
                    Text("No subscribed communities match your search.")
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
