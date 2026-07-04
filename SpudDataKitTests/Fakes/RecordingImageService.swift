//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import CoreGraphics
import Foundation
import UIKit
@testable import SpudDataKit

/// A test double for `ImageServiceType` that records the URLs it was asked to
/// fetch (the offline downloader warms images through `fetch(_:downsampleTo:)`).
///
/// Each `fetch` immediately finishes the stream. When `yieldsReady` is `true`
/// (the default) it emits `.ready` first, so the downloader's stream-draining
/// completes as a success. When `yieldsReady` is `false` the stream ends without
/// any value — `drainImageFetch` sees no `.ready` and throws `.notReady`,
/// letting retry + swallow tests exercise that path.
///
/// URLs are recorded under an `NSLock` since the downloader drives several
/// fetches concurrently.
final class RecordingImageService: ImageServiceType, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetchedURLs: [URL] = []
    private let yieldsReady: Bool

    init(yieldsReady: Bool = true) {
        self.yieldsReady = yieldsReady
    }

    /// All URLs passed to `fetch(_:downsampleTo:)`, in completion order.
    var fetchedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _fetchedURLs
    }

    func fetch(_ url: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        record(url)
        let yieldsReady = yieldsReady
        return AsyncStream { continuation in
            if yieldsReady { continuation.yield(.ready(UIImage())) }
            continuation.finish()
        }
    }

    func fetch(_ url: URL, downsampleTo _: CGSize) -> AsyncStream<ImageLoadingState> {
        record(url)
        let yieldsReady = yieldsReady
        return AsyncStream { continuation in
            if yieldsReady { continuation.yield(.ready(UIImage())) }
            continuation.finish()
        }
    }

    private func record(_ url: URL) {
        lock.lock()
        _fetchedURLs.append(url)
        lock.unlock()
    }
}
