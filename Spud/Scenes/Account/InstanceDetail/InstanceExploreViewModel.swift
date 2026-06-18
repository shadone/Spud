//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Observation
import SpudDataKit
import SpudUtilKit

/// State + actions for the in-app instance explore screen.
/// Identity/stats/health come from `record`; sidebar/admins are fetched live;
/// communities come from the bundled directory; Join federates through the
/// browsing account.
@MainActor
@Observable
final class InstanceExploreViewModel {
    let record: ExplorerInstanceRecord

    /// The browsing account this scene operates as.
    var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    private(set) var sidebar: String?
    private(set) var adminsState: InstanceAdminsState = .loading
    private(set) var communities: [CommunityListRow] = []
    private(set) var joinedCommunityUrls: Set<String> = []

    @ObservationIgnored
    let accountScope: AccountScope
    @ObservationIgnored
    private let accountService: AccountServiceType
    private let appDatabase: AppDatabase
    private let alertService: AlertServiceType

    var instance: InstanceActorId? {
        InstanceActorId(from: record.url ?? "https://\(record.baseurl)")
    }

    var isSignedOut: Bool {
        accountScope.isSignedOut
    }

    private nonisolated(unsafe) var tasks: [Task<Void, Never>] = []

    init(
        record: ExplorerInstanceRecord,
        accountScope: AccountScope,
        accountService: AccountServiceType,
        appDatabase: AppDatabase,
        alertService: AlertServiceType,
        initialJoinedCommunityUrls: Set<String> = []
    ) {
        self.record = record
        self.accountScope = accountScope
        self.accountService = accountService
        self.appDatabase = appDatabase
        self.alertService = alertService
        let derived = appDatabase.followedCommunityActorIdsSync(forAccountKeychainId: accountScope.accountKeychainId)
        joinedCommunityUrls = initialJoinedCommunityUrls.union(derived)
    }

    func load() {
        cancelLoad()

        // Communities (synchronous directory snapshot).
        let allRows = appDatabase.explorerCommunityListRowsSync()
        communities = ExplorerCommunityDirectory.communities(
            onInstance: record.baseurl,
            in: allRows,
            sort: .members
        )

        guard let instance else {
            adminsState = .unavailable
            return
        }

        // Synchronous cache-first reads so the initial layout shows seeded data
        // without waiting for the async network refresh.
        let cachedAdmins = appDatabase.siteAdminsSync(forInstanceActorId: instance)
        adminsState = cachedAdmins.isEmpty
            ? (record.isSuspicious ? .anonymous : .unavailable)
            : .admins(cachedAdmins)
        if let value = appDatabase.siteSidebarSync(forInstanceActorId: instance), !value.isEmpty {
            sidebar = value
        }

        let accountService = accountService
        let appDatabase = appDatabase
        let isSuspicious = record.isSuspicious

        // Trigger a signed-out site fetch (sidebar + admins), then observe.
        tasks.append(Task { @MainActor [weak self] in
            let keychainId = accountService.accountForSignedOut(
                forInstance: instance,
                isServiceAccount: true
            )
            let service = accountService.scope(forAccountKeychainId: keychainId).lemmyService
            try? await service.fetchSiteInfo()

            guard !Task.isCancelled else { return }

            for await admins in appDatabase.observeSiteAdmins(forInstanceActorId: instance) {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                adminsState = admins.isEmpty
                    ? (isSuspicious ? .anonymous : .unavailable)
                    : .admins(admins)
            }
        })

        tasks.append(Task { @MainActor [weak self] in
            for await _ in appDatabase.observeAllSites() {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if let value = appDatabase.siteSidebarSync(forInstanceActorId: instance), !value.isEmpty {
                    sidebar = value
                }
            }
        })
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    func cancelLoad() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Toggle Join for a community via the browsing account's home instance.
    /// Returns the resulting joined state (so the row can settle), or throws.
    func toggleJoin(_ row: CommunityListRow) async throws -> Bool {
        let service = accountScope.lemmyService
        let wantJoined = !joinedCommunityUrls.contains(row.communityUrl)
        let id = try await service.fetchCommunityInfo(communityName: "\(row.name)@\(row.instanceHost)")
        try await service.setSubscribed(serverCommunityId: id, subscribed: wantJoined)
        if wantJoined { joinedCommunityUrls.insert(row.communityUrl) }
        else { joinedCommunityUrls.remove(row.communityUrl) }
        return wantJoined
    }
}
