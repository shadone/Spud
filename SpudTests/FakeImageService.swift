//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

/// A deterministic `ImageServiceType` for media-viewer tests, modelled on
/// `ScriptedImageService`. Only `fetch(_:thumbnail:)` is implemented; the
/// protocol's default implementations cover the rest. Shared by
/// `ZoomableImageViewLoadingIndicatorTests`, `ZoomableImageViewLiveTextTests`,
/// `MediaViewerLiveTextChromeTests`, and `MediaViewerLiveTextGestureTests`.
final class FakeImageService: ImageServiceType, @unchecked Sendable {
    enum Response {
        /// Yield `.loading` then `.ready(image)`, then finish.
        case ready(UIImage)
        /// Yield `.loading` then `.failure`, then finish.
        case failure
        /// Yield `.loading` and never finish — models an in-flight fetch.
        case loadingForever
        /// Yield `.loading(thumbnail:)` carrying a real thumbnail image, then
        /// never finish — models a thumbnail arriving over the network while
        /// the full-resolution fetch is still in flight (mirrors
        /// `.loadingForever`, but with a thumbnail payload instead of `nil`).
        case loadingForeverWithThumbnail(UIImage)
    }

    private let responses: [Response]
    private let lock = NSLock()
    private var callIndex = 0

    init(_ responses: [Response]) {
        self.responses = responses.isEmpty ? [.failure] : responses
    }

    func fetch(
        _ url: URL,
        thumbnail thumbnailUrl: URL?
    ) -> AsyncStream<ImageLoadingState> {
        let response: Response = {
            lock.lock()
            defer { lock.unlock() }
            let index = min(callIndex, responses.count - 1)
            callIndex += 1
            return responses[index]
        }()

        return AsyncStream { continuation in
            switch response {
            case let .ready(image):
                continuation.yield(.loading(thumbnail: nil))
                continuation.yield(.ready(image))
                continuation.finish()
            case .failure:
                continuation.yield(.loading(thumbnail: nil))
                continuation.yield(.failure)
                continuation.finish()
            case .loadingForever:
                continuation.yield(.loading(thumbnail: nil))
            case let .loadingForeverWithThumbnail(thumbnail):
                continuation.yield(.loading(thumbnail: thumbnail))
            }
        }
    }
}
