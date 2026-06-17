//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Opens the Saved feed. Signed-out is handled in-app (the Saved feed already
/// gates), so this intent always opens the app and selects the feed.
struct OpenSavedAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Saved Posts"
    static let description = IntentDescription("Open your saved posts in Spud.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.savedFeed(sort: nil))
        return .result()
    }
}
