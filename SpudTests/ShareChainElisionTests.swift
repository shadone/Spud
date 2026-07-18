//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Unit coverage for ``ShareChainElision`` — the pure helper that turns a
/// comment chain plus a depth into the exact rows the chain card draws.
///
/// The two behaviors under test, both from the plan's binding chain spec:
/// depth limits how many ancestors show (keeping the ones CLOSEST to the shared
/// comment), and a chain with more than four visible ancestors elides its
/// middle to top-2 + "N more replies" + bottom-2. The destination comment is
/// never elided and never counted as an ancestor.
struct ShareChainElisionTests {
    // MARK: - No elision

    @Test
    func destinationOnly_hasNoAncestorsAndNoElision() {
        let rows = ShareChainElision.visibleRows(chain: [destination()], depth: 2)
        #expect(rows == [.item(destination())])
    }

    @Test
    func threeAncestors_renderInFullNoElision() {
        let chain = ancestors(1...3) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows == [
            .item(ancestor(1)),
            .item(ancestor(2)),
            .item(ancestor(3)),
            .item(destination()),
        ])
    }

    @Test
    func fourAncestors_isTheNoElisionBoundary() {
        // Four is NOT "more than four", so all four render with no divider.
        let chain = ancestors(1...4) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows.count == 5)
        #expect(!rows.contains { if case .elision = $0 { true } else { false } })
    }

    // MARK: - Elision

    @Test
    func fiveAncestors_elideToTop2Bottom2WithSingularLabel() {
        let chain = ancestors(1...5) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows == [
            .item(ancestor(1)),
            .item(ancestor(2)),
            .elision(count: 1),
            .item(ancestor(4)),
            .item(ancestor(5)),
            .item(destination()),
        ])
    }

    @Test
    func sixAncestors_elideMiddleTwoWithPluralLabel() {
        let chain = ancestors(1...6) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows == [
            .item(ancestor(1)),
            .item(ancestor(2)),
            .elision(count: 2),
            .item(ancestor(5)),
            .item(ancestor(6)),
            .item(destination()),
        ])
    }

    // MARK: - Depth clamping

    @Test
    func depthLimitsToTheAncestorsClosestToTheDestination() {
        // Depth 2 keeps only the two ancestors immediately above the shared
        // comment (the suffix), not the two root-most ones.
        let chain = ancestors(1...5) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 2)
        #expect(rows == [
            .item(ancestor(4)),
            .item(ancestor(5)),
            .item(destination()),
        ])
    }

    @Test
    func depthZero_showsTheDestinationAlone() {
        let chain = ancestors(1...3) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 0)
        #expect(rows == [.item(destination())])
    }

    @Test
    func depthBeyondAvailable_clampsToAllAncestors() {
        let chain = ancestors(1...2) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows == [
            .item(ancestor(1)),
            .item(ancestor(2)),
            .item(destination()),
        ])
    }

    @Test
    func negativeDepth_isTreatedAsZero() {
        let chain = ancestors(1...3) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: -5)
        #expect(rows == [.item(destination())])
    }

    @Test
    func depthAndElisionCompose_suffixThenElide() {
        // Ten ancestors, depth 8: the suffix of eight (a3...a10) is elided to
        // its top-2 (a3, a4) + four hidden + bottom-2 (a9, a10).
        let chain = ancestors(1...10) + [destination()]
        let rows = ShareChainElision.visibleRows(chain: chain, depth: 8)
        #expect(rows == [
            .item(ancestor(3)),
            .item(ancestor(4)),
            .elision(count: 4),
            .item(ancestor(9)),
            .item(ancestor(10)),
            .item(destination()),
        ])
    }

    // MARK: - Elision label

    @Test
    func elisionLabel_isSingularForOne() {
        #expect(ShareChainElision.elisionLabel(count: 1) == "1 more reply")
    }

    @Test
    func elisionLabel_isPluralForMany() {
        #expect(ShareChainElision.elisionLabel(count: 2) == "2 more replies")
        #expect(ShareChainElision.elisionLabel(count: 7) == "7 more replies")
    }

    // MARK: - Fixtures

    private func ancestors(_ range: ClosedRange<Int>) -> [ShareCardContent.ChainItem] {
        range.map { ancestor($0) }
    }

    private func ancestor(_ id: Int) -> ShareCardContent.ChainItem {
        ShareCardContent.ChainItem(
            authorHandle: "u/user\(id)@lemmy.ml",
            score: Int64(id),
            bodyPlain: "Ancestor \(id) body text.",
            published: nil,
            isDestination: false,
            permalink: nil
        )
    }

    private func destination() -> ShareCardContent.ChainItem {
        ShareCardContent.ChainItem(
            authorHandle: "u/op@lemmy.ml",
            score: 99,
            bodyPlain: "The shared comment body.",
            published: Date(timeIntervalSince1970: 1_752_336_180),
            isDestination: true,
            permalink: URL(string: "https://lemmy.ml/comment/555")!
        )
    }
}
