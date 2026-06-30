//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Lays out six `SummaryStatTileView` instances in a 3-column × 2-row grid.
///
/// The layout uses two horizontal `UIStackView` rows nested inside a
/// vertical `UIStackView`, so tiles grow with Dynamic Type automatically.
@MainActor
final class SummaryStatTilesView: UIView {
    // MARK: Private

    private let tiles: [SummaryStatTileView] = (0..<6).map { _ in SummaryStatTileView() }

    // MARK: Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    private func setupLayout() {
        func row(_ views: [UIView]) -> UIStackView {
            let s = UIStackView(arrangedSubviews: views)
            s.axis = .horizontal
            s.spacing = 8
            s.distribution = .fillEqually
            return s
        }

        let topRow = row(Array(tiles[0..<3]))
        let bottomRow = row(Array(tiles[3..<6]))

        let stack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    // MARK: Configuration

    /// Configures the tile views from `stats.tiles`. Requires exactly 6 tiles
    /// (the data layer always produces exactly 6).
    func configure(stats: SummaryStats) {
        for (index, tile) in tiles.enumerated() {
            guard index < stats.tiles.count else { break }
            tile.configure(stat: stats.tiles[index])
        }
    }
}
