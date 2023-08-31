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
    case fetchPostList
    case fetchComments
    case fetchPersonInfo
    case fetchSiteInfo
    case fetchPostInfo
    case login
    case fetchImage
    case markAsRead

    public var description: String {
        rawValue
    }
}
