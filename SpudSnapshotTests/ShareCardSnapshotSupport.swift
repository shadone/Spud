//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Shared rendering helpers for the fixed-width share-card snapshot suites
/// (``ShareCardViewSnapshotTests`` / ``ShareChainCardViewSnapshotTests``). Both
/// cards are plain `UIView`s pinned to the same 372pt design width and driven by
/// ``ShareCardPalette`` (theme-independent), so the fit + trait plumbing is
/// identical. Factored here so the two suites can't drift — the operations are
/// verbatim what each suite did inline, so recorded references re-render
/// byte-identically.
@MainActor
enum ShareCardSnapshotSupport {
    /// The cards' fixed design width.
    static let width: CGFloat = 372

    /// Pins `view` to ``width`` and returns its Auto Layout height. Mutates the
    /// view (width constraint + frame + layout pass) exactly as the suites did
    /// inline.
    static func fit(_ view: UIView) -> CGSize {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: height)
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        return size
    }

    /// The card's snapshot trait collection: the requested interface style, a
    /// pinned 2x display scale, and the determinism content-size pin.
    static func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }
}
