//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Host callbacks for interactions inside a rendered markdown body. The host
/// resolves web links (in-app vs Safari per preference) and `spud-markdown://`
/// mention/community URLs, presents the media viewer / player, etc. The media
/// methods have default no-op implementations.
@MainActor
public protocol MarkdownBodyDelegate: AnyObject {
    func markdownBody(didTapLink url: URL)
    /// A loaded body image was tapped (zoom). `sourceRect` is in window
    /// coordinates, for a zoom transition.
    func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect)
    func markdownBody(didTapVideo url: URL)
    func markdownBody(didTapAudio url: URL)
}

public extension MarkdownBodyDelegate {
    func markdownBody(didTapImage _: URL, altText _: String?, sourceRect _: CGRect) { }
    func markdownBody(didTapVideo _: URL) { }
    func markdownBody(didTapAudio _: URL) { }
}
