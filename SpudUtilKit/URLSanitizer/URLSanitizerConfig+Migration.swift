//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URLSanitizerConfig {
    /// Builds the migrated config when upgrading from the legacy single
    /// `rewriteTwitterLinksToXcancel` boolean. Returns nil when no migration is
    /// needed (already migrated, or the legacy flag was off), so the caller
    /// only persists a config when there is something to carry over.
    static func migratingFromLegacyXcancel(
        legacyEnabled: Bool,
        alreadyMigrated: Bool
    ) -> URLSanitizerConfig? {
        guard !alreadyMigrated, legacyEnabled else { return nil }
        var config = URLSanitizerConfig.default
        config.redirectToFrontEnds = true
        config.frontEnds = config.frontEnds.map { entry in
            guard entry.service == .twitter else { return entry }
            return FrontEndConfig(service: .twitter, isEnabled: true, host: entry.host)
        }
        return config
    }
}
