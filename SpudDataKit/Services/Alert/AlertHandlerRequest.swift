//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Describes the context in which an error has occurred.
/// Used by``AlertServiceType``.
public enum AlertHandlerRequest: String, CustomStringConvertible {
    case vote
    case save
    case createComment
    case createPost
    case uploadImage
    case fetchPostList
    case fetchComments
    case fetchPersonInfo
    case fetchCommunityInfo
    case setSubscribed
    case fetchSiteInfo
    case fetchPostInfo
    case login
    case fetchImage
    case markAsRead
    case search
    case fetchInbox
    case markInboxItemRead
    case markAllInboxRead
    case fetchUnreadCount
    case sendPrivateMessage

    public var description: String {
        rawValue
    }
}
