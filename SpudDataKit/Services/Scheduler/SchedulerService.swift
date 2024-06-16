//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import OSLog

private let logger = Logger(.schedulerService)

public protocol SchedulerServiceType {
    func startService()
    func processNewSite(_ site: LemmySite)
}

@MainActor
public protocol HasSchedulerService {
    var schedulerService: SchedulerServiceType { get }
}

@MainActor
public class SchedulerService: SchedulerServiceType {
    // MARK: Private

    private let dataStore: DataStoreType
    private let accountService: AccountServiceType
    private let siteService: SiteServiceType
    private let alertService: AlertServiceType

    private var timer: Timer?
    private var disposables = Set<AnyCancellable>()

    private var mainContext: NSManagedObjectContext {
        dataStore.mainContext
    }

    // MARK: Functions

    public init(
        dataStore: DataStoreType,
        accountService: AccountServiceType,
        siteService: SiteServiceType,
        alertService: AlertServiceType
    ) {
        self.dataStore = dataStore
        self.accountService = accountService
        self.siteService = siteService
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

    public func processNewSite(_ site: LemmySite) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                await self.fetchSiteInfo(for: site)
            }
        }
    }

    // MARK: Site Info

    private func fetchSiteInfo(for site: LemmySite) async {
        logger.info("Fetching site info for \(site.identifierForLogging, privacy: .public)")

        // TODO: separate fetching of generic "site info" and account specific info
        // For now we fetch site info as signed out user only,
        // but better would be to fetch site info for each account (to fetch subscriptions)
        // and also extract generic site info from server response.

        let account = accountService.accountForSignedOut(
            at: site,
            isServiceAccount: true,
            in: mainContext
        )

        do {
            try await accountService
                .lemmyService(for: account)
                .fetchSiteInfo()
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
        }
    }

    private func fetchSiteInfo(for account: LemmyAccount) async {
        logger.info("Fetching site info for \(account.identifierForLogging, privacy: .public)")

        do {
            try await accountService
                .lemmyService(for: account)
                .fetchSiteInfo()
        } catch {
            alertService.handle(error, for: .fetchSiteInfo)
        }
    }

    private func fetchSiteInfoForSignedOutIfNeeded() async {
        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for signed out accounts (signed in accounts site info will be fetched
        // together with subscribed communities).
        let accountsToUpdate = accountService
            .allSignedOut(in: mainContext)
            .filter { $0.site.siteInfo == nil }
        for account in accountsToUpdate {
            await fetchSiteInfo(for: account)
        }

        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for sites that we do have any account for (not even signed out).
        let sitesToUpdate = siteService
            .allSites(in: mainContext)
            .filter { $0.siteInfo == nil && $0.accounts.isEmpty }
        for site in sitesToUpdate {
            await fetchSiteInfo(for: site)
        }

        // TODO: Also periodically re-fetch Site info for sites that we do not have a local account for?
    }

    // MARK: Subscribed communities

    /// For signed in accounts periodically re-fetch user info e.g. list of subscribed communities.
    private func fetchSiteInfoAndMyUserInfoForSignedInIfNeeded() async {
        let allSignedInAccounts = accountService
            .allAccounts(includeSignedOutAccount: false, in: mainContext)

        let accountsToFetchInitialInfo = allSignedInAccounts
            .filter { $0.accountInfo == nil }

        // Fetch initial site info (which includes `MyUserInfo`) for new accounts
        // that we never fetched it before.
        for account in accountsToFetchInitialInfo {
            await fetchSiteInfo(for: account)
        }

        // Re-fetch info periodically. Check if the data is older than 1 day and fetch.
        let oneDay: TimeInterval = 24 * 60 * 60
        let accountsToUpdateInfo = allSignedInAccounts
            .filter { $0.accountInfo != nil }
            .filter { account in
                let now = Date()
                let age = now.timeIntervalSince(account.updatedAt)
                return age > oneDay
            }
        for account in accountsToUpdateInfo {
            await fetchSiteInfo(for: account)
        }
    }
}
