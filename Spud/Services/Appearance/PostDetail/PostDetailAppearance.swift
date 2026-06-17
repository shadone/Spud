//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import UIKit

protocol PostDetailAppearanceType: AnyObject {
    var textSizeAdjustment: CGFloat { get set }
    var commentRibbonTheme: PostCommentRibbonTheme { get set }
}

class PostDetailAppearance: PostDetailAppearanceType {
    @UserDefaultsBacked(key: "PostDetail.TextSizeAdjustment")
    var textSizeAdjustment: CGFloat = 0

    @UserDefaultsBacked(key: "PostDetail.CommentRibbonTheme")
    var commentRibbonTheme: PostCommentRibbonTheme = .rainbow
}
