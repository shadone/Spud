//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import SpudDataKit

/// Resolves `CommunityAppEntity` values from the default account's subscriptions
/// in the shared App-Group database. Runs in a background intents process, so it
/// opens its own read-only data path (like the widget) rather than the app's UI
/// coordinator. Tests inject `load` to avoid touching the shared store.
struct CommunityEntityQuery: EntityStringQuery {
    private let load: @Sendable () -> [CommunityAppEntity]

    init() {
        load = { CommunityEntityQuery.loadFromSharedDatabase() }
    }

    init(load: @escaping @Sendable () -> [CommunityAppEntity]) {
        self.load = load
    }

    func entities(for identifiers: [String]) async throws -> [CommunityAppEntity] {
        let wanted = Set(identifiers)
        return load().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CommunityAppEntity] {
        let needle = string.lowercased()
        return load().filter { $0.name.lowercased().contains(needle) }
    }

    func suggestedEntities() async throws -> [CommunityAppEntity] {
        load()
    }

    private static func loadFromSharedDatabase() -> [CommunityAppEntity] {
        guard let appDatabase = try? AppDatabase() else { return [] }
        return appDatabase.followedCommunitiesForDefaultAccountSync()
            .compactMap(CommunityAppEntity.init(record:))
    }
}
