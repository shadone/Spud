//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Cleans an outbound URL by running an ordered list of independent transform
/// steps. Order matters: redirectors are unwrapped first (so later steps act
/// on the real destination) and the front-end rewrite runs last (so the chosen
/// front-end receives an already-cleaned URL). The result is idempotent.
public enum URLSanitizer {
    /// The pipeline, in execution order.
    private static let steps: [any URLRewriteStep] = [
        RedirectorUnwrapStep(),
        DeAMPStep(),
        HTTPSUpgradeStep(),
        TrackingParamStep(),
        FrontEndRewriteStep(),
    ]

    public static func sanitize(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.isEnabled else { return url }
        return steps.reduce(url) { partial, step in
            step.apply(partial, config: config)
        }
    }
}
