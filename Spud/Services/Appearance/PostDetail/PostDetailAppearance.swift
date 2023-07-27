//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Down
import Foundation
import UIKit

protocol PostDetailAppearanceType: AnyObject {
    var bodyStylerConfiguration: AnyPublisher<DownStylerConfiguration, Never> { get }

//    var textSizeAdjustmentPublisher: AnyPublisher<CGFloat, Never> { get }
//    var textSizeAdjustment: CGFloat { get set }

    var commentRibbonThemePublisher: AnyPublisher<PostCommentRibbonTheme, Never> { get }
    var commentRibbonTheme: PostCommentRibbonTheme { get set }
}

class PostDetailAppearance: PostDetailAppearanceType {
    static func bodyStylerConfiguration(for textSizeAdjustment: CGFloat) -> DownStylerConfiguration {
        let fonts = StaticFontCollection(
            heading1: .systemFont(ofSize: UIFont.systemFontSize + 11 + textSizeAdjustment),
            heading2: .systemFont(ofSize: UIFont.systemFontSize + 7 + textSizeAdjustment),
            heading3: .systemFont(ofSize: UIFont.systemFontSize + 3 + textSizeAdjustment),
            heading4: .systemFont(ofSize: UIFont.systemFontSize + 3 + textSizeAdjustment),
            heading5: .systemFont(ofSize: UIFont.systemFontSize + 3 + textSizeAdjustment),
            heading6: .systemFont(ofSize: UIFont.systemFontSize + 3 + textSizeAdjustment),
            body: .systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment),
            code: UIFont(name: "menlo", size: UIFont.systemFontSize + textSizeAdjustment) ?? .systemFont(ofSize: UIFont.systemFontSize + textSizeAdjustment),
            listItemPrefix: .monospacedDigitSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)
        )

        let colors = StaticColorCollection(
            heading1: UIColor.label,
            heading2: UIColor.label,
            heading3: UIColor.label,
            heading4: UIColor.label,
            heading5: UIColor.label,
            heading6: UIColor.label,
            body: UIColor.label,
            code: UIColor.label,
            link: UIColor.link,
            quote: UIColor.secondaryLabel,
            quoteStripe: UIColor.secondaryLabel,
            thematicBreak: UIColor.tertiaryLabel,
            listItemPrefix: UIColor.secondaryLabel,
            codeBlockBackground: UIColor.quaternaryLabel
        )

        var paragraphStyles = StaticParagraphStyleCollection()
        paragraphStyles.body = {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacingBefore = 8
            paragraphStyle.paragraphSpacing = 8
            return paragraphStyle
        }()

        return DownStylerConfiguration(
            fonts: fonts,
            colors: colors,
            paragraphStyles: paragraphStyles,
            listItemOptions: ListItemOptions(),
            quoteStripeOptions: QuoteStripeOptions(),
            thematicBreakOptions: ThematicBreakOptions(),
            codeBlockOptions: CodeBlockOptions()
        )
    }

    var bodyStylerConfiguration: AnyPublisher<DownStylerConfiguration, Never> {
        $textSizeAdjustment
            .map { textSizeAdjustment -> DownStylerConfiguration in
                Self.bodyStylerConfiguration(for: textSizeAdjustment)
            }
            .eraseToAnyPublisher()
    }

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
