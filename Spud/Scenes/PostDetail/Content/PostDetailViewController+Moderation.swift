//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import UIKit

/// Post- and comment-level moderation, hosted on `PostDetailViewController`.
///
/// The menu builders (`postModerationMenu` / `commentModerationMenu`) are
/// invoked from the header/comment context menus in the main file and return
/// nil unless the account can moderate the post's community. Each action
/// prompts (removals/bans collect an optional reason) and mutates through the
/// account's `LemmyService`, so the open screen reflects it via its GRDB
/// observation and errors surface via `alertService`.
extension PostDetailViewController {
    // MARK: - Moderation

    /// The moderation menu for the post, or nil when the account cannot
    /// moderate the post's community. Offers Remove/Restore, Lock/Unlock,
    /// Feature (pin) to community, and (admins only) Feature to instance.
    func postModerationMenu() -> UIMenu? {
        guard let headerRow = viewModel.headerRow else { return nil }
        let communityId = Lemmy.CommunityID(headerRow.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        let serverPostId = viewModel.serverPostId
        var children: [UIMenuElement] = []

        if headerRow.isRemoved {
            children.append(UIAction(
                title: NSLocalizedString("Restore", comment: "Mod action: restore a removed post"),
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { [weak self] _ in
                self?.performRemovePost(serverPostId: serverPostId, removed: false)
            })
        } else {
            children.append(UIAction(
                title: NSLocalizedString("Remove", comment: "Mod action: remove a post"),
                image: UIImage(systemName: "trash.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptRemovePost(serverPostId: serverPostId)
            })
        }

        let locked = headerRow.isLocked
        children.append(UIAction(
            title: locked
                ? NSLocalizedString("Unlock", comment: "Mod action: unlock a post")
                : NSLocalizedString("Lock", comment: "Mod action: lock a post"),
            image: UIImage(systemName: locked ? "lock.open" : "lock")
        ) { [weak self] _ in
            self?.performLockPost(serverPostId: serverPostId, locked: !locked)
        })

        let featuredCommunity = headerRow.isFeaturedCommunity
        children.append(UIAction(
            title: featuredCommunity
                ? NSLocalizedString("Unpin from community", comment: "Mod action: unfeature post in community")
                : NSLocalizedString("Pin to community", comment: "Mod action: feature post in community"),
            image: UIImage(systemName: featuredCommunity ? "pin.slash" : "pin")
        ) { [weak self] _ in
            self?.performFeaturePost(serverPostId: serverPostId, featured: !featuredCommunity, local: false)
        })

        // Featuring to the instance front page is admin-only.
        if moderationCapability.isAdmin {
            let featuredLocal = headerRow.isFeaturedLocal
            children.append(UIAction(
                title: featuredLocal
                    ? NSLocalizedString("Unpin from instance", comment: "Admin action: unfeature post on instance")
                    : NSLocalizedString("Pin to instance", comment: "Admin action: feature post on instance"),
                image: UIImage(systemName: featuredLocal ? "pin.slash.fill" : "pin.fill")
            ) { [weak self] _ in
                self?.performFeaturePost(serverPostId: serverPostId, featured: !featuredLocal, local: true)
            })
        }

        return UIMenu(
            title: NSLocalizedString("Moderation", comment: "Moderation submenu title"),
            image: UIImage(systemName: "shield"),
            children: children
        )
    }

    /// The moderation menu for a comment, or nil when the account cannot
    /// moderate the post's community. Offers Remove/Restore and
    /// Distinguish/Undistinguish. The ban-from-community action is appended
    /// separately so it can be hidden for the account's own content.
    func commentModerationMenu(
        serverCommentId: Int64,
        commentRow: PostDetailCommentRow
    ) -> UIMenu? {
        guard let headerRow = viewModel.headerRow else { return nil }
        let communityId = Lemmy.CommunityID(headerRow.serverCommunityId)
        guard moderationCapability.canModerate(communityId: communityId) else { return nil }

        var children: [UIMenuElement] = []

        if commentRow.isRemoved == true {
            children.append(UIAction(
                title: NSLocalizedString("Restore", comment: "Mod action: restore a removed comment"),
                image: UIImage(systemName: "arrow.uturn.backward")
            ) { [weak self] _ in
                self?.performRemoveComment(serverCommentId: serverCommentId, removed: false)
            })
        } else {
            children.append(UIAction(
                title: NSLocalizedString("Remove", comment: "Mod action: remove a comment"),
                image: UIImage(systemName: "trash.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptRemoveComment(serverCommentId: serverCommentId)
            })
        }

        let distinguished = commentRow.isDistinguished == true
        children.append(UIAction(
            title: distinguished
                ? NSLocalizedString("Undistinguish", comment: "Mod action: undistinguish a comment")
                : NSLocalizedString("Distinguish", comment: "Mod action: distinguish a comment"),
            image: UIImage(systemName: distinguished ? "shield.slash" : "shield")
        ) { [weak self] _ in
            self?.performDistinguishComment(serverCommentId: serverCommentId, distinguished: !distinguished)
        })

        // Ban the comment author from the community (not for your own content).
        if !isOwnContent(creatorPersonId: commentRow.creatorPersonId),
           let creatorPersonId = commentRow.creatorPersonId
        {
            children.append(UIAction(
                title: NSLocalizedString("Ban from community", comment: "Mod action: ban user from community"),
                image: UIImage(systemName: "hand.raised"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.promptBanFromCommunity(
                    serverPersonId: creatorPersonId,
                    userName: commentRow.creatorName
                )
            })
        }

        return UIMenu(
            title: NSLocalizedString("Moderation", comment: "Moderation submenu title"),
            image: UIImage(systemName: "shield"),
            children: children
        )
    }

    private func promptRemovePost(serverPostId: Lemmy.PostID) {
        presentModerationReasonAlert(
            title: NSLocalizedString("Remove post", comment: "Remove post dialog title"),
            message: NSLocalizedString("Optionally tell the author why the post was removed.", comment: "Remove post dialog message"),
            submitTitle: NSLocalizedString("Remove", comment: "Remove alert submit button")
        ) { [weak self] reason in
            self?.performRemovePost(serverPostId: serverPostId, removed: true, reason: reason)
        }
    }

    private func performRemovePost(
        serverPostId: Lemmy.PostID,
        removed: Bool,
        reason: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .removePost(serverPostId: serverPostId, removed: removed, reason: reason)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .removePost)
            }
        }
    }

    private func performLockPost(serverPostId: Lemmy.PostID, locked: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .lockPost(serverPostId: serverPostId, locked: locked)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .lockPost)
            }
        }
    }

    private func performFeaturePost(
        serverPostId: Lemmy.PostID,
        featured: Bool,
        local: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .featurePost(serverPostId: serverPostId, featured: featured, local: local)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .featurePost)
            }
        }
    }

    private func promptRemoveComment(serverCommentId: Int64) {
        presentModerationReasonAlert(
            title: NSLocalizedString("Remove comment", comment: "Remove comment dialog title"),
            message: NSLocalizedString("Optionally tell the author why the comment was removed.", comment: "Remove comment dialog message"),
            submitTitle: NSLocalizedString("Remove", comment: "Remove alert submit button")
        ) { [weak self] reason in
            self?.performRemoveComment(serverCommentId: serverCommentId, removed: true, reason: reason)
        }
    }

    private func performRemoveComment(
        serverCommentId: Int64,
        removed: Bool,
        reason: String? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .removeComment(serverCommentId: serverCommentId, removed: removed, reason: reason)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .removeComment)
            }
        }
    }

    private func performDistinguishComment(serverCommentId: Int64, distinguished: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .distinguishComment(serverCommentId: serverCommentId, distinguished: distinguished)
                Haptics.success()
            } catch {
                alertService.handle(error, for: .distinguishComment)
            }
        }
    }

    private func promptBanFromCommunity(serverPersonId: Int64, userName: String?) {
        guard let headerRow = viewModel.headerRow else { return }
        let communityId = Lemmy.CommunityID(headerRow.serverCommunityId)
        presentBanFromCommunityConfirmation(
            userName: userName ?? NSLocalizedString("this user", comment: "Fallback user name in ban confirmation"),
            communityName: headerRow.communityName
        ) { [weak self] removeData, reason in
            self?.performBanFromCommunity(
                communityId: communityId,
                serverPersonId: Lemmy.PersonID(serverPersonId),
                removeData: removeData,
                reason: reason
            )
        }
    }

    private func performBanFromCommunity(
        communityId: Lemmy.CommunityID,
        serverPersonId: Lemmy.PersonID,
        removeData: Bool,
        reason: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Haptics.tap()
            do {
                try await viewModel
                    .banFromCommunity(
                        communityId: communityId,
                        serverPersonId: serverPersonId,
                        removeData: removeData,
                        reason: reason
                    )
                Haptics.success()
            } catch {
                alertService.handle(error, for: .banFromCommunity)
            }
        }
    }
}
