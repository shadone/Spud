//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// The transient posts + comments for a person, decoded from one page of a
/// `GetPersonDetailsResponse`. Reuses the `SearchPostResult` /
/// `SearchCommentResult` value types (and thus the search result cells) since
/// the rendering is identical: feed-style post rows and comment-with-context
/// rows. Like search results these are a snapshot of the requested page rather
/// than rows in a persistent feed; a tap navigates by the server-side ids.
struct PersonContent {
    var posts: [SearchPostResult] = []
    var comments: [SearchCommentResult] = []

    init() { }

    init(response: Components.Schemas.GetPersonDetailsResponse) {
        posts = response.posts.map(SearchPostResult.init)
        comments = response.comments.map(SearchCommentResult.init)
    }

    func isEmpty(for tab: PersonContentTab) -> Bool {
        switch tab {
        case .posts: posts.isEmpty
        case .comments: comments.isEmpty
        }
    }
}

/// Which of the person's content lists is shown by the segmented control.
enum PersonContentTab: Int, CaseIterable {
    case posts
    case comments

    var title: String {
        switch self {
        case .posts:
            NSLocalizedString("Posts", comment: "Person profile segmented control: posts tab")
        case .comments:
            NSLocalizedString("Comments", comment: "Person profile segmented control: comments tab")
        }
    }
}

/// The phase the person content list is in. Drives which designed state the
/// view controller renders.
enum PersonContentPhase: Equatable {
    case loading
    case loaded
    case error
}
