//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
import UIKit
@testable import Spud

/// Regression coverage for the "inline body image zooms in from a corner" glitch.
///
/// When an inline body image finishes loading it grows its host row's height
/// after the row is already on screen. Re-measuring that row with the default
/// animated `performBatchUpdates(nil)` animates the never-laid-out image view's
/// frame from `.zero` to its fill frame — the visible corner-zoom. The fix routes
/// every such re-measure through `UITableView.remeasureRowHeightsWithoutAnimation()`,
/// which suppresses the implicit animation so the row simply snaps to its new
/// height.
///
/// This harness reproduces the mechanism with a real `UITableView` in a laid-out
/// window and a self-sizing cell whose height is driven by a mutable constraint:
/// growing the constraint after display and re-measuring is the analog of the
/// image landing. The two tests pin the discriminating behavior — the bare
/// animated re-measure attaches animations, the helper attaches none while still
/// growing the row.
@MainActor
struct NonAnimatedRemeasureTests {
    /// A self-sizing cell whose content height is a single mutable constraint.
    private final class GrowingCell: UITableViewCell {
        let box = UIView()
        var boxHeight: NSLayoutConstraint!

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            box.translatesAutoresizingMaskIntoConstraints = false
            box.backgroundColor = .systemBlue
            contentView.addSubview(box)
            boxHeight = box.heightAnchor.constraint(equalToConstant: 40)
            NSLayoutConstraint.activate([
                box.topAnchor.constraint(equalTo: contentView.topAnchor),
                box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                box.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                box.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                boxHeight,
            ])
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("not used")
        }
    }

    /// Vends the same `GrowingCell` for the single row so the test keeps a stable
    /// reference to the on-screen cell.
    private final class SingleCellDataSource: NSObject, UITableViewDataSource {
        let cell: GrowingCell
        init(cell: GrowingCell) {
            self.cell = cell
        }

        func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
            1
        }

        func tableView(_: UITableView, cellForRowAt _: IndexPath) -> UITableViewCell {
            cell
        }
    }

    private struct Harness {
        let window: UIWindow
        let tableView: UITableView
        let cell: GrowingCell
        let dataSource: SingleCellDataSource
    }

    private let indexPath = IndexPath(row: 0, section: 0)
    private let grownHeight: CGFloat = 200

    /// Builds a displayed, self-sized single-row table settled at ~40pt.
    private func makeHarness() -> Harness {
        let cell = GrowingCell(style: .default, reuseIdentifier: "cell")
        let dataSource = SingleCellDataSource(cell: cell)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let tableView = UITableView(frame: window.bounds, style: .plain)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 40
        tableView.dataSource = dataSource
        window.addSubview(tableView)
        window.makeKeyAndVisible()
        // Settle the initial self-sizing pass so the row is at ~40pt before we
        // grow it (two passes: estimate -> real self-sized height).
        tableView.layoutIfNeeded()
        tableView.layoutIfNeeded()
        return Harness(window: window, tableView: tableView, cell: cell, dataSource: dataSource)
    }

    /// All `animationKeys` across a view's whole layer subtree.
    private func animationKeys(in view: UIView) -> [String] {
        var keys = view.layer.animationKeys() ?? []
        for subview in view.subviews {
            keys += animationKeys(in: subview)
        }
        return keys
    }

    /// Grows the row and re-measures it via `remeasure`, then reports the
    /// animation keys attached to the on-screen cell subtree and the row's final
    /// height. Animation keys are read synchronously right after the re-measure
    /// call — UITableView attaches the height animation during the call.
    private func growAndRemeasure(
        _ harness: Harness,
        remeasure: (UITableView) -> Void
    ) -> (keys: [String], finalHeight: CGFloat) {
        harness.cell.boxHeight.constant = grownHeight
        remeasure(harness.tableView)
        let onScreen = harness.tableView.cellForRow(at: indexPath) ?? harness.cell
        let keys = animationKeys(in: onScreen)
        let finalHeight = harness.tableView.rectForRow(at: indexPath).height
        return (keys, finalHeight)
    }

    @Test
    func bareBatchUpdates_animatesRowHeight() {
        let harness = makeHarness()
        let (keys, _) = growAndRemeasure(harness) { $0.performBatchUpdates(nil) }
        #expect(
            !keys.isEmpty,
            "The animated re-measure did not attach any animation — the harness cannot observe the glitch, so the no-animation assertion below would be vacuous."
        )
    }

    @Test
    func helperRemeasure_doesNotAnimate_andGrowsRow() {
        let harness = makeHarness()
        let (keys, finalHeight) = growAndRemeasure(harness) { $0.remeasureRowHeightsWithoutAnimation() }
        #expect(
            keys.isEmpty,
            "Re-measuring the row attached animations \(keys) — the inline image would zoom in from a corner."
        )
        #expect(
            abs(finalHeight - grownHeight) < 2,
            "The row did not re-measure to its grown height: \(finalHeight) vs \(grownHeight)."
        )
    }
}
