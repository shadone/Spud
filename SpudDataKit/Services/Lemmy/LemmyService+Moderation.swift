//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog

private let logger = Logger.lemmyService

/// Moderation / admin write actions. These mirror the safety (block / report)
/// spine in `LemmyService+Safety.swift`: sign-out guard -> api call -> mirror the
/// updated view. Permission gating (is the account a moderator of the target
/// community, or a site admin) is the UI's responsibility, sourced from
/// `fetchModerationCapability()`; the server is the ultimate authority and
/// rejects unauthorized actions with an api error.
public extension LemmyService {
    func fetchModerationCapability() async throws -> ModerationCapability {
        // Unlike the write actions, a signed-out account resolves to `.none`
        // rather than throwing: the caller gates UI on the capability and a
        // signed-out account simply has no powers.
        guard !accountIsSignedOut else {
            return .none
        }

        logger.debug("""
            Fetch moderation capability for \
            account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash))
            """)

        let myUser: LemmyKit.MyUser
        do {
            myUser = try await api.getMyUserNeutral()
        } catch {
            logger.error("""
                Fetch moderation capability failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // The neutral `MyUser.moderates` is a bare list of community server ids.
        let moderatedCommunityIds = Set(myUser.moderates.map { Lemmy.CommunityID($0) })

        return ModerationCapability(
            moderatedCommunityIds: moderatedCommunityIds,
            isAdmin: myUser.isAdmin
        )
    }

    func removePost(
        serverPostId: Lemmy.PostID,
        removed: Bool,
        reason: String?
    ) async throws {
        try requireSignedIn(action: "Remove post", postId: serverPostId)

        logger.debug("""
            Set post removed=\(removed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        do {
            // No neutral moderation endpoint yet; the v3 wrapper still works on v3.
            _ = try await api.removePost(postID: serverPostId, removed: removed, reason: reason)
        } catch {
            logger.error("""
                Remove post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Re-fetch through the neutral getPost to refresh the mirror (the v3
        // response can't feed the neutral importer). Best-effort.
        try? await fetchPostInfo(serverPostId: serverPostId)
    }

    func lockPost(
        serverPostId: Lemmy.PostID,
        locked: Bool
    ) async throws {
        try requireSignedIn(action: "Lock post", postId: serverPostId)

        logger.debug("""
            Set post locked=\(locked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        do {
            _ = try await api.lockPost(postID: serverPostId, locked: locked)
        } catch {
            logger.error("""
                Lock post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Re-fetch through the neutral getPost to refresh the mirror. Best-effort.
        try? await fetchPostInfo(serverPostId: serverPostId)
    }

    func featurePost(
        serverPostId: Lemmy.PostID,
        featured: Bool,
        local: Bool
    ) async throws {
        try requireSignedIn(action: "Feature post", postId: serverPostId)

        let featureType: Lemmy.PostFeatureType = local ? .Local : .Community
        logger.debug("""
            Set post featured=\(featured, privacy: .public) type=\(featureType.rawValue, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        do {
            _ = try await api.featurePost(
                postID: serverPostId,
                featured: featured,
                featureType: featureType
            )
        } catch {
            logger.error("""
                Feature post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Re-fetch through the neutral getPost to refresh the mirror. Best-effort.
        try? await fetchPostInfo(serverPostId: serverPostId)
    }

    func removeComment(
        serverCommentId: Lemmy.CommentID,
        removed: Bool,
        reason: String?
    ) async throws {
        try requireSignedIn(action: "Remove comment", commentId: serverCommentId)

        logger.debug("""
            Set comment removed=\(removed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        do {
            _ = try await api.removeComment(commentID: serverCommentId, removed: removed, reason: reason)
        } catch {
            logger.error("""
                Remove comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // The neutral surface has no single-comment fetch to refresh the mirror
        // from (and the v3 response can't feed the neutral importer), so the local
        // removed flag updates on the next comment-tree load. See Phase 6 follow-ups.
    }

    func distinguishComment(
        serverCommentId: Lemmy.CommentID,
        distinguished: Bool
    ) async throws {
        try requireSignedIn(action: "Distinguish comment", commentId: serverCommentId)

        logger.debug("""
            Set comment distinguished=\(distinguished, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        do {
            _ = try await api.distinguishComment(commentID: serverCommentId, distinguished: distinguished)
        } catch {
            logger.error("""
                Distinguish comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // As with removeComment, the local distinguished flag refreshes on the
        // next comment-tree load. See Phase 6 follow-ups.
    }

    func banFromCommunity(
        serverCommunityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        ban: Bool,
        removeData: Bool,
        reason: String?
    ) async throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                Ban from community rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                communityId=\(serverCommunityId, privacy: .public) \
                personId=\(serverPersonId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }

        logger.debug("""
            Set ban=\(ban, privacy: .public) removeData=\(removeData, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            communityId=\(serverCommunityId, privacy: .public) \
            personId=\(serverPersonId, privacy: .public)
            """)

        do {
            if ban {
                _ = try await api.banFromCommunity(
                    communityID: serverCommunityId,
                    personID: serverPersonId,
                    removeData: removeData,
                    reason: reason
                )
            } else {
                _ = try await api.unbanFromCommunity(
                    communityID: serverCommunityId,
                    personID: serverPersonId,
                    reason: reason
                )
            }
        } catch {
            logger.error("""
                Ban from community failed. communityId=\(serverCommunityId, privacy: .public) \
                personId=\(serverPersonId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        // Re-fetch the person through the neutral getPersonDetails to refresh the
        // mirror (the v3 response can't feed the neutral importer); if remove_data
        // was set the server has also removed this person's content, which the
        // caller refreshes. Best-effort.
        try? await fetchPersonInfo(serverPersonId: serverPersonId)
    }

    // MARK: Helpers

    private func requireSignedIn(
        action: String,
        postId: Lemmy.PostID
    ) throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                \(action, privacy: .public) rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                postId=\(postId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }
    }

    private func requireSignedIn(
        action: String,
        commentId: Lemmy.CommentID
    ) throws {
        guard !accountIsSignedOut else {
            logger.debug("""
                \(action, privacy: .public) rejected - account is signed out. \
                account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
                commentId=\(commentId, privacy: .public)
                """)
            throw LemmyServiceError.requiresAuthentication
        }
    }
}
