//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import SpudMarkdownKit

struct ModelTests {
    @Test
    func blocksAreEquatable() {
        let a: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        let b: MarkdownBlock = .paragraph([.text("hi"), .strong([.text("there")])])
        #expect(a == b)
    }

    @Test
    func tableModelHoldsAlignmentsHeadRows() {
        let table = MarkdownTable(
            alignments: [.left, .right],
            head: [[.text("A")], [.text("B")]],
            rows: [[[.text("1")], [.text("2")]]]
        )
        #expect(table.alignments == [.left, .right])
        #expect(table.rows.count == 1)
    }
}
