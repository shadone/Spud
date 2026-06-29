//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import SpudDataKit

/// A test double for `WebArchiveCapturing` used by `OfflineDownloadServiceTests`.
///
/// Records every URL it was asked to capture and returns canned archive data (or
/// nil, to exercise the best-effort-skip path). No real `WKWebView` — the tests
/// must not touch WebKit. The captured URLs are guarded by an `NSLock` because
/// the downloader drives several `processTarget`s concurrently (they funnel here
/// one-at-a-time in production, but the recording must be thread-safe regardless).
final class RecordingWebArchiveCapturer: WebArchiveCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var _capturedURLs: [URL] = []

    /// The canned archive bytes returned on a successful capture.
    private let cannedData: Data
    /// The canned page title returned on a successful capture.
    private let cannedTitle: String?
    /// When true, every `capture` returns nil — modelling a load error / timeout
    /// so a test can assert the download survives a failed capture.
    private let returnsNil: Bool

    init(
        cannedData: Data = Data("<webarchive>".utf8),
        cannedTitle: String? = "Example Page",
        returnsNil: Bool = false
    ) {
        self.cannedData = cannedData
        self.cannedTitle = cannedTitle
        self.returnsNil = returnsNil
    }

    /// Every URL passed to `capture`, in completion order.
    var capturedURLs: [URL] {
        lock.withLock { _capturedURLs }
    }

    func capture(_ url: URL, timeout _: TimeInterval) async -> WebArchiveCaptureResult? {
        // `withLock` (scoped) rather than `lock()`/`unlock()` — the latter is
        // unavailable from this `async` context under strict concurrency.
        lock.withLock { _capturedURLs.append(url) }
        if returnsNil { return nil }
        return WebArchiveCaptureResult(data: cannedData, title: cannedTitle)
    }
}
