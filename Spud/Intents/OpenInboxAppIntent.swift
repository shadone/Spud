//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Opens the Inbox tab in Spud.
struct OpenInboxAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Inbox"
    static let description = IntentDescription("Open your Spud inbox.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.inbox)
        return .result()
    }
}
