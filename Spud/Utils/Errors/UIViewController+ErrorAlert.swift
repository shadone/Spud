//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

extension UIViewController {
    /// Presents a single-button error alert. Centralised so write call sites
    /// surface failures consistently. `message` is expected to already be
    /// user-facing (see `ErrorMessage`).
    func presentErrorAlert(
        title: String = NSLocalizedString("Something went wrong", comment: "Generic error alert title"),
        message: String,
        completion: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: "Error alert dismiss button"),
            style: .default
        ))
        present(alert, animated: true, completion: completion)
    }
}
