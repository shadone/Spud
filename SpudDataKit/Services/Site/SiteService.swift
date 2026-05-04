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

    /// Populate AppDatabase with a list of popular Lemmy instances that user
    /// can log in to. Idempotent; safe to call repeatedly.
    func populateSiteListWithSuggestedInstancesIfNeeded()
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

    private static let suggestedInstanceActorIds: [InstanceActorId] = [
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

    private func seedInitialSitesIfNeeded() {
        ensureSites(Self.initialSeedActorIds)
    }

    public func populateSiteListWithSuggestedInstancesIfNeeded() {
        ensureSites(Self.suggestedInstanceActorIds)
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
