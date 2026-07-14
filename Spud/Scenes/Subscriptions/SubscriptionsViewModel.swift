//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit
import SpudUtilKit

private let logger = Logger.app

/// View model for SubscriptionsView. Holds plain @Observable state populated
/// from `appDatabase.observeFollowedCommunities`. Feed selection is delivered
/// to the controller through the `onFeedRequested` callback passed at init —
/// the model itself never touches LemmyDataService.
@MainActor
@Observable
final class SubscriptionsViewModel {
    /// How the subscribed-communities list is ordered. (Topic grouping was
    /// dropped: inferring a topic reliably needs an LLM and mis-groups.)
    enum SortOrder: CaseIterable, Equatable {
        case alphabetical
        case byInstance
    }

    let isSignedIn: Bool
    var followCommunities: [SubscriptionsCommunityRow] = []

    /// Community actor ids the active account has favorited. Updated live from
    /// `observeFavoritedCommunityActorIds`; folded into the rows so favorites
    /// pin to the top and show a star.
    var favoriteActorIds: Set<String> = []

    /// Live filter text from the search bar.
    var searchText: String = ""
    /// Active ordering for the community list.
    var sortOrder: SortOrder = .alphabetical

    /// The subscribed communities after applying the search filter and the
    /// active sort, with favorites pinned to the top. Favorited rows come first
    /// (sorted among themselves by the active sort), then the rest. Drives the
    /// list so search / sort / favorites stay purely client-side.
    var displayedCommunities: [SubscriptionsCommunityRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let flagged = followCommunities.map { row -> SubscriptionsCommunityRow in
            var row = row
            row.isFavorite = favoriteActorIds.contains(row.communityActorId)
            return row
        }
        let filtered = query.isEmpty
            ? flagged
            : flagged.filter {
                $0.name.lowercased().contains(query)
                    || $0.instanceActorId.host.lowercased().contains(query)
            }

        let sorted = filtered.sorted(by: ordering)
        // Stable partition: favorites first, preserving the active sort within
        // each group.
        return sorted.filter(\.isFavorite) + sorted.filter { !$0.isFavorite }
    }

    /// The active-sort comparator, shared by `displayedCommunities` so favorites
    /// and non-favorites order consistently.
    private func ordering(_ lhs: SubscriptionsCommunityRow, _ rhs: SubscriptionsCommunityRow) -> Bool {
        switch sortOrder {
        case .alphabetical:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .byInstance:
            if lhs.instanceActorId.host != rhs.instanceActorId.host {
                return lhs.instanceActorId.host.localizedCaseInsensitiveCompare(rhs.instanceActorId.host) == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private let onFeedRequested: (SubscriptionsViewItemType) -> Void
    private let onExploreRequested: () -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var favoritesObservationTask: Task<Void, Never>?

    init(
        accountRowId: Int64?,
        isSignedIn: Bool,
        appDatabase: AppDatabase,
        onFeedRequested: @escaping (SubscriptionsViewItemType) -> Void,
        onExploreRequested: @escaping () -> Void
    ) {
        self.isSignedIn = isSignedIn
        self.onFeedRequested = onFeedRequested
        self.onExploreRequested = onExploreRequested

        guard let accountRowId else { return }

        observationTask = Task { [weak self] in
            for await communities in appDatabase.observeFollowedCommunities(forAccountId: accountRowId) {
                if Task.isCancelled { break }
                let rows = communities.compactMap(Self.makeRow)
                await MainActor.run { self?.followCommunities = rows }
            }
        }

        favoritesObservationTask = Task { [weak self] in
            for await actorIds in appDatabase.observeFavoritedCommunityActorIds(forAccountId: accountRowId) {
                if Task.isCancelled { break }
                await MainActor.run { self?.favoriteActorIds = actorIds }
            }
        }
    }

    deinit {
        observationTask?.cancel()
        favoritesObservationTask?.cancel()
    }

    func loadFeed(_ value: SubscriptionsViewItemType) {
        onFeedRequested(value)
    }

    /// Open the Discover (Community Explorer) screen.
    func explore() {
        onExploreRequested()
    }

    /// Builds a row from a persisted `CommunityRecord`, including the "meta"
    /// classification. Internal (not `private`) so it can be exercised directly
    /// from tests without going through the observation pipeline.
    static func makeRow(from record: CommunityRecord) -> SubscriptionsCommunityRow? {
        guard
            let id = record.id,
            let name = record.name,
            let actorIdString = record.actorId,
            let url = URL(string: actorIdString),
            let instance = InstanceActorId(from: url)
        else { return nil }

        let isMeta = MetaCommunityClassifier.classify(
            name: name,
            title: record.title,
            instanceHost: instance.host,
            siteName: nil
        ).isMeta

        return SubscriptionsCommunityRow(
            id: id,
            name: name,
            instanceActorId: instance,
            communityActorId: actorIdString,
            isMeta: isMeta
        )
    }
}
