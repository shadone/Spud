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
    var defaultCommentSortType: Lemmy.CommentSortType { get set }
    var defaultCommentSortTypeStream: AsyncStream<Lemmy.CommentSortType> { get }

    /// The selected app appearance (system / light / dark / true-black).
    var appTheme: AppTheme { get set }
    var appThemeStream: AsyncStream<AppTheme> { get }

    /// The selected accent color.
    var accentColor: AccentColor { get set }
    var accentColorStream: AsyncStream<AccentColor> { get }

    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }
    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> { get }

    /// Which instance the post-detail "Open in Browser" action targets.
    var openInBrowserInstance: Preferences.LinkInstance { get set }
    var openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> { get }

    /// Which instance "Share" links (posts and comments) target.
    var shareLinkInstance: Preferences.LinkInstance { get set }
    var shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> { get }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> { get }

    /// When opening external link first check if it's a universal link first and then open it in the app.
    var openUniversalLinkInApp: Bool { get set }

    /// Legacy single-toggle xcancel preference. Retained read-only for the
    /// one-time migration into `urlSanitizerConfig`; no longer surfaced in UI.
    var rewriteTwitterLinksToXcancel: Bool { get set }

    /// The outbound URL hygiene pipeline configuration. Read by `AppService`
    /// before opening external links and edited from the Privacy settings.
    var urlSanitizerConfig: URLSanitizerConfig { get set }
    var urlSanitizerConfigStream: AsyncStream<URLSanitizerConfig> { get }

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

    /// Comment-thread density (comfortable / compact) for the post-detail
    /// screen. Independent of the feed's `postDensity`.
    var commentDensity: PostDensity { get set }
    var commentDensityStream: AsyncStream<PostDensity> { get }

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

    /// Whether posts and communities marked not-safe-for-work are shown in
    /// feeds and the community directory. Default `false` (hide NSFW). The feed
    /// fetch threads this through `getPosts(showNSFW:)`, so the filtering is
    /// server-side; for signed-in accounts the value is also mirrored to the
    /// server's `local_user.show_nsfw`.
    var showNsfw: Bool { get set }
    var showNsfwStream: AsyncStream<Bool> { get }

    /// Whether NSFW content (posts, images, comments) are visually blurred when shown.
    /// Default `true` (blur on). Independent of ``showNsfw``.
    var blurNsfw: Bool { get set }
    var blurNsfwStream: AsyncStream<Bool> { get }

    /// Whether the app fetches link-embed metadata (thumbnail + title) for video
    /// links in comment/post bodies. Default `true`. Off ⇒ in-body link cards
    /// stay local (anchor text + host), with no third-party fetch.
    var fetchLinkEmbeds: Bool { get set }
    var fetchLinkEmbedsStream: AsyncStream<Bool> { get }

    /// Whether the user has acknowledged the age gate for viewing adult content.
    /// Set to `true` once on first confirmation; never reset to `false` in the app.
    var hasAcknowledgedNsfwAge: Bool { get set }

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

    // MARK: Offline

    /// How many posts an offline download saves. Remembered across launches so the
    /// "Download for offline" chooser opens on the user's last choice. Default
    /// ``Preferences/OfflineDownloadPostCount/default`` (100).
    var offlineDownloadPostCount: Preferences.OfflineDownloadPostCount { get set }

    /// Whether an offline download also captures a web archive of each
    /// external-link post's target page (so the linked page reads offline).
    /// Remembered across launches so the "Download for offline" chooser opens on
    /// the user's last choice. Default `false` — capturing pages is slower and
    /// heavier than warming images, so it's opt-in.
    var offlineDownloadArchiveLinks: Bool { get set }
}

@MainActor
protocol HasPreferencesService {
    var preferencesService: PreferencesServiceType { get }
}

@MainActor
class PreferencesService: PreferencesServiceType {
    @UserDefaultsBacked
    var defaultCommentSortType: Lemmy.CommentSortType

    var defaultCommentSortTypeStream: AsyncStream<Lemmy.CommentSortType> {
        $defaultCommentSortType
    }

    @UserDefaultsBacked
    var appTheme: AppTheme

    var appThemeStream: AsyncStream<AppTheme> {
        $appTheme
    }

    @UserDefaultsBacked
    var accentColor: AccentColor

    var accentColorStream: AsyncStream<AccentColor> {
        $accentColor
    }

    @UserDefaultsBacked
    var openExternalLinks: Preferences.OpenExternalLink

    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> {
        $openExternalLinks
    }

