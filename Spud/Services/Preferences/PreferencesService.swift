//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUtilKit

/// The namespace for types used by ``PreferencesService``.
enum Preferences { }

@MainActor
protocol PreferencesServiceType: AnyObject {
    var defaultCommentSortType: Components.Schemas.CommentSortType { get set }
    var defaultCommentSortTypeStream: AsyncStream<Components.Schemas.CommentSortType> { get }

    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }
    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> { get }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> { get }

    /// When opening external link first check if it's a universal link first and then open it in the app.
    var openUniversalLinkInApp: Bool { get set }
}

@MainActor
protocol HasPreferencesService {
    var preferencesService: PreferencesServiceType { get }
}

@MainActor
class PreferencesService: PreferencesServiceType {
    @UserDefaultsBacked(key: "defaultCommentSortType")
    var defaultCommentSortType: Components.Schemas.CommentSortType = .Hot

    var defaultCommentSortTypeStream: AsyncStream<Components.Schemas.CommentSortType> {
        $defaultCommentSortType
    }

    @UserDefaultsBacked(key: "openExternalLinks")
    var openExternalLinks: Preferences.OpenExternalLink = .safariViewController

    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> {
        $openExternalLinks
    }

    @UserDefaultsBacked(key: "openExternalLinksInSafariVCReaderMode")
    var openExternalLinksInSafariVCReaderMode = true

    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> {
        $openExternalLinksInSafariVCReaderMode
    }

    @UserDefaultsBacked(key: "openUniversalLinkInApp")
    var openUniversalLinkInApp: Bool = true
}
