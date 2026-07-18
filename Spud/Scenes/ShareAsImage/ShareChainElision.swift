//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure layout arithmetic for the comment-chain card: turns a chain plus a
/// depth into the exact ordered rows ``ShareChainCardView`` draws. Kept
/// rendering-free (no UIKit) so the elision/depth rules are unit-testable in
/// isolation from any view.
///
/// The rules (from the plan's binding chain spec):
///
/// - **Depth** limits how many ancestors show. The kept ancestors are the ones
///   CLOSEST to the shared comment (the suffix of the ancestor list, which is
///   ordered root-most first), because the immediate parents are the most
///   relevant context. `depth` is clamped to `0...availableAncestors`
///   (negatives become zero; a depth beyond the available count keeps them all).
/// - **Elision** collapses a chain with MORE THAN four visible ancestors to its
///   top two, a single "N more replies" divider, and its bottom two.
/// - The **destination** (the shared comment, ``ShareCardContent/ChainItem/isDestination``)
///   is never counted as an ancestor and never elided — it always renders, even
///   at depth zero.
enum ShareChainElision {
    /// One drawn row of the chain card.
    enum Row: Equatable {
        /// A rendered chain item — an ancestor or the shared comment.
        case item(ShareCardContent.ChainItem)
        /// A "N more replies" divider standing in for `count` elided ancestors.
        case elision(count: Int)
    }

    /// The maximum number of visible ancestors above which the middle is
    /// elided. At or below this count every ancestor renders.
    private static let elisionThreshold = 4

    /// Resolves `chain` and `depth` into the ordered rows to draw.
    ///
    /// - Parameters:
    ///   - chain: the full chain, ancestors root-most first followed by the
    ///     destination (as built by ``ShareCardContent``'s comment builder).
    ///   - depth: how many ancestors to keep above the shared comment; clamped
    ///     to the available count (negatives treated as zero).
    /// - Returns: ancestor rows (possibly with one ``Row/elision(count:)``
    ///   divider) followed by the destination row(s).
    static func visibleRows(chain: [ShareCardContent.ChainItem], depth: Int) -> [Row] {
        let ancestors = chain.filter { !$0.isDestination }
        let destinationRows = chain.filter(\.isDestination).map(Row.item)

        // Keep the ancestors closest to the destination (the suffix), clamped to
        // however many exist. `suffix` tolerates counts beyond the array length.
        let keep = max(0, depth)
        let visibleAncestors = Array(ancestors.suffix(keep))

        guard visibleAncestors.count > elisionThreshold else {
            return visibleAncestors.map(Row.item) + destinationRows
        }

        let hiddenCount = visibleAncestors.count - elisionThreshold
        let top = visibleAncestors.prefix(2).map(Row.item)
        let bottom = visibleAncestors.suffix(2).map(Row.item)
        return top + [.elision(count: hiddenCount)] + bottom + destinationRows
    }

    /// The divider copy for an elided run — singular "1 more reply" or plural
    /// "N more replies".
    static func elisionLabel(count: Int) -> String {
        count == 1 ? "1 more reply" : "\(count) more replies"
    }
}
