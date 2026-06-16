//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class ModelTests: XCTestCase {
    func test_blocksAreEquatable() {
        let a: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        let b: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        XCTAssertEqual(a, b)
    }

    func test_tableModelHoldsAlignmentsHeadRows() {
        let table = MarkdownTable(
            alignments: [.left, .right],
            head: [[.text("A")], [.text("B")]],
            rows: [[[.text("1")], [.text("2")]]]
        )
        XCTAssertEqual(table.alignments, [.left, .right])
        XCTAssertEqual(table.rows.count, 1)
    }
}
