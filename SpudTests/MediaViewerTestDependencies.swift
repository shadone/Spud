//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
@testable import Spud

/// Minimal dependency container satisfying `MediaViewerViewController.Dependencies`
/// (just `HasImageService`) — lighter than the app-wide `FakeDependencies` superset
/// since media-viewer tests only ever need to control image loading. Shared by
/// `MediaViewerLiveTextChromeTests` and `MediaViewerLiveTextGestureTests`.
struct MediaViewerTestDependencies: HasImageService {
    let imageService: ImageServiceType
}
