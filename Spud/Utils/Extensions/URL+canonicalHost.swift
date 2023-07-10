//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import os.log

extension URL {
    /// Returns human readable hostname excluding standard prefixes like "www.".
    ///
    /// E.g.
    /// for `www.google.com` returns `google.com`.
    /// for `www.thesun.co.uk` returns `thesun.co.uk`.
    var canonicalHost: String? {
        guard let host else { return nil }
        // TODO: implement me
        return host
    }
}
