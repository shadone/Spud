//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// The transient comments for a person, decoded from one page of a
/// `GetPersonDetailsResponse`. Reuses the `SearchCommentResult` value type (and
/// thus the comment-with-context cell) since the rendering is identical. Like
/// search results these are a snapshot of the requested page rather than rows
/// in a persistent feed; a tap navigates by the server-side ids.
///
/// The person's *posts* are NOT held here: they are persisted as real
/// `PostRecord`s by `fetchPersonContent` and read back as `PostListRow`s (so
/// the Posts tab renders with the canonical `PostListPostCell`); the view model
/// observes them via `postRows`.
struct PersonContent {
    var comments: [SearchCommentResult] = []

    init() { }

    init(response: Lemmy.GetPersonDetailsResponse) {
        comments = response.comments.map(SearchCommentResult.init)
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
