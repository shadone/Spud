//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import CoreData
import Foundation
import LemmyKit
import os.log
import SpudUtilKit

private let logger = Logger(.siteService)

public protocol SiteServiceType: AnyObject {
    func startService()

    /// Returns all sites that we know of. The returned sites are fetched in the specified context.
    func allSites(in context: NSManagedObjectContext) -> [LemmySite]

    /// Populate the Core Data storage with a list of popular Lemmy instances that user can log in to.
    func populateSiteListWithSuggestedInstancesIfNeeded()

    /// Returns a Lemmy site for the given instance hostname.
    func site(
        for instance: InstanceActorId,
        in context: NSManagedObjectContext
    ) -> LemmySite
}

public protocol HasSiteService {
    var siteService: SiteServiceType { get }
}

public class SiteService: SiteServiceType {
    // MARK: Private

    private let dataStore: DataStoreType

    // MARK: Functions

    public init(
        dataStore: DataStoreType
    ) {
        self.dataStore = dataStore
    }

    public func startService() {
        seedInitialSitesIfNeeded()
    }

    private func seedInitialSitesIfNeeded() {
        let suggestedInstancesActorIds: [InstanceActorId] = [
            "https://discuss.tchncs.de",
        ].map { stringValue in
            guard let instanceActorId = InstanceActorId(from: stringValue) else {
                fatalError("Failed to parse static hard coded string '\(stringValue)'")
            }
            return instanceActorId
        }

        let request: NSFetchRequest<Instance> = Instance.fetchRequest()
        request.predicate = NSPredicate(
            format: "actorIdRawValue IN %@",
            suggestedInstancesActorIds.map(\.actorId)
        )

        let existingInstances: [Instance]
        do {
            existingInstances = try dataStore.mainContext.fetch(request)
        } catch {
            logger.assertionFailure("Failed to fetch instances: \(error.localizedDescription)")
            return
        }

        let existingInstanceActorIds = existingInstances
            .map(\.actorId)

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

    public func allSites(in context: NSManagedObjectContext) -> [LemmySite] {
        let request: NSFetchRequest<LemmySite> = LemmySite.fetchRequest()
        do {
            return try context.fetch(request)
        } catch {
            logger.assertionFailure("Failed to fetch all sites: \(error.localizedDescription)")
            return []
        }
    }

    public func populateSiteListWithSuggestedInstancesIfNeeded() {
        let suggestedInstances: [InstanceActorId] = [
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
        .map { stringValue in
            guard let instanceActorId = InstanceActorId(from: stringValue) else {
                fatalError("Failed to parse static hard coded string '\(stringValue)'")
            }
            return instanceActorId
        }

        let request: NSFetchRequest<Instance> = Instance.fetchRequest()
        request.predicate = NSPredicate(
            format: "actorIdRawValue IN %@",
            suggestedInstances.map(\.actorId)
        )

        let existingInstances: [Instance]
        do {
            existingInstances = try dataStore.mainContext.fetch(request)
        } catch {
            logger.assertionFailure("Failed to fetch instances: \(error.localizedDescription)")
            return
        }

        let existingNormalizedInstanceUrls = existingInstances
            .map(\.actorId)

        let instancesToAdd = suggestedInstances
            .filter {
                !existingNormalizedInstanceUrls.contains($0)
            }

        instancesToAdd.forEach { instanceActorId in
            let instance = Instance(
                actorId: instanceActorId,
                in: dataStore.mainContext
            )

            _ = LemmySite(
                instance: instance,
                in: dataStore.mainContext
            )
        }

        dataStore.saveIfNeeded()
    }

    public func site(
        for instance: InstanceActorId,
        in context: NSManagedObjectContext
    ) -> LemmySite {
        assert(Thread.current.isMainThread)

        let existingInstance: Instance? = {
            let request: NSFetchRequest<Instance> = Instance.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(
                format: "actorIdRawValue == %@",
                instance.actorId
            )
            do {
                let instances = try context.fetch(request)
                logger.assert(instances.count <= 1, """
                    Expected zero or one but found \(instances.count) \
                    instances for \(instance)!
                    """)
                return instances.first
            } catch {
                logger.assertionFailure("""
                    Failed to fetch instance for \(instance): \
                    \(error.localizedDescription)
                    """)
                return nil
            }
        }()

        if let instance = existingInstance {
            if let site = instance.site {
                return site
            }

            // TODO: check if it's a Lemmy instance via instance.nodeInfo?.softwareName

            let site = LemmySite(instance: instance, in: context)
            return site
        }

        let instance = Instance(actorId: instance, in: context)
        let site = LemmySite(instance: instance, in: context)

        context.saveIfNeeded()

        return site
    }
}
