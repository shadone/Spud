//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import UIKit
import UniformTypeIdentifiers

/// "Open in Spud" action extension. Takes a shared web URL from any app, wraps
/// it in the app's `resolve` deep link, and hands it to the host app to resolve
/// and route. The extension itself does no networking and shows no UI of its
/// own — it opens the app and finishes immediately.
final class ActionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleSharedURL() }
    }

    private func handleSharedURL() async {
        guard let url = await firstWebURL() else {
            finish()
            return
        }
        let deepLink = URL.SpudInternalLink.objectAtURL(url: url).url
        openInHostApp(deepLink)
    }

    /// The first `http(s)` URL attachment across the extension's input items.
    private func firstWebURL() async -> URL? {
        let urlType = UTType.url.identifier
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(urlType) {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
                        continuation.resume(returning: item as? URL)
                    }
                }
                if let url, url.scheme == "http" || url.scheme == "https" {
                    return url
                }
            }
        }
        return nil
    }

    /// Opens a URL in the host app. Extensions cannot use `UIApplication.shared`,
    /// and `NSExtensionContext.open` no-ops for `com.apple.ui-services` action
    /// extensions, so walk the responder chain to the `UIApplication` and call
    /// the non-deprecated `open(_:options:completionHandler:)`. The legacy
    /// `openURL:` selector is force-failed ("returning NO") by modern iOS.
    private func openInHostApp(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] _ in
                    Task { @MainActor in self?.finish() }
                }
                return
            }
            responder = current.next
        }
        finish()
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
