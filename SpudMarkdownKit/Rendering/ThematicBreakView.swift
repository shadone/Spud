//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

final class ThematicBreakView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = .separator
        heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
