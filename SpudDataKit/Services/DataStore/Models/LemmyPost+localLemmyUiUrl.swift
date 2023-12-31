//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension LemmyPost {
    /// Returns a link to this post, a url that can be opened in a browser.
    /// - Note: This assumes the instance runs standard install of Lemmy-UI which is not entirely correct.
    var localLemmyUiUrl: URL {
        // TODO: check if Lemmy in the intance.nodeInfo?.softwareName
        let url = URL(string: account.site.instance.actorId.actorId)!

        if #available(iOS 16.0, *) {
            return url.appending(path: "post/\(postId)")
        } else {
            return url.appendingPathComponent("post/\(postId)")
        }
    }
}
