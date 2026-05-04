//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

protocol PostListAppearanceType: AnyObject {
    var textSizeAdjustment: CGFloat { get set }
}

class PostListAppearance: PostListAppearanceType {
    @UserDefaultsBacked(key: "PostList.PreviewImageSize")
    var previewImageSize: PostListPreviewImageSize = .medium

    @UserDefaultsBacked(key: "PostList.TextSizeAdjustment")
    var textSizeAdjustment: CGFloat = 0

    @UserDefaultsBacked(key: "PostList.DisplayVotingButtons")
    var displayVotingButtons: Bool = true
}
