//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.SortType {
    /// Deserializes a sort type from a string stored in the database. Lower-
    /// case spellings are accepted for backwards compatibility with older
    /// rows that predated the OpenAPI casing change.
    init?(fromDataStore rawValue: String) {
        switch rawValue {
        case "active":
            self = .Active

        case "hot":
            self = .Hot

        case "new":
            self = .New

        case "old":
            self = .Old

        case "topSixHour":
            self = .TopSixHour

        case "topTwelveHour":
            self = .TopTwelveHour

        case "topDay":
            self = .TopDay

        case "topWeek":
            self = .TopWeek

        case "topMonth":
            self = .TopMonth

        case "topYear":
            self = .TopYear

        case "topAll":
            self = .TopAll

        case "mostComments":
            self = .MostComments

        case "newComments":
            self = .NewComments

        case "topThreeMonths":
            self = .TopThreeMonths

        case "topSixMonths":
            self = .TopSixMonths

        case "topNineMonths":
            self = .TopNineMonths

        case "controversial":
            self = .Controversial

        case "scaled":
            self = .Scaled

        default:
            guard let value = Components.Schemas.SortType(rawValue: rawValue) else {
                return nil
            }
            self = value
        }
    }

    /// Serializes the sort type to a string for database storage.
    var dataStoreRawValue: String {
        rawValue
    }
}
