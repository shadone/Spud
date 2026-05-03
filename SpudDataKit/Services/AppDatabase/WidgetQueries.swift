//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB
import LemmyKit
import OSLog
import SpudUtilKit

private let logger = Logger.appDatabase

/// Snapshot row for the home-screen widget. Joins post + community +
/// account → site → instance so the widget can render entries without going
/// back through Core Data.
public struct WidgetPostRow: Sendable, Equatable {
    public let serverPostId: Int64
    public let title: String
    public let thumbnailUrl: String?
    public let communityName: String
    public let communityInstanceHost: String
    public let accountInstanceActorId: String
    public let score: Int64
    public let numberOfComments: Int64
}

public extension AppDatabase {
    /// Returns the top N posts on the first page of `feedKey`, in display
    /// order. Used by the widget snapshot pipeline.
    func widgetTopPosts(feedKey: String, limit: Int) async throws -> [WidgetPostRow] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                    SELECT
                        post.postId               AS serverPostId,
                        post.title                AS title,
                        post.thumbnailUrl         AS thumbnailUrl,
                        post.score                AS score,
                        post.numberOfComments     AS numberOfComments,
                        community.name            AS communityName,
                        community.actorId         AS communityActorId,
                        accountInstance.actorId   AS accountInstanceActorId
                    FROM feed
                    JOIN page         ON page.feedId = feed.id
                    JOIN pageElement  ON pageElement.pageId = page.id
                    JOIN post         ON post.id = pageElement.postId
                    JOIN community    ON community.id = post.communityId
                    JOIN account      ON account.id = feed.accountId
                    JOIN site         AS accountSite     ON accountSite.id = account.siteId
                    JOIN instance     AS accountInstance ON accountInstance.id = accountSite.instanceId
                    WHERE feed.feedKey = ?
                    ORDER BY page.position ASC, pageElement.position ASC
                    LIMIT ?
                """, arguments: [feedKey, limit])

            return rows.map { row in
                let communityActorId: String? = row["communityActorId"]
                let communityHost: String = {
                    guard
                        let actorIdString = communityActorId,
                        let url = URL(string: actorIdString),
                        let instance = InstanceActorId(from: url)
                    else { return "" }
                    return instance.host
                }()

                return WidgetPostRow(
                    serverPostId: row["serverPostId"],
                    title: row["title"],
                    thumbnailUrl: row["thumbnailUrl"],
                    communityName: row["communityName"] ?? "",
                    communityInstanceHost: communityHost,
                    accountInstanceActorId: row["accountInstanceActorId"],
                    score: row["score"],
                    numberOfComments: row["numberOfComments"]
                )
            }
        }
    }
}
