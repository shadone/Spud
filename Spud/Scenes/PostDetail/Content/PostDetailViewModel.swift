//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreData
import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit

private let logger = Logger.app

/// View-model state for PostDetailViewController. Plain @Observable values
/// driven by GRDB observations and legacy fetch calls. Sort-type changes
/// trigger a re-fetch via the legacy LemmyService — that bridge dissolves
/// in Stage 7.
@MainActor
@Observable
final class PostDetailViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAlertService &
        HasPreferencesService
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let postInfo: LemmyPostInfo

    var commentSortType: Components.Schemas.CommentSortType

    private var accountService: AccountServiceType {
        dependencies.accountService
    }

    private var alertService: AlertServiceType {
        dependencies.alertService
    }

    init(postInfo: LemmyPostInfo, dependencies: Dependencies) {
        self.dependencies = dependencies
        self.postInfo = postInfo
        commentSortType = dependencies.preferencesService.defaultCommentSortType
    }

    func didChangeCommentSortType(_ sortType: Components.Schemas.CommentSortType) {
        commentSortType = sortType
        Task { await fetchComments() }
    }

    func didPrepareObservation(numberOfFetchedComments: Int) {
        Task { await fetchComments() }
    }

    func fetchComments() async {
        do {
            try await accountService
                .lemmyService(for: postInfo.post.account)
                .fetchComments(postId: postInfo.post.objectID, sortType: commentSortType)
        } catch {
            alertService.handle(error, for: .fetchComments)
        }
    }
}
