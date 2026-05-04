//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.CommentSortType {
    /// Deserializes a comment sort type from a string stored in the
    /// database. Lowercase spellings are accepted for backwards
    /// compatibility with older rows that predated the OpenAPI casing change.
    init?(fromDataStore rawValue: String) {
        switch rawValue {
        case "hot":
            self = .Hot

        case "top":
            self = .Top

        case "new":
            self = .New

        case "old":
            self = .Old

        case "controversial":
            self = .Controversial

        default:
            guard let value = Components.Schemas.CommentSortType(rawValue: rawValue) else {
                return nil
            }
            self = value
        }
    }

    /// Serializes the comment sort type to a string for database storage.
    var dataStoreRawValue: String {
        rawValue
    }
}
