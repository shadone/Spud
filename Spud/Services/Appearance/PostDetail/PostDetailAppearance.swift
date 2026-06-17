//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import UIKit

@MainActor
protocol PostDetailAppearanceType: AnyObject {
    var textSizeAdjustment: CGFloat { get set }
    var commentRibbonTheme: PostCommentRibbonTheme { get set }
}

/// Resolves post-detail display preferences. The text-scale override is the
/// same user preference the post list and the Display settings screen read, so
/// one "Text Size" slider drives every post-text surface; it is read through
/// ``PreferencesService`` rather than a detail-specific key.
@MainActor
final class PostDetailAppearance: PostDetailAppearanceType {
    private let preferencesService: PreferencesServiceType

    init(preferencesService: PreferencesServiceType) {
        self.preferencesService = preferencesService
    }

    /// Forwards to the user's text-scale preference so post detail, the post
    /// list, and the settings screen share one value.
    var textSizeAdjustment: CGFloat {
        get { preferencesService.postTextScale }
        set { preferencesService.postTextScale = newValue }
    }

    @UserDefaultsBacked(key: "PostDetail.CommentRibbonTheme")
    var commentRibbonTheme: PostCommentRibbonTheme = .rainbow
}
