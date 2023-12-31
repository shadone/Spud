//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
enum IntentFeedTypeAppEnum: String, AppEnum {
    case all
    case local
    case subscribed
    case moderatorView

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "All",
        .local: "Local",
        .subscribed: "Subscribed",
        .moderatorView: "Moderator view",
    ]
}
