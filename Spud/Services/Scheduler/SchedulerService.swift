//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import os.log
import LemmyKit

protocol SchedulerServiceType {
    func startService()
    func processNewSite(_ site: LemmySite)
}

protocol HasSchedulerService {
    var schedulerService: SchedulerServiceType { get }
}

class SchedulerService: SchedulerServiceType {
    // MARK: Private

    private let dataStore: DataStoreType
    private let accountService: AccountServiceType
    private let siteService: SiteServiceType

    private var timer: Timer?
    private var disposables = Set<AnyCancellable>()

    private var mainContext: NSManagedObjectContext {
        dataStore.mainContext
    }

    private lazy var backgroundContext: NSManagedObjectContext = {
        let backgroundContext = dataStore.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        return backgroundContext
    }()

    private lazy var backgroundScheduler: ManagedContextSchedulerOf<DispatchQueue> = {
        DispatchQueue.managedContentScheduler(backgroundContext)
    }()

    // MARK: Functions

    init(
        dataStore: DataStoreType,
        accountService: AccountServiceType,
        siteService: SiteServiceType
    ) {
        self.dataStore = dataStore
        self.accountService = accountService
        self.siteService = siteService
    }

    func startService() {
        let fiveMinutes: TimeInterval = 300
        timer = Timer.scheduledTimer(withTimeInterval: fiveMinutes, repeats: true) { [weak self] _ in
            // Periodically check if there is anything new needs to be fetched.
            self?.fetchSubscribedCommunitiesIfNeeded()
            self?.fetchSiteInfoForSignedOutIfNeeded()
        }

        // Trigger an extra check soon after app launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.timer?.fire()
        }
    }

    private func saveIfNeeded() {
        assert(Thread.current.isMainThread)
        backgroundContext.performAndWait {
            backgroundContext.saveIfNeeded()
        }
    }

    func processNewSite(_ site: LemmySite) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.fetchSiteInfo(for: site)
        }
    }

    // MARK: Site Info

    private func fetchSiteInfo(for site: LemmySite) {
        os_log("Fetching site info for %{public}@",
               log: .schedulerService, type: .info,
               site.identifierForLogging)

        // TODO: separate fetching of generic "site info" and account specific info
        // For now we fetch site info as signed out user only,
        // but better would be to fetch site info for each account (to fetch subscriptions)
        // and also extract generic site info from server response.

        let account = accountService.accountForSignedOut(
            at: site,
            isServiceAccount: true,
            in: backgroundContext
        )
        accountService
            .lemmyService(for: account)
            .fetchSiteInfo()
            .sink { _ in } receiveValue: { _ in }
            .store(in: &disposables)
    }

    private func fetchSiteInfo(for account: LemmyAccount) {
        assert(Thread.current.isMainThread)

        os_log("Fetching site info for %{public}@",
               log: .schedulerService, type: .info,
               account.identifierForLogging)

        accountService
            .lemmyService(for: account)
            .fetchSiteInfo()
            .sink { _ in } receiveValue: { _ in }
            .store(in: &disposables)
    }

    private func fetchSiteInfoForSignedOutIfNeeded() {
        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for signed out accounts (signed in accounts site info will be fetched
        // together with subscribed communities).
        accountService
            .allSignedOut(in: backgroundContext)
            .filter { $0.site.siteInfo == nil }
            .forEach { [weak self] account in
                self?.fetchSiteInfo(for: account)
            }

        // Fetch initial site info, i.e. sites that have never fetched corresponding site info.
        // But only for sites that we do have any account for (not even signed out).
        siteService
            .allSites(in: backgroundContext)
            .filter { $0.siteInfo == nil && $0.accounts.isEmpty }
            .forEach { [weak self] site in
                self?.fetchSiteInfo(for: site)
            }

        // TODO: Also periodically re-fetch Site info for sites that we do not have a local account for?
    }

    // MARK: Subscribed communities

    private func fetchSubscribedCommunitiesIfNeeded() {
        // TODO: periodically fetch subscribed communities
        // get a list of signed in accounts, check if the data is older than X days and fetch.
    }
}
