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

    /// The home instance's classified "meta" (about-the-instance) communities,
    /// live from `AppDatabase.observeMetaCommunities`. Drives the always-visible
    /// "About <instance>" section.
    var metaCommunities: [MetaCommunityListItem] = []
    /// Host of the home instance, shown as the "About <host>" section header.
    /// `nil` when there's no account scope (signed-out preview) or the scope's
    /// instance can't be resolved.
    var metaInstanceName: String?

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
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private let accountScope: AccountScope?
    @ObservationIgnored
    private let metaCommunityService: MetaCommunityServiceType?
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    private var favoritesObservationTask: Task<Void, Never>?
    @ObservationIgnored
    private var metaObservationTask: Task<Void, Never>?

    init(
        accountRowId: Int64?,
        isSignedIn: Bool,
        appDatabase: AppDatabase,
        accountScope: AccountScope?,
        metaCommunityService: MetaCommunityServiceType?,
        onFeedRequested: @escaping (SubscriptionsViewItemType) -> Void,
        onExploreRequested: @escaping () -> Void
    ) {
        self.isSignedIn = isSignedIn
        self.appDatabase = appDatabase
        self.accountScope = accountScope
        self.metaCommunityService = metaCommunityService
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

        if let scope = accountScope, let host = scope.instanceActorId?.hostWithPort {
            metaInstanceName = scope.instanceActorId?.host

            metaObservationTask = Task { [weak self] in
                for await items in appDatabase.observeMetaCommunities(forAccountId: accountRowId, instanceHost: host) {
                    if Task.isCancelled { break }
                    await MainActor.run { self?.metaCommunities = items }
                }
            }

            // Trigger a refresh exactly once per view-model lifetime. The
            // service self-throttles against its freshness window, so this is
            // NOT re-triggered on every screen appearance.
            let keychainId = scope.accountKeychainId
            Task { [metaCommunityService] in
                await metaCommunityService?.refreshInstance(host: host, siteName: nil, forAccountKeychainId: keychainId)
            }
        }
    }

    deinit {
        observationTask?.cancel()
        favoritesObservationTask?.cancel()
        metaObservationTask?.cancel()
    }

    func loadFeed(_ value: SubscriptionsViewItemType) {
        onFeedRequested(value)
    }

    /// Open the Discover (Community Explorer) screen.
    func explore() {
        onExploreRequested()
    }

    /// Toggles the server-side subscribe state for a meta community. Routed
    /// through the account's `LemmyService`, which durably queues the mutation
    /// in the outbox (`try?` here — the outbox owns retry/rollback, so the view
    /// model doesn't need to surface a synchronous failure). The observation
    /// re-emits once the optimistic mirror lands.
    func toggleSubscribe(_ item: MetaCommunityListItem) {
        guard let scope = accountScope else { return }
        let subscribe = !item.subscribedState.isSubscribed
        Task {
            try? await scope.lemmyService.setSubscribed(
                serverCommunityId: Lemmy.CommunityID(item.serverCommunityId), subscribed: subscribe
            )
        }
    }

    /// Toggles the local favourite flag for a meta community. Purely local
    /// (the favourites table has no server counterpart); the observation
    /// re-emits immediately since the write lands synchronously.
    func toggleFavorite(_ item: MetaCommunityListItem) {
        guard let keychainId = accountScope?.accountKeychainId else { return }
        if item.isFavorite {
            appDatabase.unfavoriteCommunitySync(forKeychainId: keychainId, communityActorId: item.communityActorId)
        } else {
            appDatabase.favoriteCommunitySync(forKeychainId: keychainId, communityActorId: item.communityActorId)
        }
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
