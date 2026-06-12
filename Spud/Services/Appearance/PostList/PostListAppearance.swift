//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit
import SpudUtilKit

@MainActor
protocol PostListAppearanceType: AnyObject {
    /// Text-scale override layered on top of Dynamic Type, in points relative
    /// to the system body size.
    var textSizeAdjustment: CGFloat { get set }

    /// Post-list density (comfortable / compact).
    var postDensity: PostDensity { get }

    /// Where the thumbnail sits (left / right / hidden).
    var thumbnailPosition: ThumbnailPosition { get }
}

/// Resolves post-list display preferences for the cell layer. The reading /
/// display preferences (density, thumbnail position, text scale) live in
/// ``PreferencesService`` so they react live across the app; this type reads
/// them through that service so a single source of truth drives both the
/// settings UI and the rendered feed.
@MainActor
final class PostListAppearance: PostListAppearanceType {
    private let preferencesService: PreferencesServiceType

    init(preferencesService: PreferencesServiceType) {
        self.preferencesService = preferencesService
    }

    @UserDefaultsBacked(key: "PostList.PreviewImageSize")
    var previewImageSize: PostListPreviewImageSize = .medium

    @UserDefaultsBacked(key: "PostList.DisplayVotingButtons")
    var displayVotingButtons: Bool = true

    /// Forwards to the user's text-scale preference so the cell view-model and
    /// the settings screen share one value.
    var textSizeAdjustment: CGFloat {
        get { preferencesService.postTextScale }
        set { preferencesService.postTextScale = newValue }
    }

    var postDensity: PostDensity {
        preferencesService.postDensity
    }

    var thumbnailPosition: ThumbnailPosition {
        preferencesService.thumbnailPosition
    }
}
