//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import LemmyKit

/// Opens a Lemmy frontpage feed (All / Local / Subscribed / Moderator view) in
/// Spud. Backs the "Open Feed" Siri phrase and Shortcuts action.
struct OpenFeedAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Feed"
    static let description = IntentDescription("Open a Lemmy feed in Spud.")
    static let openAppWhenRun = true

    @Parameter(title: "Category", default: .subscribed)
    var feedType: IntentFeedTypeAppEnum

    @Parameter(title: "Sort")
    var sortType: IntentSortTypeAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Open the \(\.$feedType) feed")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let listing = Lemmy.ListingType(from: feedType)
        let sort = sortType.map { Lemmy.SortType(from: $0) }
        AppCoordinator.shared.navigate(.feed(listing: listing, sort: sort))
        return .result()
    }
}
