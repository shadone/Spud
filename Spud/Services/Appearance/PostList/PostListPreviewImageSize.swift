//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum PostListPreviewImageSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var height: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 70
        case .large: return 140
        }
    }
}
