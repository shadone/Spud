//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import UIKit

extension URL {
    /// Returns an image from url that contains image name from Asset Catalog.
    ///
    /// It seems that it isn't possible to make URL from Xcode Asset Catalog, this is a workaround for it.
    /// We define a custom url format for "linking" to asset images and use this helper to convert it
    /// to ``UIImage``.
    ///
    /// For example,
    /// ```swift
    /// let url = URL(string: "info.ddenis.spud://image-from-asset/foobar")
    ///
    /// // these two images are equivalent
    /// let imageViaUrl = url.spudImageFromAsset
    /// let image = UIImage(named: "foobar")
    /// ```
    var spudImageFromAsset: UIImage? {
        guard
            scheme == "info.ddenis.spud",
            safeHost == "image-from-assets"
        else {
            assertionFailure("Invalid url format for asset link: '\(absoluteString)'")
            return nil
        }

        let resourceName = String(safePath.dropFirst())
        return UIImage(named: resourceName)
    }
}
