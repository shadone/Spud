//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

public class StaticImageService: ImageServiceType {
    public init() { }

    public func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never> {
        let bundle = Bundle(for: StaticImageService.self)
        return .just(.ready(UIImage(named: "tv-pattern", in: bundle, with: nil)!))
    }
}
