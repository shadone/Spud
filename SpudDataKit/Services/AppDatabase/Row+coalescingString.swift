//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import GRDB

extension Row {
    /// Returns the first non-NULL `String` among `columns`, in order.
    ///
    /// Use this instead of `row["a"] ?? row["b"]`. Chaining two GRDB column
    /// subscripts through `??` hits a Swift type-inference footgun: the
    /// operands are decoded as a double optional, and a NULL *left* column
    /// makes the whole expression evaluate to `nil` instead of falling
    /// through to the right column. (A `row["a"] ?? "literal"` form is fine —
    /// only two chained subscripts trigger it.)
    ///
    /// Reading each column into its own `String?` decodes them independently
    /// and coalesces correctly.
    func coalescingString(_ columns: String...) -> String? {
        for column in columns {
            let value: String? = self[column]
            if let value {
                return value
            }
        }
        return nil
    }
}
