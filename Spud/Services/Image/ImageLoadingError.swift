//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum ImageLoadingError: Error {
    /// Failed to decode image data.
    case cannotDecode

    /// Failed to fetch the image, the server returned unexpected HTTP status code.
    case serverError(statusCode: Int)

    /// Network error has occurred.
    case network(Error)

    var localizedDescription: String { String(describing: self) }
}
