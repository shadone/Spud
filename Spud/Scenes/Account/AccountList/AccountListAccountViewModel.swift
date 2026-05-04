//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

/// Plain-value view model for an AccountList row. Built once per snapshot
/// emitted by `observeAccountListRows()` and applied to the cell in
/// `configure(with:)`. No Combine, no KVO; the cell re-renders on the next
/// snapshot.
struct AccountListAccountViewModel {
    let title: NSAttributedString
    let subtitle: NSAttributedString?
    let accessoryType: UITableViewCell.AccessoryType

    init(row: AccountListRow) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium),
            .foregroundColor: UIColor.label,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: UIFont.systemFontSize - 2, weight: .regular),
            .foregroundColor: UIColor.label,
        ]

        let titleString: String = {
            if let nickname = row.nickname {
                return "\(nickname)@\(row.instanceHostname)"
            }
            return row.instanceHostname
        }()
        title = NSAttributedString(string: titleString, attributes: titleAttributes)

        if row.isSignedOutAccountType {
            subtitle = NSAttributedString(
                string: "signed out (anonymous browsing)",
                attributes: subtitleAttributes
            )
        } else if let email = row.email {
            subtitle = NSAttributedString(string: email, attributes: subtitleAttributes)
        } else {
            subtitle = nil
        }

        accessoryType = row.isDefault ? .checkmark : .none
    }
}