    @UserDefaultsBacked
    var openInBrowserInstance: Preferences.LinkInstance

    var openInBrowserInstanceStream: AsyncStream<Preferences.LinkInstance> {
        $openInBrowserInstance
    }

    @UserDefaultsBacked
    var shareLinkInstance: Preferences.LinkInstance

    var shareLinkInstanceStream: AsyncStream<Preferences.LinkInstance> {
        $shareLinkInstance
    }

    @UserDefaultsBacked
    var openExternalLinksInSafariVCReaderMode: Bool

    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> {
        $openExternalLinksInSafariVCReaderMode
    }

    @UserDefaultsBacked
    var openUniversalLinkInApp: Bool

    @UserDefaultsBacked
    var rewriteTwitterLinksToXcancel: Bool

    @UserDefaultsBacked
    var urlSanitizerConfig: URLSanitizerConfig

    var urlSanitizerConfigStream: AsyncStream<URLSanitizerConfig> {
        $urlSanitizerConfig
    }

    @UserDefaultsBacked
    private var didMigrateXcancelToSanitizer: Bool

    @UserDefaultsBacked
    var postSwipeActions: SwipeActionConfig

    var postSwipeActionsStream: AsyncStream<SwipeActionConfig> {
        $postSwipeActions
    }

    @UserDefaultsBacked
    var commentSwipeActions: SwipeActionConfig

    var commentSwipeActionsStream: AsyncStream<SwipeActionConfig> {
        $commentSwipeActions
    }

    // MARK: Reading / display (M8)

    @UserDefaultsBacked
    var postDensity: PostDensity

    var postDensityStream: AsyncStream<PostDensity> {
        $postDensity
    }

    @UserDefaultsBacked
    var commentDensity: PostDensity

    var commentDensityStream: AsyncStream<PostDensity> {
        $commentDensity
    }

    @UserDefaultsBacked
    var thumbnailPosition: ThumbnailPosition

    var thumbnailPositionStream: AsyncStream<ThumbnailPosition> {
        $thumbnailPosition
    }

    @UserDefaultsBacked
    var postTextScale: CGFloat

    var postTextScaleStream: AsyncStream<CGFloat> {
        $postTextScale
    }

    @UserDefaultsBacked
    var showVoteButtons: Bool

    var showVoteButtonsStream: AsyncStream<Bool> {
        $showVoteButtons
    }

    @UserDefaultsBacked
    var showNsfw: Bool

    var showNsfwStream: AsyncStream<Bool> {
        $showNsfw
    }

    @UserDefaultsBacked
    var blurNsfw: Bool

    var blurNsfwStream: AsyncStream<Bool> {
        $blurNsfw
    }

    @UserDefaultsBacked
    var fetchLinkEmbeds: Bool

    var fetchLinkEmbedsStream: AsyncStream<Bool> {
        $fetchLinkEmbeds
    }

    @UserDefaultsBacked
    var hasAcknowledgedNsfwAge: Bool

    // MARK: Mark-read / hide (M8)

    @UserDefaultsBacked
    var markPostsRead: Bool

    var markPostsReadStream: AsyncStream<Bool> {
        $markPostsRead
    }

    @UserDefaultsBacked
    var markPostsReadOnScroll: Bool

    var markPostsReadOnScrollStream: AsyncStream<Bool> {
        $markPostsReadOnScroll
    }

    @UserDefaultsBacked
    var hideReadPosts: Bool

    var hideReadPostsStream: AsyncStream<Bool> {
        $hideReadPosts
    }

    @UserDefaultsBacked
    var hideReadPostsMode: HideReadPostsFilter.Mode

    var hideReadPostsModeStream: AsyncStream<HideReadPostsFilter.Mode> {
        $hideReadPostsMode
    }

    // MARK: Community directory (Explorer)

    @UserDefaultsBacked
    var explorerAutoRefreshEnabled: Bool

    var explorerAutoRefreshEnabledStream: AsyncStream<Bool> {
        $explorerAutoRefreshEnabled
    }

    @UserDefaultsBacked
    var explorerRefreshInterval: Preferences.ExplorerRefreshInterval

    var explorerRefreshIntervalStream: AsyncStream<Preferences.ExplorerRefreshInterval> {
        $explorerRefreshInterval
    }

    // MARK: Offline

    @UserDefaultsBacked
    var offlineDownloadPostCount: Preferences.OfflineDownloadPostCount

