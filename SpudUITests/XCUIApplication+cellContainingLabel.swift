//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest

extension XCUIApplication {
    func cell(containing label: String) -> XCUIElement {
        tables.cells.containing(NSPredicate(
            format: "label CONTAINS %@",
            label
        )).element
    }
}
