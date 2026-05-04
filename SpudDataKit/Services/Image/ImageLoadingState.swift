//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

/// UIImage isn't formally Sendable but is treated as immutable in the
/// image-service pipeline (we never mutate fetched UIImages, just hand them
/// off to UIImageView). @unchecked Sendable lets the enum cross actor
/// boundaries without spurious warnings.
public enum ImageLoadingState: @unchecked Sendable {
    /// The image is being fetched.
    case loading(thumbnail: UIImage?)

    /// The image was successfully fetched.
    case ready(UIImage)

    /// The image failed to load, we display a broken image icon.
    case failure
}
