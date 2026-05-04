//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudUtilKit

private let logger = Logger.schedulerService

@MainActor
public protocol SchedulerServiceType {
    func startService()
}

@MainActor
public protocol HasSchedulerService {
    var schedulerService: SchedulerServiceType { get }
}

@MainActor
public class SchedulerService: SchedulerServiceType {
    // MARK: Private

    private let appDatabase: AppDatabase
    private let accountService: AccountServiceType
    private let alertService: AlertServiceType

    private var timer: Timer?

    // MARK: Functions

    public init(
        appDatabase: AppDatabase,
        accountService: AccountServiceType,
        alertService: AlertServiceType
    ) {
        self.appDatabase = appDatabase
        self.accountService = accountService
        self.alertService = alertService
    }

    public func startService() {
        let fiveMinutes: TimeInterval = 300
        timer = Timer.scheduledTimer(withTimeInterval: fiveMinutes, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Periodically check if there is anything new needs to be fetched.
                await self.fetchSiteInfoAndMyUserInfoForSignedInIfNeeded()
                await self.fetchSiteInfoForSignedOutIfNeeded()
            }
        }

        // Trigger an extra check soon after app launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.timer?.fire()
        }
    }

    // MARK: Site Info

    private func fetchSiteInfo(forInstance actorId: InstanceActorId) async {
        logger.info("Fetching site info for \(actorId.actorId, privacy: .public)")

        // TODO: separate fetching of generic "site info" and account specific info
        // For now we fetch site info as signed out user only,
        // but better would be to fetch site info for each account (to fetch subscriptions)
        // and also extract generic site info from server response.

        let keychainId = accountService.accountForSignedOut(
            forInstance: actorId,
            isServiceAccount: true
        )

        await fetchSiteInfo(forAccountKeychainId: keychainId)
    }

    private func fetchSiteInfo(forAccountKeychainId keychainId: String) async {
        do {
            try await accountService
                .lemmyService(forAccountKeychainId: keychainId)
                .fetchSiteInfo()
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
        }
    }

    private func fetchSiteInfoForSignedOutIfNeeded() async {
        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for signed out accounts (signed in accounts site info will be fetched
        // together with subscribed communities).
        let signedOutKeychainIds: [String]
        do {
            signedOutKeychainIds = try await appDatabase.signedOutAccountsAwaitingSiteInfo()
        } catch {
            logger.error("Failed to query signed-out accounts awaiting site info: \(String(describing: error), privacy: .public)")
            signedOutKeychainIds = []
        }
        for keychainId in signedOutKeychainIds {
            await fetchSiteInfo(forAccountKeychainId: keychainId)
        }

        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for sites that we do not have any account for (not even signed out).
        let ownerlessActorIds: [InstanceActorId]
        do {
            ownerlessActorIds = try await appDatabase.ownerlessSitesAwaitingInfo()
        } catch {
            logger.error("Failed to query ownerless sites: \(String(describing: error), privacy: .public)")
            ownerlessActorIds = []
        }
        for actorId in ownerlessActorIds {
            await fetchSiteInfo(forInstance: actorId)
        }

        // TODO: Also periodically re-fetch Site info for sites that we do not have a local account for?
    }

    // MARK: Subscribed communities

    /// For signed in accounts periodically re-fetch user info e.g. list of subscribed communities.
    private func fetchSiteInfoAndMyUserInfoForSignedInIfNeeded() async {
        // Fetch initial site info (which includes `MyUserInfo`) for new accounts
        // that we never fetched it before.
        let initialKeychainIds: [String]
        do {
            initialKeychainIds = try await appDatabase.signedInAccountsAwaitingMyUserInfo()
        } catch {
            logger.error("Failed to query signed-in accounts awaiting MyUserInfo: \(String(describing: error), privacy: .public)")
            initialKeychainIds = []
        }
        for keychainId in initialKeychainIds {
            await fetchSiteInfo(forAccountKeychainId: keychainId)
        }

        // Re-fetch info periodically. Check if the data is older than 1 day and fetch.
        let oneDay: TimeInterval = 24 * 60 * 60
        let cutoff = Date().addingTimeInterval(-oneDay)
        let staleKeychainIds: [String]
        do {
            staleKeychainIds = try await appDatabase.signedInAccountsStale(updatedBefore: cutoff)
        } catch {
            logger.error("Failed to query stale signed-in accounts: \(String(describing: error), privacy: .public)")
            staleKeychainIds = []
        }
        for keychainId in staleKeychainIds {
            await fetchSiteInfo(forAccountKeychainId: keychainId)
        }
    }
}
