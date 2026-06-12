//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// The scope selected in the search bar's segmented control. Maps onto the
/// Lemmy `SearchType` and decides which result list is shown.
enum SearchScope: Int, CaseIterable {
    case posts
    case communities
    case users
    case comments

    var title: String {
        switch self {
        case .posts:
            NSLocalizedString("Posts", comment: "Search scope: posts")
        case .communities:
            NSLocalizedString("Communities", comment: "Search scope: communities")
        case .users:
            NSLocalizedString("Users", comment: "Search scope: users")
        case .comments:
            NSLocalizedString("Comments", comment: "Search scope: comments")
        }
    }

    var searchType: Components.Schemas.SearchType {
        switch self {
        case .posts: .Posts
        case .communities: .Communities
        case .users: .Users
        case .comments: .Comments
        }
    }
}
