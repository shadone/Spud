//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public struct Community: Codable {
    public let name: String
    public let site: String

    public init(name: String, site: String) {
        self.name = name
        self.site = site
    }
}
