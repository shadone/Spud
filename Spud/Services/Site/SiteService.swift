//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Combine
import Foundation
import os.log
import LemmyKit

protocol SiteServiceType: AnyObject {
    func site(for instanceUrl: URL) -> LemmySite?

    /// Returns all sites that we know of. The returned sites are fetched in the specified context.
    func allSites(in context: NSManagedObjectContext) -> [LemmySite]

    /// Populate the Core Data storage with a list of popular Lemmy instances that user can log in to.
    func populateSiteListWithSuggestedInstancesIfNeeded()
}

protocol HasSiteService {
    var siteService: SiteServiceType { get }
}

class SiteService: SiteServiceType {
    // MARK: Private

    private let dataStore: DataStoreType

    // MARK: Functions

    init(
        dataStore: DataStoreType
    ) {
        self.dataStore = dataStore
    }

    func site(for instanceUrl: URL) -> LemmySite? {
        guard let normalizedInstanceUrlString = instanceUrl.normalizedInstanceUrlString else {
            return nil
        }

        let site: LemmySite? = {
            let request: NSFetchRequest<LemmySite> = LemmySite.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "normalizedInstanceUrl == %@",
                normalizedInstanceUrlString
            )
            do {
                let sites = try dataStore.mainContext.fetch(request)
                if sites.count > 1 {
                    os_log("Expected zero or one but found %{public}d sites instead! instanceUrl=%{public}@",
                           log: .siteService, type: .error,
                           sites.count, instanceUrl.absoluteString)
                    assertionFailure()
                }
                return sites.first
            } catch {
                os_log("Failed to fetch site '%{public}@': %{public}@",
                       log: .siteService, type: .error,
                       instanceUrl.absoluteString,
                       error.localizedDescription)
                assertionFailure()
                return nil
            }
        }()

        func createSite() -> LemmySite {
            let site = LemmySite(
                normalizedInstanceUrl: normalizedInstanceUrlString,
                in: dataStore.mainContext
            )
            dataStore.saveIfNeeded()
            return site
        }

        return site ?? createSite()
    }

    func allSites(in context: NSManagedObjectContext) -> [LemmySite] {
        let request: NSFetchRequest<LemmySite> = LemmySite.fetchRequest()
        do {
            return try context.fetch(request)
        } catch {
            os_log("Failed to fetch all sites: %{public}@",
                   log: .siteService, type: .error,
                   error.localizedDescription)
            assertionFailure()
            return []
        }
    }

    func populateSiteListWithSuggestedInstancesIfNeeded() {
        let suggestedNormalizedInstancesUrls: [String] = [
            "https://lemmy.world",
            "https://sopuli.xyz",
            "https://reddthat.com",
            "https://sh.itjust.works",
            "https://vlemmy.net",
            "https://lemmy.fmhy.ml",
            "https://lemm.ee",
            "https://beehaw.org",
            "https://feddit.de",
            "https://lemmy.one",
            "https://lemmy.ca",
            "https://lemmy.blahaj.zone",
            "https://lemmy.dbzer0.com",
            "https://lemmy.sdf.org",
            "https://programming.dev",
            "https://feddit.it",
            "https://startrek.website",
            "https://infosec.pub",
            "https://feddit.uk",
            "https://feddit.nl",
            "https://dormi.zone",
            "https://lemmy.nz",
            "https://lemmy.zip",
            "https://szmer.info",
            "https://iusearchlinux.fyi",
            "https://slrpnk.net",
            "https://feddit.dk",
            "https://latte.isnot.coffee",
            "https://pathofexile-discuss.com",
            "https://dataterm.digital",
            "https://monyet.cc",
            "https://geddit.social",
            "https://sub.wetshaving.social",
            "https://monero.town",
            "https://lemmyrs.org",
            "https://waveform.social",
            "https://feddit.cl",
            "https://lemmy.pt",
            "https://lemmy.eus",
            "https://lm.korako.me",
        ]
            .map { URL(string: $0)! }
            .map { $0.normalizedInstanceUrlString! }

        let request: NSFetchRequest<LemmySite> = LemmySite.fetchRequest()
        request.predicate = NSPredicate(
            format: "normalizedInstanceUrl IN %@",
            suggestedNormalizedInstancesUrls
        )

        let existingSites: [LemmySite]
        do {
            existingSites = try dataStore.mainContext.fetch(request)
        } catch {
            os_log("Failed to fetch sites: %{public}@",
                   log: .siteService, type: .error,
                   error.localizedDescription)
            assertionFailure()
            return
        }

        let existingNormalizedInstanceUrls = existingSites
            .map { $0.normalizedInstanceUrl }

        let instancesUrlsToAdd = suggestedNormalizedInstancesUrls
            .filter {
                !existingNormalizedInstanceUrls.contains($0)
            }

        instancesUrlsToAdd.forEach { normalizedInstanceUrl in
            _ = LemmySite(
                normalizedInstanceUrl: normalizedInstanceUrl,
                in: dataStore.mainContext
            )
        }

        dataStore.saveIfNeeded()
    }
}
