//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension UIViewController {
    /// Adds given view controller
    func add(child viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        addChild(viewController)
    }

    /// Make the child occupy the whole parents view.
    func addSubviewWithEdgeConstraints(child viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }

        viewController.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Remove child view controller
    func remove(child viewController: UIViewController?) {
        guard let viewController = viewController else {
            return
        }
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }
}
