//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit

/// A Spud account exposed to App Intents / Siri. Identity is the durable
/// `accountKeychainId`, so switching is stable across re-imports and federation.
struct AccountAppEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = AccountEntityQuery()

    var id: String
    var nickname: String
    var instanceHost: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(nickname)", subtitle: "\(instanceHost)")
    }
}

extension AccountAppEntity {
    /// Builds an entity from an account list row. Falls back to the instance
    /// host when there is no signed-in nickname (signed-out browsing accounts).
    init(row: AccountListRow) {
        self.init(
            id: row.accountKeychainId,
            nickname: row.nickname ?? row.instanceHostname,
            instanceHost: row.instanceHostname
        )
    }
}
