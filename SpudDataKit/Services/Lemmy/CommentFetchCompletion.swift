//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// How a post's comment fetch ended.
///
/// This is the ONLY honest source for "is the loaded tree complete". The post's
/// comment counter cannot answer it: the server's count and the number of rows
/// a listing returns legitimately differ (a 135-comment post returns 138 rows),
/// and deriving tree state from the counter is the reconciliation approach this
/// project already considered and rejected. Whether a pagination cursor was
/// still outstanding when the fetch stopped is known exactly, at the source.
public enum CommentFetchCompletion: Sendable, Equatable {
    /// The listing was exhausted -- every page the server offered was fetched.
    /// Always the outcome on a v3 backend, whose comment listing has no cursor.
    case complete

    /// The fetch stopped with pages still outstanding.
    case partial(PartialReason)

    public enum PartialReason: Sendable, Equatable {
        /// The page budget (``LemmyService/maxCommentPages``) ran out first.
        case pageBudgetExhausted
        /// A later page failed after at least one page had already been
        /// imported. The earlier pages are kept and stay on screen.
        case pageFetchFailed
    }
}
