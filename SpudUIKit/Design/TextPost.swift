//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension Design {
    enum TextPost {
        public enum Thumbnail {
            public static let background = Asset.TextPost.Thumbnail.background.resource
            public static let icon = SymbolImageResource(systemName: "text.justifyleft")
            public static let iconTint = Asset.TextPost.Thumbnail.iconTint.resource
        }
    }
}
