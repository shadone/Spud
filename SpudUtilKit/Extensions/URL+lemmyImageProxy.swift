//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// When a Lemmy instance has `image_proxy` enabled it rewrites image post
    /// urls to `{instance}/api/v3/image_proxy?url={percent-encoded original}`.
    /// The proxy url's own path carries no file extension, which defeats
    /// extension-based content detection.
    ///
    /// Returns the embedded original url for such a proxied url, or `nil` when
    /// this is not a Lemmy image-proxy url.
    var lemmyImageProxyOriginalUrl: URL? {
        guard pathComponents.last == "image_proxy" else { return nil }
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
            let originalUrlString = components.queryItems?
            .first(where: { $0.name == "url" })?.value,
            let originalUrl = URL(string: originalUrlString)
        else {
            return nil
        }
        return originalUrl
    }
}
