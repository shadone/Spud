//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import AppIntents

@available(iOS 17.0, macOS 14.0, watchOS 10.0, *)
struct ViewTopPostsAppIntent: 
    AppIntent,
    WidgetConfigurationIntent,
    CustomIntentMigratedAppIntent,
    PredictableIntent
{
    static let intentClassName = "ViewTopPostsIntent"

    static var title: LocalizedStringResource = "View Top Posts"
    static var description = IntentDescription("")

    @Parameter(title: "Category", default: .subscribed, requestValueDialog: "Which feed do you want?")
    var feedType: IntentFeedTypeAppEnum

    @Parameter(title: "Sort", default: .hot, requestValueDialog: "How do you want to sort the feed?")
    var sortType: IntentSortTypeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary()
    }

    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction(parameters: (\.$feedType)) { feedType in
            DisplayRepresentation(
                title: "View top posts",
                subtitle: ""
            )
        }
    }

    func perform() async throws -> some IntentResult {
        // TODO: Place your refactored intent handler code here.
        return .result()
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
fileprivate extension IntentDialog {
    static func feedTypeParameterDisambiguationIntro(
        count: Int,
        feedType: IntentFeedTypeAppEnum
    ) -> Self {
        "There are \(count) options matching ‘\(feedType)’."
    }

    static func feedTypeParameterConfirmation(
        feedType: IntentFeedTypeAppEnum
    ) -> Self {
        "Just to confirm, you wanted ‘\(feedType)’?"
    }

    static func sortTypeParameterDisambiguationIntro(
        count: Int,
        sortType: IntentSortTypeAppEnum
    ) -> Self {
        "There are \(count) options matching ‘\(sortType)’."
    }

    static func sortTypeParameterConfirmation(
        sortType: IntentSortTypeAppEnum
    ) -> Self {
        "Just to confirm, you wanted ‘\(sortType)’?"
    }
}
