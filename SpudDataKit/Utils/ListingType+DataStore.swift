//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.ListingType {
    /// Deserialized a listing type from a string stored in Data Store (Core Data).
    init?(fromDataStore rawValue: String) {
        // When reading from Core Data we support deserialing from lowercase values
        // for compabitility reasons.
        switch rawValue {
        case "all":
            self = .All

        case "local":
            self = .Local

        case "subscribed":
            self = .Subscribed

        case "moderatorView":
            self = .ModeratorView

        default:
            guard let value = Components.Schemas.ListingType(rawValue: rawValue) else {
                return nil
            }
            self = value
        }
    }

    /// Serializes the listing type to a string that will be stored in Data Store (Core Data)
    var dataStoreRawValue: String {
        rawValue
    }
}
