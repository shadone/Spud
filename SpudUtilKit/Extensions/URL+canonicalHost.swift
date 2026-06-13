//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

public extension URL {
    /// Returns human readable hostname excluding standard prefixes like "www.".
    ///
    /// E.g.
    /// for `www.google.com` returns `google.com`.
    /// for `www.thesun.co.uk` returns `thesun.co.uk`.
    /// for `mozilla.org` returns `mozilla.org`.
    ///
    /// Only a leading `www.` label is stripped; a host like `wwwsomething.com`
    /// (no dot after `www`) is returned unchanged. Returns `nil` when the url has
    /// no host (e.g. `mailto:` urls).
    var canonicalHost: String? {
        guard let host else { return nil }
        let prefix = "www."
        if host.count > prefix.count, host.lowercased().hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }
}
