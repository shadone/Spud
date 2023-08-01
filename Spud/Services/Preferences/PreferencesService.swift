//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation

/// The namespace for types used by ``PreferencesService``.
enum Preferences {}

extension Preferences {
    /// Describes how to open external links in posts and comments.
    enum OpenExternalLink: Codable {
        /// Open external links in in-app browser (SFSafariViewController).
        case safariViewController

        /// Open external links in the system default browser.
        case browser
    }
}

protocol PreferencesServiceType: AnyObject {
    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
}

protocol HasPreferencesService {
    var preferencesService: PreferencesServiceType { get }
}

class PreferencesService: PreferencesServiceType {
    // MARK: Public

    @UserDefaultsBacked(key: "openExternalLinks")
    var openExternalLinks: Preferences.OpenExternalLink = .safariViewController

    @UserDefaultsBacked(key: "openExternalLinksInSafariVCReaderMode")
    var openExternalLinksInSafariVCReaderMode = true
}
