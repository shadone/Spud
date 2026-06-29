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
/// Each `fetch` immediately yields `.ready` and finishes, so the downloader's
/// stream-draining completes without real I/O. URLs are recorded under an
/// `NSLock` since the downloader drives several fetches concurrently.
final class RecordingImageService: ImageServiceType, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetchedURLs: [URL] = []

    init() { }

    /// All URLs passed to `fetch(_:downsampleTo:)`, in completion order.
    var fetchedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _fetchedURLs
    }

    func fetch(_ url: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        record(url)
        return AsyncStream { continuation in
            continuation.yield(.ready(UIImage()))
            continuation.finish()
        }
    }

    func fetch(_ url: URL, downsampleTo _: CGSize) -> AsyncStream<ImageLoadingState> {
        record(url)
        return AsyncStream { continuation in
            continuation.yield(.ready(UIImage()))
            continuation.finish()
        }
    }

    private func record(_ url: URL) {
        lock.lock()
        _fetchedURLs.append(url)
        lock.unlock()
    }
}
