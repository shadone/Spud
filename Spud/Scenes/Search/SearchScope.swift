//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// The scope selected in the search bar's segmented control. Decides which
/// result list is shown. Most scopes map onto a Lemmy `SearchType` and hit the
/// federated search API; `.instances` has no Lemmy `SearchType` and instead
/// searches the bundled Lemmy Explorer directory client-side (see ``isInstances``).
enum SearchScope: Int, CaseIterable {
    case posts
    case communities
    case users
    case comments
    case instances

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
        case .instances:
            NSLocalizedString("Instances", comment: "Search scope: instances")
        }
    }

    /// The Lemmy federated `SearchType` for this scope, or `nil` for client-side
    /// scopes (`.instances`) that Lemmy has no search type for.
    var searchType: Lemmy.SearchType? {
        switch self {
        case .posts: .Posts
        case .communities: .Communities
        case .users: .Users
        case .comments: .Comments
        case .instances: nil
        }
    }

    /// True when this scope is searched client-side over the bundled Lemmy
    /// Explorer instance directory rather than via the federated search API.
    var isInstances: Bool {
        self == .instances
    }
}
