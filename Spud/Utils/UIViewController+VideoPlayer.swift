//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AVKit
import SpudDataKit
import SpudUtilKit
import UIKit

extension UIViewController {
    /// Presents the system video player for `url` and starts playback. Used for
    /// inline video posts (mp4 / mov / m4v); the system player provides the
    /// scrubber, full-screen, AirPlay and Picture-in-Picture controls.
    func presentVideoPlayer(url: URL) {
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        controller.player = player
        present(controller, animated: true) {
            player.play()
        }
    }

    /// Routes a tapped post video URL to inline playback. A direct video file
    /// (mp4 / mov / m4v) plays immediately. A recognized video-host page (e.g.
    /// streamable) shows a brief spinner while it is resolved to a stream, then
    /// plays inline; if resolution fails (offline, removed, API error) it falls
    /// back to opening the page with the normal link flow.
    @MainActor
    func playVideo(url: URL, appService: AppServiceType) async {
        let registry = VideoHostRegistry(pipedConfig: appService.urlSanitizerConfig)
        let overlay: VideoResolvingOverlay? = registry.recognize(url) != nil
            ? VideoResolvingOverlay.present(in: self)
            : nil

        let action = await videoPlaybackAction(forVideoAt: url, using: registry)
        overlay?.dismiss()

        // If the user navigated away during resolution, don't present on a
        // popped view controller.
        guard view.window != nil else { return }

        switch action {
        case let .play(streamUrl):
            presentVideoPlayer(url: streamUrl)
        case let .openExternally(pageUrl):
            await appService.open(url: pageUrl, on: self)
        }
    }
}
