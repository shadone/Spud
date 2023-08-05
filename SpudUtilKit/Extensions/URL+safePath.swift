//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// Returns the path portion of the url.
    var safePath: String {
        let pathString: String?
        if #available(iOS 16.0, *) {
            pathString = path(percentEncoded: false)
        } else {
            pathString = path
        }

        guard let pathString else {
            assertionFailure("Failed to get path from url '\(absoluteString)'")
            return ""
        }

        return pathString
    }
}
