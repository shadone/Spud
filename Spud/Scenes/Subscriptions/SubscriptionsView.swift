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

/// A row in the always-visible "About <instance>" section: one of the home
/// instance's classified meta communities (e.g. an announcements/general
/// community), with one-tap Favourite, Notify (new-posts follow), and — when
/// signed in — Subscribe. Layout mirrors `SubscriptionsCommunityView`.
///
/// Favourite and Notify are always available (both purely local, no server
/// call — see `CommunityNotifyLabel`'s doc comment for why `bell.badge`, not
/// `bell`); Subscribe is gated by `showsSubscribe` because an anonymous/
/// signed-out account has no server-side subscribe state to mutate
/// (`setSubscribed` would throw) — see `SubscriptionsView`'s call site, which
/// passes `viewModel.isSignedIn`. The Subscribe button's title/symbol come
/// from the centralized `CommunitySubscribeButtonLabel` (also used by
/// `CommunityHeaderView` / `SearchCommunityCell`) so this row can never show
/// different copy for the same persisted `CommunitySubscribedState`.
struct MetaCommunityAboutRow: View {
    let item: MetaCommunityListItem
    let showsSubscribe: Bool
    let isNotifying: Bool
    let onSubscribe: () -> Void
    let onFavorite: () -> Void
    let onNotify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SubscriptionsCommunityIconView(communityName: item.name)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title ?? item.name)
                        .lineLimit(1)
                        .foregroundStyle(Color(.label))
                    MetaCommunityBadge()
                }
                Text("c/\(item.name)")
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The name truncates to one line (above) so these trailing
            // controls always keep their natural size instead of being
            // squeezed into a hyphenated wrap.
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                item.isFavorite
                    ? Text("Unfavorite", comment: "Accessibility label to remove a meta community from favourites")
                    : Text("Favorite", comment: "Accessibility label to add a meta community to favourites")
            )

            // Always available (like Favourite): community follows are local,
            // independent of server-side subscribe state — shown even when
            // signed out.
            Button(action: onNotify) {
                Image(systemName: CommunityNotifyLabel.symbol(isNotifying: isNotifying))
                    .foregroundStyle(isNotifying ? Color.accentColor : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(
                isNotifying
                    ? Text("Stop notifying about new posts", comment: "Accessibility label to remove a community new-posts follow")
                    : Text("Notify about new posts", comment: "Accessibility label to follow a community for new-post notifications")
            )

            if showsSubscribe {
                // A manual capsule pill (padding + `.background(_:in: Capsule())`)
                // rather than `.buttonStyle(.bordered) + .buttonBorderShape(.capsule)`
                // — matches the pill pattern already used across Discover
                // (`DiscoverView.SubscribeButton`, `InstanceCommunitiesView` chips)
                // and sidesteps that button style's height ambiguity inside a
                // `List` row.
                Button(action: onSubscribe) {
                    HStack(spacing: 4) {
                        Image(systemName: CommunitySubscribeButtonLabel.symbol(for: item.subscribedState))
                            .font(.system(size: 11, weight: .bold))
                        Text(CommunitySubscribeButtonLabel.title(for: item.subscribedState))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(item.subscribedState.isSubscribed ? Color(.secondaryLabel) : Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        item.subscribedState.isSubscribed ? Color(.tertiarySystemFill) : Color.accentColor.opacity(0.14),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CommunitySubscribeButtonLabel.title(for: item.subscribedState))
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
            // Always-visible "About <instance>" section: the home instance's
            // classified meta communities (announcements/general etc.), with
            // one-tap Favourite/Subscribe. Shown even when signed out (a
            // signed-out/anonymous account still has a keychain id and can
            // browse + favourite; only Subscribe is gated below), and — like
            // the standard feeds — steps aside while search-filtering.
            if viewModel.searchText.isEmpty, !viewModel.metaCommunities.isEmpty {
                Section(viewModel.metaInstanceName.map { "About \($0)" } ?? "About this instance") {
                    ForEach(viewModel.metaCommunities.filter { $0.confidence == .high }) { item in
                        MetaCommunityAboutRow(
                            item: item,
                            showsSubscribe: viewModel.isSignedIn,
                            isNotifying: viewModel.notifyingCommunityIds.contains(item.id),
                            onSubscribe: { viewModel.toggleSubscribe(item) },
                            onFavorite: { viewModel.toggleFavorite(item) },
                            onNotify: { viewModel.toggleNotify(item) }
                        )
                    }

                    let lowConfidenceCommunities = viewModel.metaCommunities.filter { $0.confidence == .low }
                    if !lowConfidenceCommunities.isEmpty {
                        DisclosureGroup("More on this instance") {
                            ForEach(lowConfidenceCommunities) { item in
                                MetaCommunityAboutRow(
                                    item: item,
                                    showsSubscribe: viewModel.isSignedIn,
                                    isNotifying: viewModel.notifyingCommunityIds.contains(item.id),
                                    onSubscribe: { viewModel.toggleSubscribe(item) },
                                    onFavorite: { viewModel.toggleFavorite(item) },
                                    onNotify: { viewModel.toggleNotify(item) }
                                )
                            }
                        }
                    }
                }
            }

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
                                Button {
                                    viewModel.toggleNotify(for: community)
                                } label: {
                                    Label(
                                        CommunityNotifyLabel.title,
                                        systemImage: CommunityNotifyLabel.symbol(isNotifying: viewModel.isNotifying(community))
                                    )
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
