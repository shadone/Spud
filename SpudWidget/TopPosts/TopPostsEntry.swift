//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Intents
import UIKit
import WidgetKit

struct TopPostsEntry: TimelineEntry {
    let date: Date

    let topPosts: TopPosts
    let images: [URL: UIImage]
}
