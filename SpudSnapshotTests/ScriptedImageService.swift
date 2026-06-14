//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import UIKit

/// A deterministic `ImageServiceType` for snapshot tests that scripts the
/// outcome of each `fetch` call.
///
/// Unlike `StaticImageService` (always one outcome), this drives the post-detail
/// header through its distinct states: a successful image, a hard failure (the
/// failure plate), and an in-flight retry that never resolves (the spinner
/// plate). Responses are consumed in order; the last entry repeats, so a single
/// `[.ready(image)]` serves any number of fetches.
final class ScriptedImageService: ImageServiceType, @unchecked Sendable {
    enum Response {
        /// Yield `.loading` then `.ready(image)`, then finish.
        case ready(UIImage)
        /// Yield `.loading` then `.failure`, then finish.
        case failure
        /// Yield `.loading` and never finish — models a retry still in flight,
        /// holding the failure plate in its spinning "Loading image…" state.
        case loadingForever
        /// Yield `.loading(thumbnail:)` carrying a preview image and never finish
        /// — models the full image still downloading while a low-res thumbnail is
        /// shown under the spinner.
        case loadingThumbnail(UIImage)
    }

    private let responses: [Response]
    private let knownSize: CGSize?
    private let lock = NSLock()
    private var callIndex = 0

    /// - Parameter knownSize: when set, `imageSize(for:)` returns it, modelling
    ///   an image whose size the service already knows (e.g. the post list
    ///   fetched its thumbnail), so the header reserves the exact placeholder
    ///   height up front.
    init(_ responses: [Response], knownSize: CGSize? = nil) {
        self.responses = responses.isEmpty ? [.failure] : responses
        self.knownSize = knownSize
    }

    func imageSize(for url: URL) -> CGSize? {
        knownSize
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
            continuation.yield(.loading(thumbnail: nil))
            switch response {
            case let .ready(image):
                continuation.yield(.ready(image))
                continuation.finish()
            case .failure:
                continuation.yield(.failure)
                continuation.finish()
            case .loadingForever:
                break
            case let .loadingThumbnail(image):
                continuation.yield(.loading(thumbnail: image))
                // Never finish: the full image is still "downloading".
            }
        }
    }
}
