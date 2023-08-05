//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension TimeInterval {
    var roundedInt: Int {
        Int(rounded())
    }
}
