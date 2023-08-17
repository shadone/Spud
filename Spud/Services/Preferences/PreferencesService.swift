//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit

/// The namespace for types used by ``PreferencesService``.
enum Preferences {}

protocol PreferencesServiceType: AnyObject {
    var defaultCommentSortType: CommentSortType { get set }
    var defaultCommentSortTypePublisher: AnyPublisher<CommentSortType, Never> { get }

    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }
    var openExternalLinksPublisher: AnyPublisher<Preferences.OpenExternalLink, Never> { get }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
    var openExternalLinksInSafariVCReaderModePublisher: AnyPublisher<Bool, Never> { get }

    /// When opening external link first check if it's a universal link first and then open it in the app.
    var openUniversalLinkInApp: Bool { get set }
}

protocol HasPreferencesService {
    var preferencesService: PreferencesServiceType { get }
}

class PreferencesService: PreferencesServiceType {
    // MARK: Public

    @UserDefaultsBacked(key: "defaultCommentSortType")
    var defaultCommentSortType: CommentSortType = .hot

    var defaultCommentSortTypePublisher: AnyPublisher<CommentSortType, Never> {
        $defaultCommentSortType
    }

    @UserDefaultsBacked(key: "openExternalLinks")
    var openExternalLinks: Preferences.OpenExternalLink = .safariViewController

    var openExternalLinksPublisher: AnyPublisher<Preferences.OpenExternalLink, Never> {
        $openExternalLinks
    }

    @UserDefaultsBacked(key: "openExternalLinksInSafariVCReaderMode")
    var openExternalLinksInSafariVCReaderMode = true

    var openExternalLinksInSafariVCReaderModePublisher: AnyPublisher<Bool, Never> {
        $openExternalLinksInSafariVCReaderMode
    }

    @UserDefaultsBacked(key: "openUniversalLinkInApp")
    var openUniversalLinkInApp: Bool = true
}
