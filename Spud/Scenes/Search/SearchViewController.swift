//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class SearchViewController: UIViewController {
    // MARK: - Private

    lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 15, weight: .light)
        label.textColor = UIColor.tertiaryLabel
        label.numberOfLines = 0
        label.text = "Search\nnot implemented"
        return label
    }()

    // MARK: - Functions

    init() {
        super.init(nibName: nil, bundle: nil)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        tabBarItem.title = "Search"
        tabBarItem.image = UIImage(systemName: "magnifyingglass")!

        view.backgroundColor = .white

        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
        ])
    }
}
