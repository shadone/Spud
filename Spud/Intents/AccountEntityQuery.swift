//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit

/// Resolves `AccountAppEntity` values from the accounts in the shared App-Group
/// database. Runs in a background intents process, so it opens its own read-only
/// data path (like the widget) rather than the app's UI coordinator. Tests
/// inject `load` to avoid touching the shared store.
struct AccountEntityQuery: EntityQuery {
    private let load: @Sendable () -> [AccountAppEntity]

    init() {
        load = { AccountEntityQuery.loadFromSharedDatabase() }
    }

    init(load: @escaping @Sendable () -> [AccountAppEntity]) {
        self.load = load
    }

    func entities(for identifiers: [String]) async throws -> [AccountAppEntity] {
        let wanted = Set(identifiers)
        return load().filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountAppEntity] {
        load()
    }

    private static func loadFromSharedDatabase() -> [AccountAppEntity] {
        guard let appDatabase = try? AppDatabase() else { return [] }
        return appDatabase.accountsSync().map(AccountAppEntity.init(row:))
    }
}
