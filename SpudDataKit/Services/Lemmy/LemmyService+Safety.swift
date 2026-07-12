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

/// Safety actions: block person/community, report post/comment, hide post, and read the blocked list.
public extension LemmyService {
    func setBlocked(
        serverPersonId: Lemmy.PersonID,
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

        let view: Lemmy.PersonView
        do {
            view = try await api.blockPersonNeutral(id: Int64(serverPersonId), block: blocked)
        } catch {
            logger.error("""
                Block person failed. personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Mirror the refreshed author info. The server now filters this author's
        // content out of subsequent feed fetches; the caller refreshes the feed.
        await mirrorPersonInfoToAppDatabase(view: view)
    }

    func setBlocked(
        serverCommunityId: Lemmy.CommunityID,
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

        let view: Lemmy.CommunityView
        do {
            view = try await api.blockCommunityNeutral(id: Int64(serverCommunityId), block: blocked)
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
        await mirrorCommunityInfoToAppDatabase(view: view)
    }

    internal func mirrorPersonInfoToAppDatabase(
        view: Lemmy.PersonView
    ) async {
        do {
            guard let (_, siteRowId) = try await accountSiteIds() else { return }
            try await appDatabase.upsertPerson(from: view, siteId: siteRowId)
        } catch {
            logger.error("AppDatabase upsertPerson failed: \(String(describing: error), privacy: .public)")
        }
    }

    func reportPost(
        serverPostId: Lemmy.PostID,
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
        serverCommentId: Lemmy.CommentID,
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

        let response: Lemmy.GetSiteResponse
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
        serverPostId: Lemmy.PostID
    ) async throws {
        logger.debug("""
            Fetch post. account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let detail: PostDetail
        do {
            detail = try await api.getPostNeutral(id: Int64(serverPostId))
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

        await mirrorPostInfoToAppDatabase(view: detail.post)

        guard appDatabase.postRowIdSync(
            forKeychainId: accountIdentifierForLogging,
            serverPostId: Int64(serverPostId)
        ) != nil else {
            throw LemmyServiceError.internalInconsistency(
                description: "fetchPostInfo: post row not persisted after mirror for postId=\(serverPostId)"
            )
        }

        // Harvest the post's cross-posts (other posts linking the same url) so
        // their counters stay fresh without a separate fetch — restoring the v3
        // `getPost` cross-post harvest now that `getPostNeutral` carries them on
        // `PostDetail.crossPosts`. Best-effort; a failure is logged and skipped.
        await mirrorPostViewsToAppDatabase(views: detail.crossPosts)
    }

    internal func mirrorPostInfoToAppDatabase(
        view: Lemmy.PostView
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
        views: [Lemmy.PostView]
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
        serverPostId: Lemmy.PostID,
        hidden: Bool
    ) async throws {
        try await requireCapability(.hidePosts)

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
