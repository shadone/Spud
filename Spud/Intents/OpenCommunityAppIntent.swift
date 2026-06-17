//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents

/// Opens one of the user's communities in Spud. The `community` parameter is
/// resolved from the default account's subscriptions by `CommunityEntityQuery`,
/// so Siri / Shortcuts can pick or say a community by name.
struct OpenCommunityAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Community"
    static let description = IntentDescription("Open one of your communities in Spud.")
    static let openAppWhenRun = true

    @Parameter(title: "Community")
    var community: CommunityAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$community)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppCoordinator.shared.navigate(.community(name: community.name, instance: community.instance))
        _ = try? await IntentDonationManager.shared.donate(intent: self)
        return .result()
    }
}
