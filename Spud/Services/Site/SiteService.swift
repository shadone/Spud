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

private let logger = Logger(.siteService)

protocol SiteServiceType: AnyObject {
    func startService()

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

    func startService() {
        seedInitialSitesIfNeeded()
    }

    private func seedInitialSitesIfNeeded() {
        let suggestedInstancesActorIds: [String] = [
            "https://discuss.tchncs.de",
        ]

        let request: NSFetchRequest<Instance> = Instance.fetchRequest()
        request.predicate = NSPredicate(
            format: "actorId IN %@",
            suggestedInstancesActorIds
        )

        let existingInstances: [Instance]
        do {
            existingInstances = try dataStore.mainContext.fetch(request)
        } catch {
            logger.error("Failed to fetch instances: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
            return
        }

        let existingInstanceActorIds = existingInstances
            .map { $0.actorId }

        let instancesActorIdsToAdd = suggestedInstancesActorIds
            .filter {
                !existingInstanceActorIds.contains($0)
            }

        instancesActorIdsToAdd.forEach { actorId in
            let instance = Instance(
                actorId: actorId,
                in: dataStore.mainContext
            )

            _ = LemmySite(
                instance: instance,
                in: dataStore.mainContext
            )
        }

        dataStore.saveIfNeeded()
    }

    func allSites(in context: NSManagedObjectContext) -> [LemmySite] {
        let request: NSFetchRequest<LemmySite> = LemmySite.fetchRequest()
        do {
            return try context.fetch(request)
        } catch {
            logger.error("Failed to fetch all sites: \(error.localizedDescription, privacy: .public)")
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
            "https://pathofexile-discuss.com",
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

        let request: NSFetchRequest<Instance> = Instance.fetchRequest()
        request.predicate = NSPredicate(
            format: "actorId IN %@",
            suggestedNormalizedInstancesUrls
        )

        let existingInstances: [Instance]
        do {
            existingInstances = try dataStore.mainContext.fetch(request)
        } catch {
            logger.error("Failed to fetch instances: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
            return
        }

        let existingNormalizedInstanceUrls = existingInstances
            .map { $0.actorId }

        let instancesUrlsToAdd = suggestedNormalizedInstancesUrls
            .filter {
                !existingNormalizedInstanceUrls.contains($0)
            }

        instancesUrlsToAdd.forEach { normalizedInstanceUrl in
            let instance = Instance(
                actorId: normalizedInstanceUrl,
                in: dataStore.mainContext
            )

            _ = LemmySite(
                instance: instance,
                in: dataStore.mainContext
            )
        }

        dataStore.saveIfNeeded()
    }
}
