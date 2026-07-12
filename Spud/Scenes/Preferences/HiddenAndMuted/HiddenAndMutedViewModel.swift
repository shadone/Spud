//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// Drives the "Hidden & Muted" management screen. Hidden posts come from the
/// local store (server-backed `isHidden`); muted communities are the local,
/// timed mute records. Both lists are read synchronously on appear. Unhide
/// calls `LemmyService.hidePost(..., hidden: false)`; unmute deletes the local
/// record.
@MainActor
@Observable
final class HiddenAndMutedViewModel {
    private(set) var hiddenPosts: [HiddenPostListItem] = []
    private(set) var mutedCommunities: [MutedCommunityListItem] = []

    @ObservationIgnored
    private let accountScope: AccountScope
    @ObservationIgnored
    private let appDatabase: AppDatabase

    private var accountKeychainId: String {
        accountScope.accountKeychainId
    }

    init(
        accountScope: AccountScope,
        appDatabase: AppDatabase
    ) {
        self.accountScope = accountScope
        self.appDatabase = appDatabase
    }

    /// Reloads both lists from the local store.
    func load() {
        hiddenPosts = appDatabase.hiddenPostsSync(forKeychainId: accountKeychainId)
        mutedCommunities = appDatabase.mutedCommunitiesSync(forKeychainId: accountKeychainId)
    }

    /// Unhides the post, removing it from the list optimistically and reverting
    /// on failure.
    func unhide(post: HiddenPostListItem) {
        let index = hiddenPosts.firstIndex { $0.serverPostId == post.serverPostId }
        if let index { hiddenPosts.remove(at: index) }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accountScope.lemmyService
                    .hidePost(serverPostId: Lemmy.PostID(post.serverPostId), hidden: false)
            } catch {
                logger.error("Unhide post failed: \(String(describing: error), privacy: .public)")
                if let index, index <= hiddenPosts.count {
                    hiddenPosts.insert(post, at: index)
                } else {
                    hiddenPosts.append(post)
                }
            }
        }
    }

    /// Unmutes the community. Muting is local, so this is a synchronous delete
    /// with no revert.
    func unmute(community: MutedCommunityListItem) {
        mutedCommunities.removeAll { $0.communityActorId == community.communityActorId }
        appDatabase.unmuteCommunitySync(
            forKeychainId: accountKeychainId,
            communityActorId: community.communityActorId
        )
    }
}
