//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import WebKit

private let logger = Logger.webArchive

/// The result of a successful web-archive capture: the `.webarchive`
/// (`WKWebView.createWebArchiveData()`) blob plus the captured page title.
///
/// A small `Sendable` value so it can cross the capturer's `@MainActor`
/// boundary back to the (actor-isolated) ``OfflineDownloadService``.
public struct WebArchiveCaptureResult: Sendable, Equatable {
    /// The serialized web archive — the full page (HTML + subresources) in
    /// Apple's `.webarchive` format, ready to hand to
    /// ``OfflineWebArchiveStore/upsertWebArchive(url:postServerId:title:data:)``
    /// and later reload offscreen in the offline reader (slice 2).
    public let data: Data

    /// The page's `<title>`, when WebKit reported one. Used as a human-readable
    /// label in the archive store (and the offline reader's nav title).
    public let title: String?

    public init(data: Data, title: String?) {
        self.data = data
        self.title = title
    }
}

/// Captures an external web page as a `.webarchive` blob, best-effort.
///
/// Used by the offline downloader to snapshot each external-link post's target
/// page so it can be read offline later (slice 2). A failure (load error,
/// timeout, or WebKit refusing to serialize) returns nil — the downloader skips
/// that page and carries on; capturing pages is never allowed to abort a run.
public protocol WebArchiveCapturing: Sendable {
    /// Capture `url` as a web archive, giving up after `timeout` seconds.
    ///
    /// - Returns: the archive bytes + page title on success, or nil on any
    ///   failure (navigation error, timeout, or empty/failed serialization).
    ///   Best-effort by contract — callers must tolerate nil.
    func capture(_ url: URL, timeout: TimeInterval) async -> WebArchiveCaptureResult?
}

/// `WKWebView`-backed ``WebArchiveCapturing``.
///
/// **`@MainActor`.** `WKWebView` (and its `WKNavigationDelegate`) are main-actor
/// bound, so the whole capturer is too. The offline downloader is an actor; it
/// must `await` across to the main actor for every capture — which is fine, the
/// captures are deliberately slow and serialized anyway (see below).
///
/// **One reused web view, serialized.** A single offscreen `WKWebView` is reused
/// across captures (constructing one per page is costly and leaks process
/// memory). Because that single view can only load one page at a time, captures
/// MUST be serialized: a second `capture(...)` arriving while one is in flight
/// waits for the first to finish (an in-flight continuation queue). The offline
/// downloader funnels its archive captures sequentially anyway, but the guard
/// here makes the capturer correct under any caller.
///
/// **Cost.** Each capture spins up a real page load (network + JS + subresource
/// fetches) and then serializes the whole DOM + resources to a `.webarchive`.
/// This is heavy — seconds per page and potentially megabytes of output — which
/// is exactly why the feature is opt-in and the captures run one-at-a-time off
/// the main download fan-out.
///
/// **Best-effort.** Every failure path (navigation error, timeout, serialization
/// failure) returns nil; the capturer never throws and never traps.
@MainActor
public final class WebArchiveCapturer: WebArchiveCapturing {
    /// The single reused offscreen web view. Lazily created on first capture so a
    /// capturer that's constructed-but-never-used costs nothing.
    private var webView: WKWebView?

    /// Bridges `WKWebView` navigation callbacks to the awaiting `capture(...)`.
    /// Held for the web view's lifetime (the web view references it weakly via
    /// `navigationDelegate`, so the capturer must retain it).
    private var navigationCoordinator: NavigationCoordinator?

    /// Tail of the serial capture chain. Each `capture(...)` builds a task that
    /// first awaits the previous tail (so the single reused web view is only ever
    /// driven by one capture at a time), then performs its own capture, and
    /// installs itself as the new tail. Concurrent callers therefore queue in
    /// arrival order rather than racing the shared web view.
    ///
    /// `Task` is a value type (no identity), so serialization is expressed by
    /// chaining each task onto its predecessor — not by comparing tokens.
    private var captureChainTail: Task<Void, Never>?

    public init() { }

    public func capture(_ url: URL, timeout: TimeInterval) async -> WebArchiveCaptureResult? {
        // Chain this capture after whatever is currently queued. We need the
        // result out of the chained task, so park it in a box the task fills.
        let previousTail = captureChainTail
        let resultBox = ResultBox()

        let task = Task { @MainActor in
            // Wait for the predecessor to finish using the web view before
            // claiming it. (A finished/absent predecessor returns immediately.)
            await previousTail?.value
            resultBox.value = await self.performCapture(url, timeout: timeout)
        }
        captureChainTail = task
        await task.value
        return resultBox.value
    }

