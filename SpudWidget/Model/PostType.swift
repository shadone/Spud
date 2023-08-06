//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

public enum PostType: Codable {
    case text
    case image(URL)

    public var imageUrl: URL? {
        if case let .image(url) = self {
            return url
        }
        return nil
    }
}
