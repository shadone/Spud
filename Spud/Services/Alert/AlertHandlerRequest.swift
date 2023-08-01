//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum AlertHandlerRequest: CustomStringConvertible {
    case vote
    case fetchPostList
    case fetchComments
    case fetchPersonDetails
    case fetchSiteInfo
    case login
    case fetchImage

    var description: String {
        switch self {
        case .vote:
            return "vote"

        case .fetchPostList:
            return "fetchPostList"

        case .fetchComments:
            return "fetchComments"

        case .fetchPersonDetails:
            return "fetchPersonDetails"

        case .fetchSiteInfo:
            return "fetchSiteInfo"

        case .login:
            return "login"

        case .fetchImage:
            return "fetchImage"
        }
    }
}