//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreSpotlight
import Foundation
import OSLog
import SpudDataKit
import SpudUtilKit
import UniformTypeIdentifiers

private let logger = Logger.app

/// Indexes the default account's saved + recently-opened posts into Spotlight,
/// under a dedicated `content` domain (kept separate from the community index).
/// Each item's identifier is the canonical routing URL, so a tap funnels through
/// `SceneDelegate.scene(_:continue:)` -> `AppCoordinator.open` like any deep
/// link. Best-effort: re-run on launch and on foreground.
enum ContentSpotlightIndexer {
    static let domainIdentifier = "content"
    static let limit = 100

    static func reindex(appDatabase: AppDatabase) {
        Task {
            let rows = appDatabase.indexableContentRowsForDefaultAccountSync(limit: limit)
            let items = rows.compactMap(makeItem(from:))
            do {
                let index = CSSearchableIndex.default()
                // Reset the domain first so unsaved / aged-out items don't linger.
                try await index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier])
                try await index.indexSearchableItems(items)
            } catch {
                logger.error("Spotlight content indexing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pure mapping from a content row to a Spotlight item. nil when no canonical
    /// URL can be built (so the item would not be routable).
    static func makeItem(from row: IndexableContentRow) -> CSSearchableItem? {
        guard let canonical = LinkURL.forPost(
            instance: .originalInstance,
            originalPostUrl: row.originalPostUrl,
            serverPostId: row.serverPostId,
            instanceActorId: nil
        ) else { return nil }
        let routingURL = URL.SpudInternalLink.objectAtURL(url: canonical).url
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = row.title
        if let communityName = row.communityName {
            attributes.contentDescription = "!\(communityName)"
        }
        if let thumb = row.thumbnailUrl, let thumbURL = URL(string: thumb) {
            attributes.thumbnailURL = thumbURL
        }
        return CSSearchableItem(
            uniqueIdentifier: routingURL.absoluteString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
