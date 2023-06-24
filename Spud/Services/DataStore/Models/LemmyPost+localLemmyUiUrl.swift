//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension LemmyPost {
    /// Returns a link to this post, a url that can be opened in a browser.
    /// - Note: This assumes the instance runs standard install of Lemmy-UI which is not entirely correct.
    var localLemmyUiUrl: URL {
        URL(string: "\(account.site.instanceUrl.absoluteString)/post/\(localPostId)")!
    }
}
