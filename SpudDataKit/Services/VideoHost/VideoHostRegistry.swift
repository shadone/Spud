//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Aggregates the known video hosts. Recognition returns the first host that
/// claims a URL; resolution dispatches to the host matching the match's kind.
/// Adding a host = appending it to `hosts`.
public struct VideoHostRegistry: VideoHostRecognizing, VideoHostResolving {
    private let hosts: [any VideoHost]

    public init(hosts: [any VideoHost] = [StreamableVideoHost(), PeerTubeVideoHost()]) {
        self.hosts = hosts
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
