//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// Returns the hostname portion of the url.
    var safeHost: String {
        let hostString: String?
        if #available(iOS 16.0, *) {
            hostString = host(percentEncoded: false)
        } else {
            hostString = host
        }

        guard let hostString else {
            //assertionFailure("Failed to get hostname from url '\(absoluteString)'")
            return absoluteString
        }

        return hostString
    }
}
