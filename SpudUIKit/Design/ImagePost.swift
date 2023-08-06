//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension Design {
    enum ImagePost {
        public enum BrokenThumbnail {
            public static let background = Asset.ImagePost.BrokenThumbnail.background.resource
            public static let icon = SymbolImageResource(systemName: "questionmark.square.dashed")
            public static let iconTint = Asset.ImagePost.BrokenThumbnail.iconTint.resource
        }
    }
}
