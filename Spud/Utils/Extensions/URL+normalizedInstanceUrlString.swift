//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension URL {
    /// Returns a url representing Lemmy instance. In a normalized form to ensure consistency regardless of how
    /// user might've spelled it.
    var normalizedInstanceUrlString: String? {
        guard port == nil || port == 443 else {
            return nil
        }

        assert(pathComponents == [] || pathComponents == ["/"])

        return "https://\(safeHost)/"
    }
}
