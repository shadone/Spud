//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit
@testable import Spud

class MarkdownViewController: UIViewController {
    var attributedText: NSAttributedString? {
        get {
            textLabel.attributedText
        }
        set {
            textLabel.attributedText = newValue
        }
    }

    lazy var textLabel: LinkLabel = {
        let label = LinkLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()

    init() {
        super.init(nibName: nil, bundle: nil)

        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        view.backgroundColor = .systemBackground

        view.addSubview(textLabel)

        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: view.topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
