//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Decides which Piped instance (apiHost) should resolve a YouTube-family page URL
/// for inline playback: the user's Piped front-end first, then — only with the
/// explicit `inlinePlaybackViaPiped` opt-in — the catalog's default Piped instance.
enum PipedInstanceResolver {
    /// - Returns: the Piped apiHost to resolve `url` through, or nil if it should
    ///   not be inline-resolved via Piped (-> browser fallback). Precedence is
    ///   two-step: a configured Piped front-end wins; otherwise the catalog's
    ///   default Piped instance applies iff the user opted in to
    ///   `inlinePlaybackViaPiped`.
    static func apiHost(forYouTubePageURL url: URL, config: URLSanitizerConfig) -> String? {
        guard let ref = YouTubeReference.extract(from: url) else { return nil }
        switch ref.sourceKind {
        case .frontEnd(.piped):
            // Already on a cataloged Piped instance.
            return YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost
        case .youtube, .frontEnd(.invidious), .frontEndShape:
            // Canonical youtube.com/youtu.be, Invidious front-ends, and the bare
            // /watch?v= shape (best-effort Invidious). First preference: the
            // user's YouTube front-end, iff it is Piped. Never resolve via the
            // Invidious instance itself.
            if config.redirectToFrontEnds {
                let setting = config.setting(for: .youtube)
                if setting.isEnabled,
                   let instance = YouTubeFrontEndCatalog.instance(forHost: setting.host),
                   instance.kind == .piped,
                   let apiHost = instance.apiHost
                {
                    return apiHost
                }
            }
            // Second preference: the catalog's default Piped instance — but only
            // with the explicit opt-in. Routing playback traffic to a third
            // party the user didn't choose must be consensual; without the
            // opt-in, nil means playback opens the original page in the browser.
            guard config.inlinePlaybackViaPiped else { return nil }
            return YouTubeFrontEndCatalog.defaultPipedApiHost
        }
    }
}
