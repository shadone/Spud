//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

@MainActor
protocol AppearanceServiceType {
    var general: GeneralAppearance { get }
    var postList: PostListAppearanceType { get }
    var postDetail: PostDetailAppearanceType { get }
}

@MainActor
protocol HasAppearanceService {
    var appearanceService: AppearanceServiceType { get }
}

@MainActor
class AppearanceService: AppearanceServiceType {
    let general = GeneralAppearance()
    let postList: PostListAppearanceType = PostListAppearance()
    let postDetail: PostDetailAppearanceType = PostDetailAppearance()
}
