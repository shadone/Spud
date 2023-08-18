//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

protocol PostListAppearanceType: AnyObject {
//    var previewImageSizePublisher: AnyPublisher<PostListPreviewImageSize, Never> { get }
//    var previewImageSize: PostListPreviewImageSize { get set }

    var textSizeAdjustmentPublisher: AnyPublisher<CGFloat, Never> { get }
    var textSizeAdjustment: CGFloat { get set }

//    var displayVotingButtonsPublisher: AnyPublisher<Bool, Never> { get }
//    var displayVotingButtons: Bool { get set }
}

class PostListAppearance: PostListAppearanceType {
    var previewImageSizePublisher: AnyPublisher<PostListPreviewImageSize, Never> {
        $previewImageSize
    }

    @UserDefaultsBacked(key: "PostList.PreviewImageSize")
    var previewImageSize: PostListPreviewImageSize = .medium

    var textSizeAdjustmentPublisher: AnyPublisher<CGFloat, Never> {
        $textSizeAdjustment
    }

    @UserDefaultsBacked(key: "PostList.TextSizeAdjustment")
    var textSizeAdjustment: CGFloat = 0

    var displayVotingButtonsPublisher: AnyPublisher<Bool, Never> {
        $displayVotingButtons
    }

    @UserDefaultsBacked(key: "PostList.DisplayVotingButtons")
    var displayVotingButtons: Bool = true
}
