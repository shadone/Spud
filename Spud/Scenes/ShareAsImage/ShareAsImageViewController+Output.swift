//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUIKit
import UIKit
import UniformTypeIdentifiers

/// The editor's output actions — Share, Save to Photos, Copy — and the shared
/// export helpers they use.
///
/// Every action renders a FRESH card (``makeExportCard()``) rather than the
/// on-screen preview: ``ShareCardImageRenderer/render(cardView:options:)`` runs a
/// layout pass that mutates the view's bounds, so handing it the live preview
/// would corrupt what the user is looking at. Each action also persists the
/// current options as the last-used configuration.
extension ShareAsImageViewController {
    // MARK: - Share

    func shareTapped() {
        Task { [weak self] in
            guard let self else { return }
            await ensureMediaResolved()
            let image = renderCurrentImage()
            viewModel.persist()
            guard let permalink else {
                presentFailure()
                return
            }
            do {
                let pngURL = try ShareCardImageRenderer.writePNG(
                    image,
                    altText: viewModel.currentAltText,
                    suggestedName: suggestedFileName
                )
                let items = ShareCardImageRenderer.shareItems(
                    image: image,
                    pngFileURL: pngURL,
                    permalink: permalink
                )
                presentShareSheet(items: items, sourceView: shareButton)
            } catch {
                presentFailure()
            }
        }
    }

    // MARK: - Save to Photos

    func saveTapped() {
        Task { [weak self] in
            guard let self else { return }
            await ensureMediaResolved()
            let image = renderCurrentImage()
            viewModel.persist()
            UIImageWriteToSavedPhotosAlbum(
                image,
                self,
                #selector(image(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        }
    }

    @objc
    func image(_: UIImage, didFinishSavingWithError error: Error?, contextInfo _: UnsafeRawPointer) {
        if error != nil {
            Haptics.warning()
            showToast("Couldn't save to Photos")
        } else {
            Haptics.success()
            showToast("Saved to Photos")
        }
    }

    // MARK: - Copy

    func copyTapped() {
        Task { [weak self] in
            guard let self else { return }
            await ensureMediaResolved()
            let image = renderCurrentImage()
            viewModel.persist()

            var item: [String: Any] = [:]
            if let png = image.pngData() {
                item[UTType.png.identifier] = png
            }
            if let permalink {
                item[UTType.url.identifier] = permalink
            }
            UIPasteboard.general.items = item.isEmpty ? [] : [item]
            Haptics.success()
            showToast("Copied")
        }
    }

    // MARK: - Export helpers

    /// The card's permalink: the post's for a post card, the shared comment's for
    /// a comment card.
    private var permalink: URL? {
        switch content.kind {
        case .post: content.post?.permalink
        case .comment: content.chain.last(where: \.isDestination)?.permalink
        }
    }

    private var suggestedFileName: String {
        content.post?.title ?? "Spud comment"
    }

    /// Fetches the media image if the card shows media and it isn't cached yet,
    /// so the export renders with the image rather than a shimmer. Failures fall
    /// through — the card just renders without media.
    private func ensureMediaResolved() async {
        guard content.kind == .post,
              viewModel.options.showMedia,
              let url = content.post?.mediaUrl,
              loadedMediaImage == nil
        else { return }
        loadedMediaImage = await loadImage(url)
    }

    /// Builds a fresh card from the current content/options — never the live
    /// preview — and renders it per the selected canvas.
    private func renderCurrentImage() -> UIImage {
        let card: UIView
        switch content.kind {
        case .post:
            let postCard = ShareCardView(content: content, options: viewModel.options)
            postCard.setMediaImage(loadedMediaImage)
            card = postCard
        case .comment:
            card = ShareChainCardView(content: content, options: viewModel.options)
        }
        return ShareCardImageRenderer.render(cardView: card, options: viewModel.options)
    }

    private func presentFailure() {
        Haptics.warning()
        showToast("Couldn't create the image")
    }

    private func showToast(_ message: String) {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(message, in: window)
    }
}
