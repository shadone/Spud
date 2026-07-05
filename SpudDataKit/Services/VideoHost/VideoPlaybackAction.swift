//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

/// What to do with a tapped post video URL.
public enum VideoPlaybackAction: Equatable, Sendable {
    /// Play this directly-playable stream URL inline.
    case play(URL)
    /// Resolution is not possible (unrecognized-but-not-a-file, or a recognized
    /// host that failed to resolve); open this page URL with the normal link flow.
    case openExternally(URL)
}

/// Decides how to play a tapped video URL:
/// - not a recognized host → assume a direct file, `.play(url)` (existing behavior);
/// - a recognized host that resolves → `.play(streamUrl)`;
/// - a recognized host that fails to resolve → `.openExternally(pageUrl)`.
public func videoPlaybackAction(
    forVideoAt url: URL,
    using host: some VideoHostRecognizing & VideoHostResolving
) async -> VideoPlaybackAction {
    guard let match = host.recognize(url) else {
        return .play(url)
    }
    do {
        let resolved = try await host.resolve(match)
        return .play(resolved.streamUrl)
    } catch {
        Logger.resolvableVideoHost.error(
            "Failed to resolve \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        return .openExternally(match.pageUrl)
    }
}
