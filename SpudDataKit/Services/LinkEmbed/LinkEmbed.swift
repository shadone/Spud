//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Resolved preview metadata for a link. `title` is fetched (oEmbed) for video
/// links; `thumbnailURL` is derived locally (YouTube/Invidious) or from oEmbed
/// (PeerTube).
public struct LinkEmbed: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case video
        case generic
    }

    public let kind: Kind
    public let title: String?
    public let thumbnailURL: URL?

    public init(kind: Kind, title: String?, thumbnailURL: URL?) {
        self.kind = kind
        self.title = title
        self.thumbnailURL = thumbnailURL
    }
}
