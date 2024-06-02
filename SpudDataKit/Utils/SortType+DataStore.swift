//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.SortType {
    /// Deserialized a sort type from a string stored in Data Store (Core Data).
    init?(fromDataStore rawValue: String) {
        // When reading from Core Data we support deserialing from lowercase values
        // for compabitility reasons.
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

    /// Serializes the sort type to a string that will be stored in Data Store (Core Data)
    var dataStoreRawValue: String {
        rawValue
    }
}
