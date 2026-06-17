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
        finish()
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

    /// Opens a URL in the host app. App extensions cannot reference
    /// `UIApplication.shared`, so walk the responder chain for an object that
    /// implements `openURL:` (that object is the application); fall back to the
    /// extension context if none is found.
    private func openInHostApp(_ url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
