//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import OSLog
import SpudUIKit
import UIKit
import WebKit

private let logger = Logger(subsystem: "info.ddenis.Spud", category: "WebArchiveReader")

/// An in-app reader that renders a previously-captured `.webarchive` file in a
/// `WKWebView`, fully offline.
///
/// Reached when the user opens an external link while offline and a web archive
/// was saved for that link (see `AppService.open(url:on:)` →
/// `resolveOpenStrategy`). A web archive is a self-contained snapshot of the
/// page (HTML + subresources) so it renders without a network connection.
///
/// Chrome is styled like the in-app browser: a Done button to dismiss, a share
/// button (shares the **original live URL**, not the local file), and an
/// "Open in browser" overflow action that opens the live page in the system
/// browser — handy once the user is back online. A subtle "Saved offline"
/// subtitle in the title area makes clear this is a stored snapshot, not the
/// live page.
///
/// Present this inside a `UINavigationController` modally — see
/// ``makeModal(archiveFileURL:originalURL:title:)``.
final class OfflineWebArchiveReaderViewController: UIViewController {
    /// On-disk `.webarchive` file to render.
    private let archiveFileURL: URL

    /// The live page URL the archive was captured from. Used by Share and
    /// "Open in browser" — both act on the real page, never the local file.
    private let originalURL: URL

    /// Best-known page title (from the archive's index row), shown until/unless
    /// the loaded `WKWebView` reports a more specific `title`.
    private let initialTitle: String?

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // A web archive is self-contained; no extra data stores or JS bridges
        // are needed. Default configuration renders the snapshot as captured.
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        // The archive is a frozen snapshot — let the content drive the title via
        // KVO below rather than allowing in-page navigation to live URLs.
        return webView
    }()

    private var titleObservation: NSKeyValueObservation?

    /// Whether the initial `.webarchive` load has finished. Until it has, the
    /// `file:`-scheme navigation that renders the snapshot must be allowed
    /// through; once it has, any further navigation is an in-page link tap that
    /// would go to the live network (defeating the offline snapshot) and is
    /// instead cancelled and routed to the system browser (see
    /// ``webView(_:decidePolicyFor:decisionHandler:)``).
    private var hasLoadedArchive = false

    /// - Parameters:
    ///   - archiveFileURL: On-disk `.webarchive` file to load.
    ///   - originalURL: The live page URL the archive was captured from (used by
    ///     Share and Open-in-browser).
    ///   - title: Best-known page title, when available.
    init(archiveFileURL: URL, originalURL: URL, title: String?) {
        self.archiveFileURL = archiveFileURL
        self.originalURL = originalURL
        initialTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.background

        configureNavigationItem()

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Keep the navigation title in sync with the loaded page's title; fall
        // back to the index-row title (or the host) until the web view reports one.
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                self?.updateTitle(from: webView.title)
            }
        }

        loadArchive()
    }

    // MARK: - Loading

    /// Load the local `.webarchive`. Web archives load from a file URL; grant
    /// read access to the containing directory so `WKWebView` can resolve the
    /// archive's bundled subresources.
    private func loadArchive() {
        webView.loadFileURL(
            archiveFileURL,
            allowingReadAccessTo: archiveFileURL.deletingLastPathComponent()
        )
    }

    // MARK: - Navigation item

    private func configureNavigationItem() {
        updateTitle(from: initialTitle)

        navigationItem.leftBarButtonItem = {
            let item = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(doneTapped)
            )
            item.accessibilityLabel = NSLocalizedString(
                "Done",
                comment: "Accessibility label for the button that closes the offline web archive reader"
            )
            return item
        }()

        let shareItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        shareItem.accessibilityLabel = NSLocalizedString(
            "Share",
            comment: "Accessibility label for the share button in the offline web archive reader"
        )

        let overflowItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: makeOverflowMenu()
        )
        overflowItem.accessibilityLabel = NSLocalizedString(
            "More",
            comment: "Accessibility label for the overflow menu button in the offline web archive reader"
        )

        navigationItem.rightBarButtonItems = [overflowItem, shareItem]
    }

    /// Builds the overflow menu. "Open in browser" opens the **live** URL in the
    /// system browser — useful once the user is back online and wants the real,
    /// current page rather than the saved snapshot.
    private func makeOverflowMenu() -> UIMenu {
        let openInBrowser = UIAction(
            title: NSLocalizedString(
                "Open in Browser",
                comment: "Offline reader overflow action that opens the live page in the system browser"
            ),
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.openLiveURLInSystemBrowser()
        }
        return UIMenu(children: [openInBrowser])
    }

    /// Opens the live page in the system browser. Shared by the overflow action
    /// and the in-page-link interception (see the navigation delegate): both honor
    /// the user's intent to leave the frozen snapshot for the live web.
    private func openLiveURLInSystemBrowser() {
        UIApplication.shared.open(originalURL)
    }

    /// Sets the navigation title to the best available page title and pins a
    /// subtle "Saved offline" subtitle (with a small offline glyph) beneath it,
    /// so the user always knows they're reading a stored snapshot.
    private func updateTitle(from pageTitle: String?) {
        let resolved = [pageTitle, initialTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? originalURL.host
            ?? NSLocalizedString(
                "Saved Page",
                comment: "Fallback title for the offline web archive reader when no page title is known"
            )

        title = resolved
        navigationItem.titleView = makeTitleView(title: resolved)
    }

    /// A two-line title view: the page title on top, a muted "Saved offline"
    /// caption (preceded by an offline glyph) below. The caption distinguishes
    /// the snapshot from a live page at a glance.
    private func makeTitleView(title: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textAlignment = .center

        let subtitleText = NSLocalizedString(
            "Saved offline",
            comment: "Subtitle in the offline web archive reader indicating the page is a stored snapshot"
        )

        let subtitleLabel = UILabel()
        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.textAlignment = .center

        // Prefix the caption with an offline glyph as an inline image attachment.
        let attributed = NSMutableAttributedString()
        if let glyph = UIImage(systemName: "wifi.slash") {
            let attachment = NSTextAttachment()
            attachment.image = glyph.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            // Scale the glyph down to caption size and nudge it onto the baseline.
            let captionFont = UIFont.preferredFont(forTextStyle: .caption2)
            let glyphSize = captionFont.capHeight
            attachment.bounds = CGRect(x: 0, y: 0, width: glyphSize, height: glyphSize)
            attributed.append(NSAttributedString(attachment: attachment))
            attributed.append(NSAttributedString(string: " "))
        }
        attributed.append(NSAttributedString(string: subtitleText))
        subtitleLabel.attributedText = attributed

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0

        // The title area is read as one element by VoiceOver: "<page>, saved offline".
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = String(
            format: NSLocalizedString(
                "%@, saved offline",
                comment: "VoiceOver label for the offline reader title; %@ is the page title"
            ),
            title
        )
        stack.accessibilityTraits = .header

        return stack
    }

    // MARK: - Actions

    @objc
    private func doneTapped() {
        dismiss(animated: true)
    }

    @objc
    private func shareTapped() {
        // Share the live URL, never the on-disk archive file path.
        presentShareSheet(for: originalURL, sourceItem: navigationItem.rightBarButtonItems?.last)
    }
}

