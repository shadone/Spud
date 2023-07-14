//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class PersonHeaderStatView: UIStackView {
    // MARK: Public

    var value: String? {
        get {
            valueLabel.text
        }
        set {
            valueLabel.text = newValue
        }
    }

    var text: String? {
        get {
            textLabel.text
        }
        set {
            textLabel.text = newValue
        }
    }

    // MARK: UI Properties

    lazy var valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .label
        label.font = UIFont.boldSystemFont(ofSize: 21)
        return label
    }()

    lazy var textLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }()

    // MARK: Functions

    override init(frame: CGRect) {
        super.init(frame: frame)

        axis = .vertical
        alignment = .center

        addArrangedSubview(valueLabel)
        addArrangedSubview(textLabel)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
