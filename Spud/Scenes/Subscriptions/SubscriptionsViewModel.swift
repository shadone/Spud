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

    /// Live filter text from the search bar.
    var searchText: String = ""
    /// Active ordering for the community list.
    var sortOrder: SortOrder = .alphabetical

    /// The subscribed communities after applying the search filter and the
    /// active sort. Drives the list so search / sort stay purely client-side.
    var displayedCommunities: [SubscriptionsCommunityRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty
            ? followCommunities
            : followCommunities.filter {
                $0.name.lowercased().contains(query)
                    || $0.instanceActorId.host.lowercased().contains(query)
            }

        switch sortOrder {
        case .alphabetical:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .byInstance:
            return filtered.sorted {
                if $0.instanceActorId.host != $1.instanceActorId.host {
                    return $0.instanceActorId.host.localizedCaseInsensitiveCompare($1.instanceActorId.host) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private let onFeedRequested: (SubscriptionsViewItemType) -> Void
    private let onExploreRequested: () -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

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
    }

    deinit {
        observationTask?.cancel()
    }

    func loadFeed(_ value: SubscriptionsViewItemType) {
        onFeedRequested(value)
    }

    /// Open the Discover (Community Explorer) screen.
    func explore() {
        onExploreRequested()
    }

    private static func makeRow(from record: CommunityRecord) -> SubscriptionsCommunityRow? {
        guard
            let id = record.id,
            let name = record.name,
            let actorIdString = record.actorId,
            let url = URL(string: actorIdString),
            let instance = InstanceActorId(from: url)
        else { return nil }

        return SubscriptionsCommunityRow(
            id: id,
            name: name,
            instanceActorId: instance
        )
    }
}
