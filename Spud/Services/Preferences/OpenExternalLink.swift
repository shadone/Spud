//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

extension Preferences {
    /// Describes how to open external links in posts and comments.
    enum OpenExternalLink: String, RawRepresentable, Codable, CaseIterable, Identifiable {
        /// Open external links in in-app browser (SFSafariViewController).
        case safariViewController

        /// Open external links in the system default browser.
        case browser

        var id: String { rawValue }
    }
}

extension Preferences.OpenExternalLink {
    struct MenuItem {
        let title: String
    }

    var itemForMenu: MenuItem {
        switch self {
        case .safariViewController:
            return .init(title: "In-App Safari")

        case .browser:
            return .init(title: "Safari")
        }
    }
}
