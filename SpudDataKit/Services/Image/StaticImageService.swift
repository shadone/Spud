//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import UIKit

public final class StaticImageService: ImageServiceType, @unchecked Sendable {
    public init() { }

    public func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AsyncStream<ImageLoadingState> {
        AsyncStream { continuation in
            let bundle = Bundle(for: StaticImageService.self)
            if let image = UIImage(named: "tv-pattern", in: bundle, with: nil) {
                continuation.yield(.ready(image))
            } else {
                continuation.yield(.failure)
            }
            continuation.finish()
        }
    }

    public func fetchPublisher(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AnyPublisher<ImageLoadingState, Never> {
        let bundle = Bundle(for: StaticImageService.self)
        guard let image = UIImage(named: "tv-pattern", in: bundle, with: nil) else {
            return .just(.failure)
        }
        return .just(.ready(image))
    }
}
