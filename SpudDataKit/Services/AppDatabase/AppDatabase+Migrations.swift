//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import GRDB

extension AppDatabase {
    /// Versioned schema migrator.
    ///
    /// Append a new `migrator.registerMigration("vN_…")` for every schema
    /// change. Never edit a registered migration after it has shipped.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initialSchema") { db in
            try db.create(table: "instance") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("actorId", .text).notNull().unique()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime)
            }

            try db.create(table: "nodeInfo") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("instanceId", .integer)
                    .notNull()
                    .unique()
                    .references("instance", onDelete: .cascade)
                t.column("softwareName", .text).notNull()
                t.column("softwareVersion", .text).notNull()
                t.column("isOpenRegistrationsAllowed", .boolean).notNull().defaults(to: false)
                t.column("numberOfLocalPosts", .integer).notNull().defaults(to: 0)
                t.column("numberOfLocalComments", .integer).notNull().defaults(to: 0)
                t.column("numberOfUsersTotal", .integer).notNull().defaults(to: 0)
                t.column("numberOfUsersHalfYear", .integer).notNull().defaults(to: 0)
                t.column("numberOfUsersMonth", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "site") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("instanceId", .integer)
                    .notNull()
                    .unique()
                    .references("instance", onDelete: .cascade)
                t.column("name", .text)
                t.column("descriptionText", .text)
                t.column("sidebar", .text)
                t.column("legalInformation", .text)
                t.column("iconUrl", .text)
                t.column("bannerUrl", .text)
                t.column("version", .text)
                t.column("defaultPostListingType", .text)
                t.column("enableDownvotes", .boolean)
                t.column("enableNsfw", .boolean)
                t.column("numberOfPosts", .integer)
                t.column("numberOfComments", .integer)
                t.column("numberOfCommunities", .integer)
                t.column("numberOfUsers", .integer)
                t.column("numberOfUsersDay", .integer)
                t.column("numberOfUsersWeek", .integer)
                t.column("numberOfUsersMonth", .integer)
                t.column("numberOfUsersHalfYear", .integer)
                t.column("infoCreatedDate", .datetime)
                t.column("infoUpdatedDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "person") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer)
                    .notNull()
                    .references("site", onDelete: .cascade)
                t.column("personId", .integer).notNull()
                t.column("name", .text)
                t.column("displayName", .text)
                t.column("avatarUrl", .text)
                t.column("bannerUrl", .text)
                t.column("bio", .text)
                t.column("actorId", .text)
                t.column("matrixUserId", .text)
                t.column("isAdmin", .boolean).notNull().defaults(to: false)
                t.column("isBanned", .boolean).notNull().defaults(to: false)
                t.column("isBotAccount", .boolean).notNull().defaults(to: false)
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("isLocal", .boolean).notNull().defaults(to: false)
                t.column("numberOfPosts", .integer).notNull().defaults(to: 0)
                t.column("numberOfComments", .integer).notNull().defaults(to: 0)
                t.column("banExpires", .datetime)
                t.column("personCreatedDate", .datetime)
                t.column("personUpdatedDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["siteId", "personId"])
            }

            try db.create(table: "account") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("siteId", .integer)
                    .notNull()
                    .references("site", onDelete: .cascade)
                t.column("personId", .integer)
                    .references("person", onDelete: .setNull)
                t.column("accountKeychainId", .text).notNull().unique()
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("isServiceAccount", .boolean).notNull().defaults(to: false)
                t.column("isSignedOutAccountType", .boolean).notNull().defaults(to: false)
                t.column("localAccountId", .integer)
                t.column("email", .text)
                t.column("emailVerified", .boolean)
                t.column("acceptedApplication", .boolean)
                t.column("defaultListingType", .text)
                t.column("defaultSortType", .text)
                t.column("showAvatars", .boolean)
                t.column("showBotAccounts", .boolean)
                t.column("showNsfw", .boolean)
                t.column("showReadPosts", .boolean)
                t.column("showScores", .boolean)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "community") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer)
                    .notNull()
                    .references("account", onDelete: .cascade)
                t.column("communityId", .integer).notNull()
                t.column("name", .text)
                t.column("title", .text)
                t.column("actorId", .text)
                t.column("descriptionText", .text)
                t.column("iconUrl", .text)
                t.column("bannerUrl", .text)
                t.column("isHidden", .boolean).notNull().defaults(to: false)
                t.column("isLocal", .boolean).notNull().defaults(to: false)
                t.column("isNsfw", .boolean).notNull().defaults(to: false)
                t.column("isPostingRestrictedToMods", .boolean).notNull().defaults(to: false)
                t.column("isRemoved", .boolean).notNull().defaults(to: false)
                t.column("communityCreatedDate", .datetime)
                t.column("communityUpdatedDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["accountId", "communityId"])
            }

            try db.create(table: "accountFollowedCommunity") { t in
                t.column("accountId", .integer)
                    .notNull()
                    .references("account", onDelete: .cascade)
                t.column("communityId", .integer)
                    .notNull()
                    .references("community", onDelete: .cascade)
                t.primaryKey(["accountId", "communityId"])
            }

            try db.create(table: "post") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer)
                    .notNull()
                    .references("account", onDelete: .cascade)
                t.column("communityId", .integer)
                    .notNull()
                    .references("community", onDelete: .cascade)
                t.column("creatorId", .integer)
                    .notNull()
                    .references("person", onDelete: .cascade)
                t.column("postId", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text)
                t.column("url", .text)
                t.column("urlEmbedTitle", .text)
                t.column("urlEmbedDescription", .text)
                t.column("thumbnailUrl", .text)
                t.column("originalPostUrl", .text).notNull()
                t.column("score", .integer).notNull().defaults(to: 0)
                t.column("numberOfUpvotes", .integer).notNull().defaults(to: 0)
                t.column("numberOfDownvotes", .integer).notNull().defaults(to: 0)
                t.column("numberOfComments", .integer).notNull().defaults(to: 0)
                t.column("isRead", .boolean).notNull().defaults(to: false)
                // voteStatus: 1 = up, 0 = down, NULL = neutral.
                t.column("voteStatus", .integer)
                t.column("published", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["accountId", "postId"])
            }

            try db.create(table: "comment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("postId", .integer)
                    .notNull()
                    .references("post", onDelete: .cascade)
                t.column("creatorId", .integer)
                    .notNull()
                    .references("person", onDelete: .cascade)
                t.column("localCommentId", .integer).notNull()
                t.column("body", .text).notNull()
                t.column("score", .integer).notNull().defaults(to: 0)
                t.column("numberOfUpvotes", .integer).notNull().defaults(to: 0)
                t.column("numberOfDownvotes", .integer).notNull().defaults(to: 0)
                // voteStatus: 1 = up, 0 = down, NULL = neutral.
                t.column("voteStatus", .integer)
                t.column("originalCommentUrl", .text)
                t.column("published", .datetime).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.uniqueKey(["postId", "localCommentId"])
            }

            try db.create(table: "commentElement") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("postId", .integer)
                    .notNull()
                    .references("post", onDelete: .cascade)
                // Nullable: a "more" placeholder has no comment row.
                t.column("commentId", .integer)
                    .references("comment", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("depth", .integer).notNull().defaults(to: 0)
                t.column("sortType", .text).notNull()
                t.column("moreChildCount", .integer)
                t.column("moreParentId", .integer)
            }

            try db.create(table: "feed") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer)
                    .notNull()
                    .references("account", onDelete: .cascade)
                t.column("feedKey", .text).notNull().unique()
                t.column("frontpageListingType", .text)
                t.column("communityName", .text)
                t.column("communityInstanceActorId", .text)
                t.column("sortType", .text).notNull()
                t.column("identifierForDebugging", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "page") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("feedId", .integer)
                    .notNull()
                    .references("feed", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["feedId", "position"])
            }

            try db.create(table: "pageElement") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pageId", .integer)
                    .notNull()
                    .references("page", onDelete: .cascade)
                t.column("postId", .integer)
                    .notNull()
                    .references("post", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.uniqueKey(["pageId", "postId"])
            }
        }

        migrator.registerMigration("v2_savedFlag") { db in
            try db.alter(table: "post") { t in
                t.add(column: "isSaved", .boolean).notNull().defaults(to: false)
            }
            try db.alter(table: "comment") { t in
                t.add(column: "isSaved", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v3_feedSavedOnly") { db in
            try db.alter(table: "feed") { t in
                t.add(column: "savedOnly", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v4_communitySubscribedAndCounts") { db in
            try db.alter(table: "community") { t in
                // subscribedState stores the Lemmy SubscribedType raw value
                // ("Subscribed" / "NotSubscribed" / "Pending").
                t.add(column: "subscribedState", .text)
                    .notNull()
                    .defaults(to: "NotSubscribed")
                t.add(column: "numberOfSubscribers", .integer)
                    .notNull()
                    .defaults(to: 0)
                t.add(column: "numberOfPosts", .integer)
                    .notNull()
                    .defaults(to: 0)
                t.add(column: "numberOfComments", .integer)
                    .notNull()
                    .defaults(to: 0)
            }
        }

        migrator.registerMigration("v5_moderationStatusFields") { db in
            // Moderation / content-status flags carried by the Lemmy post and
            // comment objects. These drive the status badges (Removed, Locked,
            // Featured, Distinguished) and let mod actions toggle visibly.
            try db.alter(table: "post") { t in
                t.add(column: "isRemoved", .boolean).notNull().defaults(to: false)
                t.add(column: "isLocked", .boolean).notNull().defaults(to: false)
                t.add(column: "isFeaturedCommunity", .boolean).notNull().defaults(to: false)
                t.add(column: "isFeaturedLocal", .boolean).notNull().defaults(to: false)
                t.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
            }
            try db.alter(table: "comment") { t in
                t.add(column: "isRemoved", .boolean).notNull().defaults(to: false)
                t.add(column: "isDistinguished", .boolean).notNull().defaults(to: false)
                t.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
            }
        }

        return migrator
    }
}
