//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.ListingType {
    /// Deserializes a listing type from a string stored in the database.
    /// Lowercase spellings are accepted for backwards compatibility with
    /// older rows that predated the OpenAPI casing change.
    init?(fromDataStore rawValue: String) {
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

    /// Serializes the listing type to a string for database storage.
    var dataStoreRawValue: String {
        rawValue
    }
}
