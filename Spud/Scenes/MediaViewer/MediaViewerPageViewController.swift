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

    init(item: MediaItem, pageIndex: Int, imageService: ImageServiceType) {
        self.pageIndex = pageIndex
        zoomableImageView = ZoomableImageView(item: item, imageService: imageService)
        super.init(nibName: nil, bundle: nil)
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
