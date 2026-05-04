//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class GeneralAppearance {
    let upvoteIcon = UIImage(systemName: "arrow.up")!
    let downvoteIcon = UIImage(systemName: "arrow.down")!

    let upvoteSwipeActionBackgroundColor: UIColor = .systemRed.withAlphaComponent(0.8)
    let downvoteSwipeActionBackgroundColor: UIColor = .systemIndigo.withAlphaComponent(0.8)

    var upvoteButtonActiveColor: UIColor = .systemRed
    var downvoteButtonActiveColor: UIColor = .systemIndigo
}
