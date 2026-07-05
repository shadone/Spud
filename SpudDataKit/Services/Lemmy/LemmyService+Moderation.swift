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

        let response: Components.Schemas.GetSiteResponse
        do {
            response = try await api.getSite()
        } catch {
            logger.error("""
                Fetch moderation capability failed. \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        guard let myUser = response.my_user else {
            return .none
        }

        let moderatedCommunityIds = Set(myUser.moderates.map(\.community.id))
        let isAdmin = myUser.local_user_view.local_user.admin

        return ModerationCapability(
            moderatedCommunityIds: moderatedCommunityIds,
            isAdmin: isAdmin
        )
    }

    func removePost(
        serverPostId: Components.Schemas.PostID,
        removed: Bool,
        reason: String?
    ) async throws {
        try requireSignedIn(action: "Remove post", postId: serverPostId)

        logger.debug("""
            Set post removed=\(removed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.removePost(postID: serverPostId, removed: removed, reason: reason)
        } catch {
            logger.error("""
                Remove post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorPostInfoToAppDatabase(view: response.post_view)
    }

    func lockPost(
        serverPostId: Components.Schemas.PostID,
        locked: Bool
    ) async throws {
        try requireSignedIn(action: "Lock post", postId: serverPostId)

        logger.debug("""
            Set post locked=\(locked, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.lockPost(postID: serverPostId, locked: locked)
        } catch {
            logger.error("""
                Lock post failed. postId=\(serverPostId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorPostInfoToAppDatabase(view: response.post_view)
    }

    func featurePost(
        serverPostId: Components.Schemas.PostID,
        featured: Bool,
        local: Bool
    ) async throws {
        try requireSignedIn(action: "Feature post", postId: serverPostId)

        let featureType: Components.Schemas.PostFeatureType = local ? .Local : .Community
        logger.debug("""
            Set post featured=\(featured, privacy: .public) type=\(featureType.rawValue, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            postId=\(serverPostId, privacy: .public)
            """)

        let response: Components.Schemas.PostResponse
        do {
            response = try await api.featurePost(
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

        await mirrorPostInfoToAppDatabase(view: response.post_view)
    }

    func removeComment(
        serverCommentId: Components.Schemas.CommentID,
        removed: Bool,
        reason: String?
    ) async throws {
        try requireSignedIn(action: "Remove comment", commentId: serverCommentId)

        logger.debug("""
            Set comment removed=\(removed, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.removeComment(commentID: serverCommentId, removed: removed, reason: reason)
        } catch {
            logger.error("""
                Remove comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommentToAppDatabase(view: response.comment_view)
    }

    func distinguishComment(
        serverCommentId: Components.Schemas.CommentID,
        distinguished: Bool
    ) async throws {
        try requireSignedIn(action: "Distinguish comment", commentId: serverCommentId)

        logger.debug("""
            Set comment distinguished=\(distinguished, privacy: .public) \
            for account=\(self.accountIdentifierForLogging, privacy: .sensitive(mask: .hash)) \
            commentId=\(serverCommentId, privacy: .public)
            """)

        let response: Components.Schemas.CommentResponse
        do {
            response = try await api.distinguishComment(commentID: serverCommentId, distinguished: distinguished)
        } catch {
            logger.error("""
                Distinguish comment failed. commentId=\(serverCommentId, privacy: .public). \
                \(String(describing: error), privacy: .public)
                """)
            throw LemmyServiceError(from: error)
        }

        await mirrorCommentToAppDatabase(view: response.comment_view)
    }

    func banFromCommunity(
        serverCommunityId: Components.Schemas.CommunityID,
        serverPersonId: Components.Schemas.PersonID,
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

        let response: Components.Schemas.BanFromCommunityResponse
        do {
            if ban {
                response = try await api.banFromCommunity(
                    communityID: serverCommunityId,
                    personID: serverPersonId,
                    removeData: removeData,
                    reason: reason
                )
            } else {
                response = try await api.unbanFromCommunity(
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

        // Mirror the refreshed author info; if remove_data was set the server
        // has also removed this person's content, which the caller refreshes.
        await mirrorPersonInfoToAppDatabase(view: response.person_view)
    }

    // MARK: Helpers

    private func requireSignedIn(
        action: String,
        postId: Components.Schemas.PostID
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
        commentId: Components.Schemas.CommentID
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
