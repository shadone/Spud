//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit

extension CrossPostSummary {
    /// The "c/name@instance" display handle for the cross-post's community,
    /// matching the "c/…" attribution format used elsewhere (e.g. the post-list
    /// context menu, the post-detail header attribution). Falls back to a bare
    /// "c/name" when the community actor id doesn't resolve to a host.
    var qualifiedCommunityHandle: String {
        guard
            let communityActorId,
            let host = InstanceActorId(from: communityActorId)?.host
        else {
            return "c/\(communityName)"
        }
        return "c/\(communityName)@\(host)"
    }
}
