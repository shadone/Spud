//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A video-hosting service Spud can play inline by resolving its page URL to a stream.
public enum VideoHostKind: Equatable, Sendable {
    case streamable
    case peertube
    case piped
}

/// A URL recognized as belonging to a `VideoHostKind`, carrying the host-specific
/// identifier (e.g. a streamable shortcode) and the original page URL.
public struct VideoHostMatch: Equatable, Sendable {
    public let kind: VideoHostKind
    public let identifier: String
    public let pageUrl: URL

    public init(kind: VideoHostKind, identifier: String, pageUrl: URL) {
        self.kind = kind
        self.identifier = identifier
        self.pageUrl = pageUrl
    }
}

/// The playable result of resolving a `VideoHostMatch`.
public struct ResolvedVideo: Equatable, Sendable {
    /// A directly-playable (AVFoundation-supported) stream URL.
    public let streamUrl: URL
    /// The host's own poster image, when the API returns one.
    public let posterUrl: URL?
    public let title: String?

    public init(streamUrl: URL, posterUrl: URL?, title: String?) {
        self.streamUrl = streamUrl
        self.posterUrl = posterUrl
        self.title = title
    }
}

public enum VideoHostResolutionError: Error, Equatable, Sendable {
    /// The match cannot be resolved by this host (wrong kind / malformed).
    case unresolvable
    /// The network fetch returned no data.
    case network
    /// The response body could not be decoded.
    case decoding
    /// The video exists but is not ready to play.
    case notReady
    /// The response carried no AVFoundation-playable file.
    case noPlayableFile
}

/// Synchronous, pure recognition of a URL as a known video host. Used by the
/// content detector, which must stay synchronous and side-effect-free.
public protocol VideoHostRecognizing: Sendable {
    func recognize(_ url: URL) -> VideoHostMatch?
}

/// Asynchronous resolution of a match into a playable stream (a network call).
public protocol VideoHostResolving: Sendable {
    func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo
}

/// A concrete host that both recognizes its URLs and resolves them.
public protocol VideoHost: VideoHostRecognizing, VideoHostResolving {
    var kind: VideoHostKind { get }
}
