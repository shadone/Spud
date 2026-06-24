//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension Preferences {
    /// Which instance a post/comment link should point at.
    enum LinkInstance: String, RawRepresentable, Codable, CaseIterable, Identifiable {
        /// The account's home instance: `<home>/post|comment/<serverId>`.
        case myInstance

        /// The canonical federation permalink (`ap_id`), falling back to the
        /// home instance when absent.
        case originalInstance

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .myInstance:
                return "My Instance"
            case .originalInstance:
                return "Original Instance"
            }
        }
    }
}
