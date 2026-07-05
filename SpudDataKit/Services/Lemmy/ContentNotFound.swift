//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit

/// Recognizes the Lemmy "this post does not exist" rejection so read paths and
/// the outbox can mark a stale cached post as unavailable. The only place the
/// `couldnt_find_post` error code is matched — mirrors `OutboxFailureClass` /
/// `LoadFailure` in style.
public enum ContentNotFound {
    /// The Lemmy error codes that mean "the requested post is gone". Lemmy does
    /// not distinguish mod-removed / author-deleted / de-federated here.
    private static let postCodes: Set<String> = ["couldnt_find_post"]

    /// `true` when `error` is a structured Lemmy rejection whose code means the
    /// post no longer exists, unwrapping both the bare `LemmyApiError` and the
    /// `LemmyServiceError.apiError` wrapper.
    public static func matchesPost(_ error: Error) -> Bool {
        switch error {
        case let apiError as LemmyApiError:
            return matchesPost(apiError)
        case let .apiError(apiError) as LemmyServiceError:
            return matchesPost(apiError)
        default:
            return false
        }
    }

    private static func matchesPost(_ apiError: LemmyApiError) -> Bool {
        guard case let .serverError(errorResponse) = apiError else { return false }
        return postCodes.contains(errorResponse.error)
    }
}
