//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AVKit
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
}