// MARK: - WKNavigationDelegate

extension OfflineWebArchiveReaderViewController: WKNavigationDelegate {
    /// Gate every navigation so the reader stays offline.
    ///
    /// The archive renders from a `file:` URL (and may reference `about:blank` /
    /// `data:` subresources). The FIRST such load is the snapshot itself and must
    /// be allowed. Once that initial load has finished (``hasLoadedArchive``), any
    /// further navigation is the user tapping a link inside the archived HTML —
    /// which `WKWebView` would otherwise load LIVE over the network, defeating the
    /// offline snapshot (a blank/error page when offline) and silently leaving the
    /// stored copy. So we CANCEL it; for an http(s) tap we honor the user's intent
    /// by opening the destination in the system browser instead of failing
    /// silently. Non-http(s) schemes (file/about/data) are allowed so the snapshot
    /// and its bundled subresources keep rendering.
    /// Uses the `async` form of the requirement (the completion-handler form's
    /// `decisionHandler` is `@escaping @MainActor @Sendable`, which is fiddly to
    /// match exactly; the `async` overload is cleaner and the VC is already
    /// `@MainActor`).
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased()
        let isWebScheme = scheme == "http" || scheme == "https"

        // Before the snapshot has loaded, allow the file:/about:/data: navigation
        // that renders it. (A captured page should not be issuing live http(s)
        // requests at this stage; if it somehow does, treat it as a link tap.)
        guard hasLoadedArchive else {
            if isWebScheme {
                if let url {
                    await UIApplication.shared.open(url)
                }
                return .cancel
            }
            return .allow
        }

        // After the snapshot loaded: any new web navigation is an in-page link
        // tap. Cancel the live load and hand the tapped URL to the system browser
        // so the tap is honored rather than silently failing. Non-web schemes
        // (rare here) are simply cancelled — we never go live for the snapshot.
        if isWebScheme, let url {
            await UIApplication.shared.open(url)
        }
        return .cancel
    }

    /// The initial `.webarchive` load finished: from here on, treat navigations as
    /// in-page link taps (see ``webView(_:decidePolicyFor:decisionHandler:)``).
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        hasLoadedArchive = true
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        logger.error("Failed to load offline web archive: \(String(describing: error), privacy: .public)")
    }
}

// MARK: - Modal presentation

extension OfflineWebArchiveReaderViewController {
    /// Wraps the reader in a `UINavigationController` ready to present modally,
    /// matching how the in-app browser appears.
    ///
    /// - Parameters:
    ///   - archiveFileURL: On-disk `.webarchive` file to render.
    ///   - originalURL: The live page URL the archive was captured from.
    ///   - title: Best-known page title, when available.
    /// - Returns: A configured `UINavigationController` to `present`.
    static func makeModal(
        archiveFileURL: URL,
        originalURL: URL,
        title: String?
    ) -> UINavigationController {
        let reader = OfflineWebArchiveReaderViewController(
            archiveFileURL: archiveFileURL,
            originalURL: originalURL,
            title: title
        )
        let navigationController = UINavigationController(rootViewController: reader)
        navigationController.modalPresentationStyle = .automatic
        return navigationController
    }
}
