//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension String {
    func endsWith(_ substr: String) -> Bool {
        suffix(substr.count) == substr
    }
}
