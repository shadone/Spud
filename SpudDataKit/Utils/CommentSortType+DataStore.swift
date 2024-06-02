//
// Copyright (c) 2024, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

extension Components.Schemas.CommentSortType {
    /// Deserialized a comment sort type from a string stored in Data Store (Core Data).
    init?(fromDataStore rawValue: String) {
        // When reading from Core Data we support deserialing from lowercase values
        // for compabitility reasons.
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

    /// Serializes the comment sort type to a string that will be stored in Data Store (Core Data)
    var dataStoreRawValue: String {
        rawValue
    }
}
