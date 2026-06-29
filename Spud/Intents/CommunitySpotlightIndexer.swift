//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreSpotlight
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Indexes the default account's subscribed communities into Spotlight so they
/// surface in system search and open via `OpenCommunityAppIntent`. Best-effort:
/// re-run on launch and on foreground to keep the index roughly current with
/// subscription changes.
enum CommunitySpotlightIndexer {
    static func reindex(appDatabase: AppDatabase, diagnostics: DiagnosticLogging) {
        Task {
            let entities = appDatabase.followedCommunitiesForDefaultAccountSync()
                .compactMap(CommunityAppEntity.init(record:))
            do {
                try await CSSearchableIndex.default().indexAppEntities(entities)
                await diagnostics.record(
                    category: .spotlight,
                    level: .debug,
                    event: "reindex.finish",
                    message: "Community Spotlight index updated",
                    instance: nil,
                    metadata: ["count": String(entities.count)]
                )
            } catch {
                logger.error("Spotlight community indexing failed: \(error.localizedDescription, privacy: .public)")
                await diagnostics.record(
                    category: .spotlight,
                    level: .error,
                    event: "reindex.failed",
                    message: "Community Spotlight indexing failed",
                    instance: nil,
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
    }
}