    /// One-shot box letting a chained `@MainActor` task hand its result back to
    /// the awaiting `capture(...)`. Only ever touched on the main actor (the task
    /// is `@MainActor`, and the reader awaits the task first), so the
    /// `@unchecked Sendable` is sound.
    private final class ResultBox: @unchecked Sendable {
        var value: WebArchiveCaptureResult?
    }

    // MARK: - Private

    /// Drives one capture: load the page, await `didFinish` or the timeout, then
    /// serialize the archive. Assumes exclusive use of the web view (the caller's
    /// in-flight guard provides that).
    private func performCapture(_ url: URL, timeout: TimeInterval) async -> WebArchiveCaptureResult? {
        let webView = ensureWebView()
        let coordinator = navigationCoordinator

        // Kick off the load, then await completion or the timeout (whichever
        // comes first) inside the coordinator. The timeout lives in the
        // coordinator (not a racing task group here) so the whole method stays
        // cleanly main-actor isolated.
        webView.load(URLRequest(url: url))
        let loaded = await coordinator?.awaitNavigation(timeout: timeout) ?? false

        guard loaded else {
            logger.debug("Web archive capture timed out or failed to load: \(url.absoluteString, privacy: .public)")
            // Stop the (possibly still-loading) navigation so the reused web view
            // is idle for the next capture.
            webView.stopLoading()
            // Drop the resolved/abandoned navigation token so the next capture
            // starts from a clean delegate state.
            coordinator?.reset()
            return nil
        }

        // Serialize the loaded page. WKWebView's completion-handler API is bridged
        // to async via a checked continuation.
        let data: Data? = await withCheckedContinuation { continuation in
            webView.createWebArchiveData { result in
                switch result {
                case let .success(data):
                    continuation.resume(returning: data)
                case let .failure(error):
                    logger.debug("Web archive serialization failed for \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }

        let title = webView.title
        coordinator?.reset()

        guard let data, !data.isEmpty else { return nil }
        return WebArchiveCaptureResult(data: data, title: title.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Lazily build the reused offscreen web view + its navigation coordinator.
    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let coordinator = NavigationCoordinator()
        // A nonpersistent data store keeps captured pages out of the app's
        // cookie/cache jar (these are throwaway offscreen loads).
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        view.navigationDelegate = coordinator
        webView = view
        navigationCoordinator = coordinator
        return view
    }

    /// Bridges `WKNavigationDelegate` callbacks into an awaitable signal, with a
    /// built-in timeout.
    ///
    /// `@MainActor` (WebKit calls its delegate on the main actor). A single
    /// pending continuation is resolved by the FIRST of: `didFinish` (true), any
    /// failure callback (false), or the timeout (false). All resolution funnels
    /// through ``resolve(_:)`` which clears the continuation and cancels the
    /// timeout, so the continuation is resumed exactly once. ``reset()`` clears
    /// any stale continuation between captures.
    @MainActor
    private final class NavigationCoordinator: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Bool, Never>?
        /// The in-flight timeout task for the current navigation, cancelled the
        /// moment the navigation resolves by any means.
        private var timeoutTask: Task<Void, Never>?

        /// Suspend until the current navigation finishes (true), fails (false),
        /// or `timeout` seconds elapse (false). The timeout is a polite bound so
        /// a hung host can't stall the (serialized) capturer indefinitely.
        func awaitNavigation(timeout: TimeInterval) async -> Bool {
            await withCheckedContinuation { continuation in
                // A leftover continuation should never happen (captures are
                // serialized), but if one lingers, resolve it false rather than
                // leak it.
                self.continuation?.resume(returning: false)
                self.continuation = continuation

                let nanoseconds = UInt64(timeout * 1_000_000_000)
                timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.resolve(false)
                }
            }
        }

        /// Discard any unresolved continuation so the next capture starts clean.
        func reset() {
            resolve(false)
        }

        /// Resume the pending continuation exactly once and tear down the timeout.
        private func resolve(_ value: Bool) {
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation?.resume(returning: value)
            continuation = nil
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            resolve(true)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError _: any Error) {
            resolve(false)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: any Error) {
            resolve(false)
        }
    }
}
