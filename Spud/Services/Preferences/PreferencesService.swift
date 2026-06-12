//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudUIKit
import SpudUtilKit

/// The namespace for types used by ``PreferencesService``.
enum Preferences { }

@MainActor
protocol PreferencesServiceType: AnyObject {
    var defaultCommentSortType: Components.Schemas.CommentSortType { get set }
    var defaultCommentSortTypeStream: AsyncStream<Components.Schemas.CommentSortType> { get }

    /// The selected app appearance (system / light / dark / true-black).
    var appTheme: AppTheme { get set }
    var appThemeStream: AsyncStream<AppTheme> { get }

    /// The selected accent color.
    var accentColor: AccentColor { get set }
    var accentColorStream: AsyncStream<AccentColor> { get }

    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }
    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> { get }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> { get }

    /// When opening external link first check if it's a universal link first and then open it in the app.
    var openUniversalLinkInApp: Bool { get set }

    /// The user-assigned swipe actions for post cells. Defaults reproduce the
    /// pre-M8 hardcoded behaviour (``SwipeActionConfig/defaultPosts``).
    var postSwipeActions: SwipeActionConfig { get set }
    var postSwipeActionsStream: AsyncStream<SwipeActionConfig> { get }

    /// The user-assigned swipe actions for comment cells. Defaults reproduce
    /// the pre-M8 hardcoded behaviour (``SwipeActionConfig/defaultComments``).
    var commentSwipeActions: SwipeActionConfig { get set }
    var commentSwipeActionsStream: AsyncStream<SwipeActionConfig> { get }
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

    @UserDefaultsBacked(key: "appTheme")
    var appTheme: AppTheme = .system

    var appThemeStream: AsyncStream<AppTheme> {
        $appTheme
    }

    @UserDefaultsBacked(key: "accentColor")
    var accentColor: AccentColor = .lemmy

    var accentColorStream: AsyncStream<AccentColor> {
        $accentColor
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

    @UserDefaultsBacked(key: "postSwipeActions")
    var postSwipeActions: SwipeActionConfig = .defaultPosts

    var postSwipeActionsStream: AsyncStream<SwipeActionConfig> {
        $postSwipeActions
    }

    @UserDefaultsBacked(key: "commentSwipeActions")
    var commentSwipeActions: SwipeActionConfig = .defaultComments

    var commentSwipeActionsStream: AsyncStream<SwipeActionConfig> {
        $commentSwipeActions
    }
}
