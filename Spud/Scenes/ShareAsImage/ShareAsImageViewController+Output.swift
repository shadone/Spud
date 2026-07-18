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

    /// Renders a fresh card and hands it to the system share sheet.
    ///
    /// Guarded against re-entrancy by ``ShareAsImageViewModel/beginExport()``:
    /// a second tap while a render is already in flight is a synchronous no-op
    /// (checked before the `Task` is even spawned), so a rapid double-tap can't
    /// race two renders or present two share sheets. The output bar is disabled
    /// with the tapped button spinning for the duration — see
    /// ``setOutputBarBusy(_:activeButton:)``.
    func shareTapped() {
        guard viewModel.beginExport() else { return }
        setOutputBarBusy(true, activeButton: shareButton)
        // Snapshot the options at the moment of the tap, before the media await:
        // the tray + preview toggles stay live during the await, so rendering
        // from the snapshot guarantees the exported card matches what the user
        // saw when they tapped.
        let options = viewModel.options
        Task { [weak self] in
            guard let self else { return }
            defer {
                viewModel.endExport()
                setOutputBarBusy(false, activeButton: shareButton)
            }
            await ensureMediaResolved(options: options)
            let image = renderCurrentImage(options: options)
            viewModel.persist()
            guard let permalink else {
                presentFailure()
                return
            }
            do {
                let pngURL = try await ShareCardImageRenderer.writePNG(
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

    /// Renders a fresh card and writes it to Photos.
    ///
    /// Unlike Share/Copy, the export guard is released in the
    /// `UIImageWriteToSavedPhotosAlbum` completion handler
    /// (``image(_:didFinishSavingWithError:contextInfo:)``), not at the end of
    /// this `Task` — the actual Photos write is asynchronous beyond the task's
    /// own body, and it's specifically a rapid double-tap here that was writing
    /// the photo twice, so the button stays busy for the full round trip.
    func saveTapped() {
        guard viewModel.beginExport() else { return }
        setOutputBarBusy(true, activeButton: saveButton)
        let options = viewModel.options
        Task { [weak self] in
            guard let self else { return }
            await ensureMediaResolved(options: options)
            let image = renderCurrentImage(options: options)
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
        viewModel.endExport()
        setOutputBarBusy(false, activeButton: saveButton)
        if error != nil {
            Haptics.warning()
            showToast("Couldn't save to Photos")
        } else {
            Haptics.success()
            showToast("Saved to Photos")
        }
    }

    // MARK: - Copy

    /// Renders a fresh card and copies it (+ the permalink) to the pasteboard.
    /// See ``shareTapped()`` for the re-entrancy guard.
    func copyTapped() {
        guard viewModel.beginExport() else { return }
        setOutputBarBusy(true, activeButton: copyButton)
        let options = viewModel.options
        Task { [weak self] in
            guard let self else { return }
            defer {
                viewModel.endExport()
                setOutputBarBusy(false, activeButton: copyButton)
            }
            await ensureMediaResolved(options: options)
            let image = renderCurrentImage(options: options)
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

    // MARK: - Output bar busy state

    /// Disables the whole output bar (and the nav-bar Done button) and swaps
    /// `activeButton`'s content for a spinner
    /// (`UIButton.Configuration.showsActivityIndicator`) while an export is in
    /// flight — mirrors `InstanceDetailViewController.setBrowseButtonBusy`.
    /// Purely the visual half of the guard; ``ShareAsImageViewModel/beginExport()``
    /// is what actually blocks a second tap from starting a second render.
    /// Done is disabled too so the editor can't be dismissed mid-export, which
    /// would orphan the pending share sheet / Photos write.
    private func setOutputBarBusy(_ busy: Bool, activeButton: UIButton) {
        for button in [shareButton, saveButton, copyButton] {
            button.isEnabled = !busy
        }
        doneButton.isEnabled = !busy
        guard var config = activeButton.configuration else { return }
        config.showsActivityIndicator = busy
        activeButton.configuration = config
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
    /// so the export renders with the image rather than a shimmer. On failure
    /// ``loadedMediaImage`` stays `nil` and ``renderCurrentImage(options:)``
    /// renders the card genuinely WITHOUT media —
    /// ``ShareAsImageViewModel/exportOptions(_:resolvedMedia:)`` drops the media
    /// section for the export — so the "Loading media…" placeholder is never
    /// baked into the PNG. Spud is offline-first, so a failed/absent fetch here
    /// is a real path. Takes the tap-time options snapshot rather than reading
    /// the live options, so a toggle during the await can't change the decision.
    private func ensureMediaResolved(options: ShareCardOptions) async {
        guard content.kind == .post,
              options.showMedia,
              let url = content.post?.mediaUrl,
              loadedMediaImage == nil
        else { return }
        loadedMediaImage = await loadImage(url)
    }

    /// Builds a fresh card from the content and the tap-time `options` snapshot —
    /// never the live preview — through the same `locale`/`timeZone` timestamp
    /// seam the preview uses, and renders it per the selected canvas. When the
    /// media never resolved, the export options drop the media section (see
    /// ``ShareAsImageViewModel/exportOptions(_:resolvedMedia:)``) so a failed
    /// fetch never bakes the loading placeholder into the PNG.
    private func renderCurrentImage(options optionsSnapshot: ShareCardOptions) -> UIImage {
        let options = viewModel.exportOptions(optionsSnapshot, resolvedMedia: loadedMediaImage != nil)
        let card: UIView
        switch content.kind {
        case .post:
            let postCard = ShareCardView(content: content, options: options, locale: locale, timeZone: timeZone)
            postCard.setMediaImage(loadedMediaImage)
            card = postCard
        case .comment:
            card = ShareChainCardView(content: content, options: options, locale: locale, timeZone: timeZone)
        }
        return ShareCardImageRenderer.render(cardView: card, options: options)
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
