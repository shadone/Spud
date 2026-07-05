//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

// MARK: - Safety (block / report)

public extension LemmyService {
    func setBlocked(
        serverPersonId: Components.Schemas.PersonID,
        blocked: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Block person rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                personId=\(serverPersonId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set blocked=\(blocked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            personId=\(serverPersonId, privacy: .public)
            """)

        let response: Components.Schemas.BlockPersonResponse
        do {
            response = try await api.blockPerson(personID: serverPersonId, block: blocked)
        } catch {
            logger.error("""
                Block person failed. personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the refreshed author info. The server now filters this author's
        // content out of subsequent feed fetches; the caller refreshes the feed.
        await mirrorPersonInfoToAppDatabase(view: response.person_view)
    }

    func setBlocked(
        serverCommunityId: Components.Schemas.CommunityID,
        blocked: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Block community rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set blocked=\(blocked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public)
            """)

        let response: Components.Schemas.BlockCommunityResponse
        do {
            response = try await api.blockCommunity(communityID: serverCommunityId, block: blocked)
        } catch {
            logger.error("""
                Block community failed. communityId=\(serverCommunityId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the refreshed community info. The server now filters this
        // community's content out of subsequent feed fetches; the caller
        // refreshes the feed.
        await mirrorCommunityInfoToAppDatabase(view: response.community_view)
    }

    internal func mirrorPersonInfoToAppDatabase(
        view: Components.Schemas.PersonView
    ) async {
        do {
            guard let (_, siteRowId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPerson(from: view, siteId: siteRowId)
        } catch {
            logger.error("AppDatabase upsertPerson failed: \(String(describing: error), privacy: .public)")
        }
    }

    func reportPost(
        serverPostId: Components.Schemas.PostID,
        reason: String
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Report post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Report post for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        do {
            _ = try await api.createPostReport(postID: serverPostId, reason: reason)
        } catch {
            logger.error("""
                Report post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func reportComment(
        serverCommentId: Components.Schemas.CommentID,
        reason: String
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Report comment rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(serverCommentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Report comment for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        do {
            _ = try await api.createCommentReport(commentID: serverCommentId, reason: reason)
        } catch {
            logger.error("""
                Report comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }
    }

    func fetchBlockedList() async throws -> BlockedList {
        guard !accountIsSignedOut else {
            logger.debug("""
                Fetch blocked list rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("Fetch blocked list for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))")

        let response: Components.Schemas.GetSiteResponse
        do {
            response = try await api.getSite()
        } catch {
            logger.error("""
                Fetch blocked list failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        guard let myUser = response.my_user else {
            return .empty
        }

        let persons = myUser.person_blocks.map { block -> BlockedList.Person in
            let target = block.target
            return BlockedList.Person(
                serverPersonId: target.id,
                name: target.name,
                handle: Self.handle(name: target.name, actorId: target.actor_id),
                avatarUrl: target.avatar.flatMap(URL.init(string:))
            )
        }

        let communities = myUser.community_blocks.map { block -> BlockedList.Community in
            let community = block.community
            return BlockedList.Community(
                serverCommunityId: community.id,
                name: community.name,
                handle: Self.handle(name: community.name, actorId: community.actor_id),
                iconUrl: community.icon.flatMap(URL.init(string:))
            )
        }

        return BlockedList(persons: persons, communities: communities)
    }

    /// Builds a `name@instance` handle from a bare name and the federated
    /// `actor_id` url (e.g. `https://lemmy.world/u/alice` -> `alice@lemmy.world`).
    /// Falls back to the bare name if the host can't be resolved.
    private static func handle(name: String, actorId: String) -> String {
        guard
            let url = URL(string: actorId),
            let host = url.host
        else {
            return name
        }
        return "\(name)@\(host)"
    }

    func fetchPostInfo(
        serverPostId: Components.Schemas.PostID
    ) async throws {
        logger.debug("""
            Fetch post. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.GetPostResponse
        do {
            response = try await api.getPost(id: serverPostId)
        } catch {
            logger.error("""
                Fetch post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            if ContentNotFound.matchesPost(error) {
                try? await appDatabase.markPostUnavailable(
                    forKeychainId: accountIdentifierForLogging,
                    serverPostId: Int64(serverPostId)
                )
            }
            throw LemmyServiceError(from: error)
        }

        logger.debug("""
            Fetch post complete. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        await mirrorPostInfoToAppDatabase(view: response.post_view)

        guard appDatabase.postRowIdSync(
            forKeychainId: accountIdentifierForLogging,
            serverPostId: Int64(serverPostId)
        ) != nil else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchPostInfo: post row not persisted after mirror for postId=\(serverPostId)"
            )
        }

        // getPost also returns the cross-posts as full PostViews, so harvest
        // their counters too — keeps any cross-post we already cache fresh
        // without a separate fetch. Best-effort: a cross-post is incidental and
        // must not affect the primary post's persistence contract above.
        await mirrorPostViewsToAppDatabase(views: response.cross_posts)
    }

    internal func mirrorPostInfoToAppDatabase(
        view: Components.Schemas.PostView
    ) async {
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertPost(
                from: view,
                accountId: accountRowId,
                siteId: siteRowId
            )
        } catch {
            logger.error("AppDatabase upsertPost failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Best-effort harvest of incidental PostViews (e.g. a post's cross-posts)
    /// so their counters stay fresh without an extra fetch. Each is upserted
    /// like any other post; a failure is logged and the rest are skipped.
    internal func mirrorPostViewsToAppDatabase(
        views: [Components.Schemas.PostView]
    ) async {
        guard !views.isEmpty else { return }
        do {
            guard let (accountRowId, siteRowId) = try await accountSiteIds() else {
                return
            }
            try await appDatabase.upsertPosts(
                from: views,
                accountId: accountRowId,
                siteId: siteRowId
            )
        } catch {
            logger.error("AppDatabase upsertPost (cross-posts) failed: \(String(describing: error), privacy: .public)")
        }
    }

    func hidePost(
        serverPostId: Components.Schemas.PostID,
        hidden: Bool
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Hide post rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(serverPostId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set hidden=\(hidden, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        guard let outbox = await outboxService() else {
            throw LemmyServiceError.internalInconsistency(description: "outbox unavailable")
        }
        await outbox.enqueue(OutboxOperation(
            entityType: .post,
            entityServerId: Int64(serverPostId),
            desiredState: .hide(hidden)
        ))
    }

    func outboxFailureEvents() async -> AsyncStream<OutboxFailure> {
        guard let outbox = await outboxService() else {
            return AsyncStream { $0.finish() }
        }
        return await outbox.failureEvents
    }

    func drainPendingOutbox() async {
        let service = await outboxService()
        if let service {
            await service.drainAll()
        } else {
            // The outbox service could not be built (account/site not yet mirrored).
            // If the account has pending operations we can't drain, record a durable
            // error so operators can identify stuck outbox rows without needing to
            // attach a debugger.
            guard let ids = try? await accountSiteIds(),
                  let pending = try? await appDatabase.allOutboxOperations(accountId: ids.0),
                  !pending.isEmpty
            else { return }

            let instanceHost = await resolveInstanceHost()
            await DiagnosticLog(appDatabase: appDatabase).record(
                category: .outbox,
                level: .error,
                event: "drain.skippedNoService",
                message: "drainPendingOutbox: outbox service unavailable, \(pending.count) pending operation(s) skipped",
                instance: instanceHost,
                metadata: ["pendingCount": String(pending.count)]
            )
        }
    }
}
