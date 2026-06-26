//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

enum LinkPreviewCardFactory {
    /// Builds one `LinkPreviewView` per preview into `stack`, wires taps, and
    /// (when `fetchLinkEmbeds` and the link is a video) asynchronously fills in the
    /// title + thumbnail. `token`/`currentToken` guard against a slow fetch landing
    /// on a recycled cell — pass a fresh `UUID()` per configure and a closure
    /// returning the cell's current token.
    @MainActor
    static func populate(
        _ stack: UIStackView,
        previews: [CommentLinkPreview],
        fetchLinkEmbeds: Bool,
        imageService: ImageServiceType,
        linkEmbedService: LinkEmbedServiceType?,
        token: UUID,
        currentToken: @escaping () -> UUID,
        onTap: @escaping (URL) -> Void,
        registerContextMenu: (LinkPreviewView, URL) -> Void
    ) {
        for preview in previews {
            let view = LinkPreviewView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.url = preview.displayURL
            view.anchorText = preview.anchorText
            view.isVideo = preview.kind == .video
            let tapURL = preview.tapURL
            view.tapped = { _ in onTap(tapURL) }
            registerContextMenu(view, tapURL)
            stack.addArrangedSubview(view)

            guard fetchLinkEmbeds, preview.kind == .video, let service = linkEmbedService else { continue }
            Task { [weak view] in
                guard let embed = await service.embed(for: preview.displayURL) else { return }
                guard currentToken() == token, let view else { return }
                if let title = embed.title { view.title = title }
                guard let thumbnailURL = embed.thumbnailURL else { return }
                for await state in imageService.fetch(thumbnailURL) {
                    guard currentToken() == token else { return }
                    if case let .ready(image) = state { view.thumbnailImage = image }
                }
            }
        }
    }
}
