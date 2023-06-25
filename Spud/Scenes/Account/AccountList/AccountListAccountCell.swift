//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import UIKit

class AccountListAccountCell: UITableViewCell {
    static let reuseIdentifier = "AccountListAccountCell"

    func configure(with account: LemmyAccount) {
        var content = defaultContentConfiguration()

        content.text = account.site.normalizedInstanceUrl
        if account.isSignedOutAccountType {
            content.secondaryText = "signed out (anonymous browsing)"
        }

        self.contentConfiguration = content
    }
}
