//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Switches the active Spud account. The existing default-account observation
/// rebuilds the UI for the new default.
struct SwitchAccountAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Account"
    static let description = IntentDescription("Switch the active Spud account.")
    static let openAppWhenRun = true

    @Parameter(title: "Account")
    var account: AccountAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch to \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.dependencies.accountService
            .setDefaultAccount(forAccountKeychainId: account.id)
        return .result()
    }
}
