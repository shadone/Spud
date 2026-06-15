//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
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

    /// Whether tapped twitter.com / x.com links are rewritten to the
    /// `xcancel.com` privacy front-end before opening. Default `false`.
    var rewriteTwitterLinksToXcancel: Bool { get set }

    /// The user-assigned swipe actions for post cells. Defaults reproduce the
    /// pre-M8 hardcoded behaviour (``SwipeActionConfig/defaultPosts``).
    var postSwipeActions: SwipeActionConfig { get set }
    var postSwipeActionsStream: AsyncStream<SwipeActionConfig> { get }

    /// The user-assigned swipe actions for comment cells. Defaults reproduce
    /// the pre-M8 hardcoded behaviour (``SwipeActionConfig/defaultComments``).
    var commentSwipeActions: SwipeActionConfig { get set }
    var commentSwipeActionsStream: AsyncStream<SwipeActionConfig> { get }

    // MARK: Reading / display (M8)

    /// Post-list density (comfortable / compact). Affects cell margins,
    /// spacing, and font size. Default `.comfortable` (the pre-M8 look).
    var postDensity: PostDensity { get set }
    var postDensityStream: AsyncStream<PostDensity> { get }

    /// Where the post-list thumbnail sits (left / right / hidden). Default
    /// `.left` (the pre-M8 layout).
    var thumbnailPosition: ThumbnailPosition { get set }
    var thumbnailPositionStream: AsyncStream<ThumbnailPosition> { get }

    /// A user text-scale override layered on top of Dynamic Type, in points
    /// relative to the system body size. Default `0` (no override).
    var postTextScale: CGFloat { get set }
    var postTextScaleStream: AsyncStream<CGFloat> { get }

    /// Whether the post-list cell shows the trailing up/down vote arrows.
    /// Default `true` (the Scout compact cell shows them).
    var showVoteButtons: Bool { get set }
    var showVoteButtonsStream: AsyncStream<Bool> { get }

    // MARK: Mark-read / hide (M8)

    /// Whether posts interacted with (opened, voted) are marked read. Default
    /// `true`.
    var markPostsRead: Bool { get set }
    var markPostsReadStream: AsyncStream<Bool> { get }

    /// Whether posts are marked read as they scroll out of view. Default
    /// `false`. Has no effect when ``markPostsRead`` is off.
    var markPostsReadOnScroll: Bool { get set }
    var markPostsReadOnScrollStream: AsyncStream<Bool> { get }

    /// Whether already-read posts are hidden from the feed. Default `false`.
    var hideReadPosts: Bool { get set }
    var hideReadPostsStream: AsyncStream<Bool> { get }

    /// When read posts are hidden — live (vanish on read) or only at refresh.
    /// Default `.onRefresh` (less jarring). Has no effect when
    /// ``hideReadPosts`` is off.
    var hideReadPostsMode: HideReadPostsFilter.Mode { get set }
    var hideReadPostsModeStream: AsyncStream<HideReadPostsFilter.Mode> { get }

    // MARK: Community directory (Explorer)

    /// Whether the bundled community/instance directory is refreshed from the
    /// network automatically at launch. Default `true`. When off, the directory
    /// only updates via the manual "Update Now" control.
    var explorerAutoRefreshEnabled: Bool { get set }
    var explorerAutoRefreshEnabledStream: AsyncStream<Bool> { get }

    /// How often the directory is auto-refreshed when ``explorerAutoRefreshEnabled``
    /// is on. Default `.daily`.
    var explorerRefreshInterval: Preferences.ExplorerRefreshInterval { get set }
    var explorerRefreshIntervalStream: AsyncStream<Preferences.ExplorerRefreshInterval> { get }
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

    @UserDefaultsBacked(key: "rewriteTwitterLinksToXcancel")
    var rewriteTwitterLinksToXcancel: Bool = false

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

    // MARK: Reading / display (M8)

    @UserDefaultsBacked(key: "postDensity")
    var postDensity: PostDensity = .comfortable

    var postDensityStream: AsyncStream<PostDensity> {
        $postDensity
    }

    @UserDefaultsBacked(key: "thumbnailPosition")
    var thumbnailPosition: ThumbnailPosition = .left

    var thumbnailPositionStream: AsyncStream<ThumbnailPosition> {
        $thumbnailPosition
    }

    @UserDefaultsBacked(key: "postTextScale")
    var postTextScale: CGFloat = 0

    var postTextScaleStream: AsyncStream<CGFloat> {
        $postTextScale
    }

    @UserDefaultsBacked(key: "showVoteButtons")
    var showVoteButtons: Bool = true

    var showVoteButtonsStream: AsyncStream<Bool> {
        $showVoteButtons
    }

    // MARK: Mark-read / hide (M8)

    @UserDefaultsBacked(key: "markPostsRead")
    var markPostsRead: Bool = true

    var markPostsReadStream: AsyncStream<Bool> {
        $markPostsRead
    }

    @UserDefaultsBacked(key: "markPostsReadOnScroll")
    var markPostsReadOnScroll: Bool = false

    var markPostsReadOnScrollStream: AsyncStream<Bool> {
        $markPostsReadOnScroll
    }

    @UserDefaultsBacked(key: "hideReadPosts")
    var hideReadPosts: Bool = false

    var hideReadPostsStream: AsyncStream<Bool> {
        $hideReadPosts
    }

    @UserDefaultsBacked(key: "hideReadPostsMode")
    var hideReadPostsMode: HideReadPostsFilter.Mode = .onRefresh

    var hideReadPostsModeStream: AsyncStream<HideReadPostsFilter.Mode> {
        $hideReadPostsMode
    }

    // MARK: Community directory (Explorer)

    @UserDefaultsBacked(key: "explorerAutoRefreshEnabled")
    var explorerAutoRefreshEnabled: Bool = true

    var explorerAutoRefreshEnabledStream: AsyncStream<Bool> {
        $explorerAutoRefreshEnabled
    }

    @UserDefaultsBacked(key: "explorerRefreshInterval")
    var explorerRefreshInterval: Preferences.ExplorerRefreshInterval = .daily

    var explorerRefreshIntervalStream: AsyncStream<Preferences.ExplorerRefreshInterval> {
        $explorerRefreshInterval
    }
}
