//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Opens the Search tab in Spud and runs a query. Backs the "Search Lemmy" Siri
/// phrase and Shortcuts action.
struct SearchLemmyAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Lemmy"
    static let description = IntentDescription("Search Lemmy in Spud.")
    static let openAppWhenRun = true

    @Parameter(title: "Query", requestValueDialog: "What do you want to search for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Lemmy for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.search(query: query))
        return .result()
    }
}
