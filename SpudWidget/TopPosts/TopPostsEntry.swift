//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Intents
import UIKit
import WidgetKit

/// UIImage isn't formally Sendable (UIKit is @MainActor), but the widget
/// pipeline only writes the dictionary once, then hands it to WidgetKit
/// for serialization — no further mutation, no shared write access.
struct TopPostsEntry: TimelineEntry, @unchecked Sendable {
    let date: Date

    let topPosts: TopPosts
    let images: [URL: UIImage]
}
