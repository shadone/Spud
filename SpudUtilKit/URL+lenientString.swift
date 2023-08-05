//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// Attempt to parse the provided string as URL more leniently.
    ///
    /// Some times the incoming urls are not encoded entirely correctly (as per URI spec) and Foundation's URL
    /// being very strictly spec compliant rejects those. This helper is meant to implement more lenient parsing of urls.
    ///
    /// Example of bad urls that Foundation.URL rejects:
    /// - https://matrix.to/#/#lemmy-admin-support-topics:discuss.online
    /// - https://www.reddit.com/r/oslo/comments/i63epw/lyst_til_å_finne_en_psykolog_som_hjelper_noen_med/
    init?(lenientString stringValue: String) {
        guard
            let components = URLComponents(string: stringValue),
            let url = components.url
        else {
            return nil
        }
        self = url
    }
}
