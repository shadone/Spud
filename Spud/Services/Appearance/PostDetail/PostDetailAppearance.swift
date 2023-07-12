//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

protocol PostDetailAppearanceType: AnyObject {
//    var textSizeAdjustmentPublisher: AnyPublisher<CGFloat, Never> { get }
//    var textSizeAdjustment: CGFloat { get set }

    var commentRibbonThemePublisher: AnyPublisher<PostCommentRibbonTheme, Never> { get }
    var commentRibbonTheme: PostCommentRibbonTheme { get set }
}

class PostDetailAppearance: PostDetailAppearanceType {
    var textSizeAdjustmentPublisher: AnyPublisher<CGFloat, Never> {
        $textSizeAdjustment
    }

    @UserDefaultsBacked(key: "PostDetail.TextSizeAdjustment")
    var textSizeAdjustment: CGFloat = 0

    var commentRibbonThemePublisher: AnyPublisher<PostCommentRibbonTheme, Never> {
        $commentRibbonTheme
    }

    @UserDefaultsBacked(key: "PostDetail.CommentRibbonTheme")
    var commentRibbonTheme: PostCommentRibbonTheme = .rainbow
}
