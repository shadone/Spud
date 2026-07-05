//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Decides which Piped instance (apiHost) should resolve a YouTube-family page URL
/// for inline playback, honoring the user's front-end preference.
enum PipedInstanceResolver {
    /// - Returns: the Piped apiHost to resolve `url` through, or nil if it should
    ///   not be inline-resolved via Piped (-> browser fallback).
    static func apiHost(forYouTubePageURL url: URL, config: URLSanitizerConfig) -> String? {
        guard let ref = YouTubeReference.extract(from: url) else { return nil }
        switch ref.sourceKind {
        case .frontEnd(.piped):
            // Already on a cataloged Piped instance.
            return YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost
        case .youtube:
            // Canonical youtube.com/youtu.be: use the user's YouTube front-end iff it is Piped.
            guard config.redirectToFrontEnds else { return nil }
            let setting = config.setting(for: .youtube)
            guard setting.isEnabled,
                  let instance = YouTubeFrontEndCatalog.instance(forHost: setting.host),
                  instance.kind == .piped
            else {
                return nil
            }
            return instance.apiHost
        case .frontEnd(.invidious), .frontEndShape:
            return nil
        }
    }
}