    @UserDefaultsBacked
    var offlineDownloadArchiveLinks: Bool

    /// Designated initializer. Injects the `UserDefaults` store that backs every
    /// `@UserDefaultsBacked` property so tests can run against a private,
    /// disposable suite instead of `.standard`. Each assignment must preserve the
    /// property's exact key string and default value.
    init(storage: UserDefaults) {
        _defaultCommentSortType = .init(wrappedValue: .Hot, key: "defaultCommentSortType", storage: storage)
        _appTheme = .init(wrappedValue: .system, key: "appTheme", storage: storage)
        _accentColor = .init(wrappedValue: .lemmy, key: "accentColor", storage: storage)
        _openExternalLinks = .init(wrappedValue: .safariViewController, key: "openExternalLinks", storage: storage)
        _openInBrowserInstance = .init(wrappedValue: .myInstance, key: "openInBrowserInstance", storage: storage)
        _shareLinkInstance = .init(wrappedValue: .originalInstance, key: "shareLinkInstance", storage: storage)
        _openExternalLinksInSafariVCReaderMode = .init(
            wrappedValue: true,
            key: "openExternalLinksInSafariVCReaderMode",
            storage: storage
        )
        _openUniversalLinkInApp = .init(wrappedValue: true, key: "openUniversalLinkInApp", storage: storage)
        _rewriteTwitterLinksToXcancel = .init(wrappedValue: false, key: "rewriteTwitterLinksToXcancel", storage: storage)
        _urlSanitizerConfig = .init(wrappedValue: .default, key: "urlSanitizerConfig", storage: storage)
        _didMigrateXcancelToSanitizer = .init(
            wrappedValue: false,
            key: "didMigrateXcancelToSanitizer",
            storage: storage
        )
        _postSwipeActions = .init(wrappedValue: .defaultPosts, key: "postSwipeActions", storage: storage)
        _commentSwipeActions = .init(wrappedValue: .defaultComments, key: "commentSwipeActions", storage: storage)
        _postDensity = .init(wrappedValue: .comfortable, key: "postDensity", storage: storage)
        _commentDensity = .init(wrappedValue: .comfortable, key: "commentDensity", storage: storage)
        _thumbnailPosition = .init(wrappedValue: .left, key: "thumbnailPosition", storage: storage)
        _postTextScale = .init(wrappedValue: 0, key: "postTextScale", storage: storage)
        _showVoteButtons = .init(wrappedValue: true, key: "showVoteButtons", storage: storage)
        _showNsfw = .init(wrappedValue: false, key: "showNsfw", storage: storage)
        _blurNsfw = .init(wrappedValue: true, key: "blurNsfw", storage: storage)
        _fetchLinkEmbeds = .init(wrappedValue: true, key: "fetchLinkEmbeds", storage: storage)
        _hasAcknowledgedNsfwAge = .init(wrappedValue: false, key: "hasAcknowledgedNsfwAge", storage: storage)
        _markPostsRead = .init(wrappedValue: true, key: "markPostsRead", storage: storage)
        _markPostsReadOnScroll = .init(wrappedValue: false, key: "markPostsReadOnScroll", storage: storage)
        _hideReadPosts = .init(wrappedValue: false, key: "hideReadPosts", storage: storage)
        _hideReadPostsMode = .init(wrappedValue: .onRefresh, key: "hideReadPostsMode", storage: storage)
        _explorerAutoRefreshEnabled = .init(wrappedValue: true, key: "explorerAutoRefreshEnabled", storage: storage)
        _explorerRefreshInterval = .init(wrappedValue: .daily, key: "explorerRefreshInterval", storage: storage)
        _offlineDownloadPostCount = .init(
            wrappedValue: .default,
            key: "offlineDownloadPostCount",
            storage: storage
        )
        _offlineDownloadArchiveLinks = .init(
            wrappedValue: false,
            key: "offlineDownloadArchiveLinks",
            storage: storage
        )

        if let migrated = URLSanitizerConfig.migratingFromLegacyXcancel(
            legacyEnabled: rewriteTwitterLinksToXcancel,
            alreadyMigrated: didMigrateXcancelToSanitizer
        ) {
            urlSanitizerConfig = migrated
        }
        didMigrateXcancelToSanitizer = true
    }

    /// Convenience initializer backing every preference with `UserDefaults.standard`.
    /// Keeps all existing `PreferencesService()` call sites source-compatible.
    convenience init() {
        self.init(storage: .standard)
    }
}
