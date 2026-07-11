//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

// Note: `VideoHost` is qualified as `SpudDataKit.VideoHost` throughout this file because
// `import SpudUtilKit` also exports a `VideoHost` enum (for link-parsing).

/// Aggregates the known video hosts. Recognition returns the first host that
/// claims a URL; resolution dispatches to the host matching the match's kind.
/// Adding a host = appending it to `hosts`.
public struct VideoHostRegistry: VideoHostRecognizing, VideoHostResolving {
    private let hosts: [any SpudDataKit.VideoHost]

    public init(hosts: [any SpudDataKit.VideoHost]) {
        self.hosts = hosts
    }

    /// Production default. `pipedConfig` is the caller's snapshot of the user's
    /// URL-sanitizer config; it gates Piped-based YouTube resolution (recognition
    /// is preference-free). The detector uses `.default` (it never resolves).
    public init(pipedConfig: URLSanitizerConfig = .default) {
        self.init(hosts: [
            StreamableVideoHost(),
            PeerTubeVideoHost(),
            PipedVideoHost(config: pipedConfig),
            LoopsVideoHost(),
        ])
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        for host in hosts {
            if let match = host.recognize(url) {
                return match
            }
        }
        return nil
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard let host = hosts.first(where: { $0.kind == match.kind }) else {
            throw VideoHostResolutionError.unresolvable
        }
        return try await host.resolve(match)
    }
}
