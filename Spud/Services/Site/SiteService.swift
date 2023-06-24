//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import os.log
import LemmyKit

protocol SiteServiceType: AnyObject {
    func site(for instanceUrl: URL) -> LemmySite?
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
            let site = LemmySite(context: dataStore.mainContext)
            site.normalizedInstanceUrl = normalizedInstanceUrlString
            site.createdAt = Date()
            dataStore.saveIfNeeded()
            return site
        }

        return site ?? createSite()
    }
}
