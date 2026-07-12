//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

public extension SiteListRow {
    /// A minimal row for a user-typed instance that isn't in the Explorer
    /// directory (e.g. a private, non-federated Lemmy instance). Only
    /// `instance`/`hostname` are meaningful here; every decorative directory
    /// field (icon, description, stats) is defaulted since there's no
    /// directory record to source them from.
    ///
    /// `isOpenRegistration` is `true` because we cannot know the real value
    /// without a `getSite` call, and defaulting to `false` would be actively
    /// misleading (the login screen's "create an account" affordance is not
    /// gated on this flag, but callers that do branch on it should still see
    /// sign-up as available here) - the register request itself is the real
    /// gate and will reject a closed instance.
    static func forTypedInstance(_ instance: InstanceActorId) -> SiteListRow {
        SiteListRow(
            id: 0,
            instance: instance,
            hostname: instance.host,
            name: nil,
            descriptionText: nil,
            iconUrl: nil,
            score: 0,
            usersTotal: nil,
            usersActiveMonth: nil,
            uptimeAllTime: nil,
            isNsfw: false,
            isOpenRegistration: true,
            languageCodes: [],
            tags: []
        )
    }
}
