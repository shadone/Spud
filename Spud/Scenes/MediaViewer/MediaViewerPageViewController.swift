//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Hosts a single zoomable image. One of these per `MediaItem`; the container
/// pages between them with a `UIPageViewController`.
final class MediaViewerPageViewController: UIViewController {
    let pageIndex: Int

    /// The zoomable host, exposed so the container can ask whether the current
    /// page is zoomed (to arbitrate the swipe-to-dismiss gesture).
    let zoomableImageView: ZoomableImageView

    /// True once this page's full-resolution load failed while a preview was on
    /// screen — i.e. only the low-resolution preview is available. The container
    /// reads this when the current page changes to (re)show its degraded pill.
    private(set) var isShowingLowResPreviewOnly = false

    /// Invoked when this page resolves to a degraded (low-res-only) state, so the
    /// container can show its "low-resolution preview" pill if this is the
    /// current page.
    var onFullImageUnavailable: ((MediaViewerPageViewController) -> Void)?

    init(
        item: MediaItem,
        pageIndex: Int,
        imageService: ImageServiceType,
        onFullImageUnavailable: ((MediaViewerPageViewController) -> Void)? = nil
    ) {
        self.pageIndex = pageIndex
        self.onFullImageUnavailable = onFullImageUnavailable
        zoomableImageView = ZoomableImageView(item: item, imageService: imageService)
        super.init(nibName: nil, bundle: nil)
        zoomableImageView.onFullImageUnavailable = { [weak self] in
            guard let self else { return }
            isShowingLowResPreviewOnly = true
            self.onFullImageUnavailable?(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = zoomableImageView
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        zoomableImageView.startLoading()
    }
}
