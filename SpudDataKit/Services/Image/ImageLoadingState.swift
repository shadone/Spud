//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

public enum ImageLoadingState {
    /// The image is being fetched.
    case loading(thumbnail: UIImage?)

    /// The image was successfully fetched.
    case ready(UIImage)

    /// The image failed to load, we display a broken image icon.
    case failure
}
