//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// If this URL points at Twitter / X, returns the equivalent URL on the
    /// `xcancel.com` privacy front-end, preserving the path, query and fragment;
    /// otherwise returns `self` unchanged.
    ///
    /// Matches `twitter.com` and `x.com`, including their `www.`, `mobile.` and
    /// `m.` subdomains. Other hosts -- including unlisted subdomains such as
    /// `api.twitter.com` -- are left untouched.
    func rewritingTwitterToXcancel() -> URL {
        guard
            var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else {
            return self
        }

        // Strip a single recognised subdomain label so e.g. mobile.twitter.com
        // matches, without matching arbitrary subdomains like api.twitter.com.
        let baseHost: String
        if let label = ["www.", "mobile.", "m."].first(where: { host.hasPrefix($0) }) {
            baseHost = String(host.dropFirst(label.count))
        } else {
            baseHost = host
        }

        guard baseHost == "twitter.com" || baseHost == "x.com" else {
            return self
        }

        components.host = "xcancel.com"
        return components.url ?? self
    }
}
