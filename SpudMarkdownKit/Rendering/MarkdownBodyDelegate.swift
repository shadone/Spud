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
    /// The context menu to present for a long-press on an inline body link, or
    /// `nil` to show no menu.
    ///
    /// The host builds a menu that is SAFE for the link's scheme: UIKit's default
    /// text-link menu eagerly builds a URL preview that traps on a non-`http(s)`
    /// scheme (e.g. the synthetic `spud-markdown://mention?…` URL a Lemmy mention
    /// renders as), so an internal / non-web link MUST be given a preview-free
    /// configuration. Returning `nil` suppresses the menu entirely. The default
    /// implementation returns `nil`, so a host that renders no interactive links
    /// simply shows no long-press menu (never the crashing default).
    func markdownBody(menuConfigurationForLink url: URL) -> UITextItem.MenuConfiguration?
    /// A loaded body image was tapped (zoom). `sourceRect` is in window
    /// coordinates, for a zoom transition.
    func markdownBody(didTapImage url: URL, altText: String?, sourceRect: CGRect)
    func markdownBody(didTapVideo url: URL)
    func markdownBody(didTapAudio url: URL)
}

public extension MarkdownBodyDelegate {
    func markdownBody(menuConfigurationForLink _: URL) -> UITextItem.MenuConfiguration? {
        nil
    }

    func markdownBody(didTapImage _: URL, altText _: String?, sourceRect _: CGRect) { }
    func markdownBody(didTapVideo _: URL) { }
    func markdownBody(didTapAudio _: URL) { }
}
