//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Starts the new-post composer in Spud. The compose path applies the in-app
/// sign-in gate for signed-out accounts.
struct NewPostAppIntent: AppIntent {
    static let title: LocalizedStringResource = "New Post"
    static let description = IntentDescription("Start a new post in Spud.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.newPost)
        return .result()
    }
}
