//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudUtilKit

private let logger = Logger.siteService

public protocol SiteServiceType: AnyObject {
    func startService()
}

@MainActor
public protocol HasSiteService {
    var siteService: SiteServiceType { get }
}

public class SiteService: SiteServiceType {
    // MARK: Private

    private let appDatabase: AppDatabase

    // MARK: Functions

    public init(
        appDatabase: AppDatabase
    ) {
        self.appDatabase = appDatabase
    }

    public func startService() {
        seedInitialSitesIfNeeded()
    }

    private static let initialSeedActorIds: [InstanceActorId] = [
        "https://discuss.tchncs.de",
    ].map { stringValue in
        guard let instanceActorId = InstanceActorId(from: stringValue) else {
            fatalError("Failed to parse static hard coded string '\(stringValue)'")
        }
        return instanceActorId
    }

    private func seedInitialSitesIfNeeded() {
        ensureSites(Self.initialSeedActorIds)
    }

    private func ensureSites(_ actorIds: [InstanceActorId]) {
        Task { [appDatabase] in
            for actorId in actorIds {
                do {
                    _ = try await appDatabase.ensureSite(forInstance: actorId)
                } catch {
                    logger.error("""
                        Failed to ensure site for \(actorId.actorId, privacy: .public): \
                        \(String(describing: error), privacy: .public)
                        """)
                }
            }
        }
    }
}
