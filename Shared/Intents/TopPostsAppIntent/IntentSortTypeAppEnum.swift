//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import AppIntents

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
enum IntentSortTypeAppEnum: String, AppEnum {
    case active
    case hot
    case new
    case topSixHour
    case topTwelveHour
    case topDay
    case topWeek
    case topMonth
    case topYear
    case topAll
    case mostComments
    case newComments

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sort")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .active: "Active",
        .hot: "Hot",
        .new: "New",
        .topSixHour: "Top 6 Hours",
        .topTwelveHour: "Top 12 Hours",
        .topDay: "Top Day",
        .topWeek: "Top Week",
        .topMonth: "Top Month",
        .topYear: "Top Year",
        .topAll: "Top All",
        .mostComments: "Most Comments",
        .newComments: "New Comments"
    ]
}

