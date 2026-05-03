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
    let isSignedIn: Bool
    var followCommunities: [SubscriptionsCommunityRow] = []

    private let onFeedRequested: (SubscriptionsViewItemType) -> Void
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(
        accountRowId: Int64?,
        isSignedIn: Bool,
        appDatabase: AppDatabase,
        onFeedRequested: @escaping (SubscriptionsViewItemType) -> Void
    ) {
        self.isSignedIn = isSignedIn
        self.onFeedRequested = onFeedRequested

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
