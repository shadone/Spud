//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import SpudDataKit
import SpudUIKit
import SpudUtilKit
import SwiftUI

@MainActor
@Observable
final class PreferencesViewModel {
    typealias OwnDependencies =
        HasAccountService &
        HasAppDatabase &
        HasExplorerService &
        HasPreferencesService
    typealias NestedDependencies =
        HasVoid
    typealias Dependencies = NestedDependencies & OwnDependencies

    @ObservationIgnored
    private let dependencies: (own: OwnDependencies, nested: NestedDependencies)?

    private var preferencesService: PreferencesServiceType? {
        dependencies?.own.preferencesService
    }

    private var accountService: AccountServiceType? {
        dependencies?.own.accountService
    }

    private var appDatabase: AppDatabase? {
        dependencies?.own.appDatabase
    }

    private var explorerService: ExplorerServiceType? {
        dependencies?.own.explorerService
    }

    /// The account these preferences apply to. Used to scope the blocked-list
    /// management screens. Empty in the preview init.
    @ObservationIgnored
    let accountKeychainId: String

    /// Whether the backing account is signed out (anonymous). Blocking requires
    /// authentication, so the blocked-list section is hidden for signed-out
    /// accounts.
    var isSignedOut: Bool {
        guard let accountService else { return true }
        return accountService.isSignedOut(forAccountKeychainId: accountKeychainId)
    }

    /// Builds the view model backing the blocked-users / blocked-communities
    /// management screens. Returns nil in the preview init (no services).
    /// Builds the view model backing the "Hidden & Muted" management screen.
    /// Returns nil in the preview init (no services).
    func makeHiddenAndMutedViewModel() -> HiddenAndMutedViewModel? {
        guard let accountService, let appDatabase else { return nil }
        return HiddenAndMutedViewModel(
            accountScope: accountService.scope(forAccountKeychainId: accountKeychainId),
            appDatabase: appDatabase
        )
    }

    func makeBlockedListViewModel() -> BlockedListViewModel? {
        guard let accountService else { return nil }
        return BlockedListViewModel(
            accountScope: accountService.scope(forAccountKeychainId: accountKeychainId)
        )
    }

    let allPostSortTypes: [Components.Schemas.SortType]
    let allCommentSortTypes: [Components.Schemas.CommentSortType]

    var defaultPostSortType: Components.Schemas.SortType
    var defaultCommentSortType: Components.Schemas.CommentSortType

    var openExternalLink: Preferences.OpenExternalLink
    var openExternalLinkInSafariVCReaderMode: Bool
    var openExternalLinkAsUniversalLinkInApp: Bool
    var openInBrowserInstance: Preferences.LinkInstance
    var shareLinkInstance: Preferences.LinkInstance

    /// Mirrored outbound URL hygiene config. Writes flow back through
    /// `preferencesService`; external changes arrive via its stream.
    var urlSanitizerConfig: URLSanitizerConfig

    /// User-assigned swipe actions for post and comment cells (M8). Mirrored
    /// here so the settings UI reflects external changes; writes flow back
    /// through `preferencesService`.
    var postSwipeActions: SwipeActionConfig
    var commentSwipeActions: SwipeActionConfig

    /// The selected app appearance and accent color. Live-applied app-wide via
    /// the preference streams the window observes; mirrored here so the
    /// Appearance settings UI reflects external changes.
    let allAppThemes: [AppTheme] = AppTheme.allCases
    let allAccentColors: [AccentColor] = AccentColor.allCases
    var appTheme: AppTheme
    var accentColor: AccentColor

    // MARK: Reading / display (M8)

    let allPostDensities: [PostDensity] = PostDensity.allCases
    let allThumbnailPositions: [ThumbnailPosition] = ThumbnailPosition.allCases

    var postDensity: PostDensity
    var thumbnailPosition: ThumbnailPosition
    var postTextScale: CGFloat
    var showVoteButtons: Bool

    var showNsfw: Bool
    var blurNsfw: Bool
    var fetchLinkEmbeds: Bool
    var hasAcknowledgedNsfwAge: Bool

    var markPostsRead: Bool
    var markPostsReadOnScroll: Bool
    var hideReadPosts: Bool
    var hideReadPostsMode: HideReadPostsFilter.Mode

    var storageSize: String
    var storageFileUrl: URL

    // MARK: Community directory (Explorer)

    let allExplorerRefreshIntervals: [Preferences.ExplorerRefreshInterval] =
        Preferences.ExplorerRefreshInterval.allCases

    /// Whether the bundled community/instance directory auto-refreshes at launch.
    var explorerAutoRefresh: Bool
    /// How often it auto-refreshes when enabled.
    var explorerRefreshInterval: Preferences.ExplorerRefreshInterval
    /// When the directory was last successfully fetched from the network; nil
    /// until the first refresh (the app ships with a bundled seed).
    var communityDataLastUpdated: Date?
    /// True while a manual "Update Now" fetch is in flight.
    var isRefreshingCommunityData: Bool = false
    /// Set when the most recent manual fetch failed (e.g. no connection).
    var communityDataRefreshFailed: Bool = false

    /// Async sequence of URLs that the user tapped in the link-testing footer.
    /// The view controller drains this stream to open the URL through
    /// `AppService` honouring the current user preferences.
    @ObservationIgnored
    let externalLinkRequested: AsyncStream<URL>

    @ObservationIgnored
    private let externalLinkRequestedContinuation: AsyncStream<URL>.Continuation

    /// Fired when the user taps the "Drafts & Outbox" row. The view controller
    /// drains this stream and pushes `OutboundContentListViewController`.
    @ObservationIgnored
    let draftsOutboxRequested: AsyncStream<Void>

    @ObservationIgnored
    private let draftsOutboxRequestedContinuation: AsyncStream<Void>.Continuation

    @ObservationIgnored
    private var preferenceObservationTasks: [Task<Void, Never>] = []

    init(
        defaultPostSortType initialDefaultPostSortType: Components.Schemas.SortType,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        self.dependencies = (own: dependencies, nested: dependencies)
        self.accountKeychainId = accountKeychainId

        allPostSortTypes = Components.Schemas.SortType.allCases
        allCommentSortTypes = Components.Schemas.CommentSortType.allCases

        defaultPostSortType = initialDefaultPostSortType
        defaultCommentSortType = dependencies.preferencesService.defaultCommentSortType

        openExternalLink = dependencies.preferencesService.openExternalLinks
        openExternalLinkInSafariVCReaderMode =
            dependencies.preferencesService.openExternalLinksInSafariVCReaderMode
        openExternalLinkAsUniversalLinkInApp =
            dependencies.preferencesService.openUniversalLinkInApp
        openInBrowserInstance = dependencies.preferencesService.openInBrowserInstance
        shareLinkInstance = dependencies.preferencesService.shareLinkInstance
        urlSanitizerConfig = dependencies.preferencesService.urlSanitizerConfig

        appTheme = dependencies.preferencesService.appTheme
        accentColor = dependencies.preferencesService.accentColor

        postDensity = dependencies.preferencesService.postDensity
        thumbnailPosition = dependencies.preferencesService.thumbnailPosition
        postTextScale = dependencies.preferencesService.postTextScale
        showVoteButtons = dependencies.preferencesService.showVoteButtons
        showNsfw = dependencies.preferencesService.showNsfw
        blurNsfw = dependencies.preferencesService.blurNsfw
        fetchLinkEmbeds = dependencies.preferencesService.fetchLinkEmbeds
        hasAcknowledgedNsfwAge = dependencies.preferencesService.hasAcknowledgedNsfwAge
        markPostsRead = dependencies.preferencesService.markPostsRead
        markPostsReadOnScroll = dependencies.preferencesService.markPostsReadOnScroll
        hideReadPosts = dependencies.preferencesService.hideReadPosts
        hideReadPostsMode = dependencies.preferencesService.hideReadPostsMode

        postSwipeActions = dependencies.preferencesService.postSwipeActions
        commentSwipeActions = dependencies.preferencesService.commentSwipeActions

        storageSize = ByteCountFormatter.string(
            fromByteCount: Int64(dependencies.appDatabase.sizeInBytes),
            countStyle: .file
        )
        storageFileUrl = dependencies.appDatabase.storeURL ?? URL(fileURLWithPath: "/")

        explorerAutoRefresh = dependencies.preferencesService.explorerAutoRefreshEnabled
        explorerRefreshInterval = dependencies.preferencesService.explorerRefreshInterval
        communityDataLastUpdated = dependencies.appDatabase.explorerLastFetchedAtSync()

        let (stream, continuation) = AsyncStream<URL>.makeStream()
        externalLinkRequested = stream
        externalLinkRequestedContinuation = continuation

        let (draftsStream, draftsContinuation) = AsyncStream<Void>.makeStream()
        draftsOutboxRequested = draftsStream
        draftsOutboxRequestedContinuation = draftsContinuation

        let preferencesService = dependencies.preferencesService

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.defaultCommentSortTypeStream {
                self?.defaultCommentSortType = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openExternalLinksStream {
                self?.openExternalLink = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openInBrowserInstanceStream {
                self?.openInBrowserInstance = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.shareLinkInstanceStream {
                self?.shareLinkInstance = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.openExternalLinksInSafariVCReaderModeStream {
                self?.openExternalLinkInSafariVCReaderMode = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.appThemeStream {
                self?.appTheme = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.accentColorStream {
                self?.accentColor = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.postSwipeActionsStream {
                self?.postSwipeActions = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.commentSwipeActionsStream {
                self?.commentSwipeActions = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.postDensityStream {
                self?.postDensity = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.thumbnailPositionStream {
                self?.thumbnailPosition = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.postTextScaleStream {
                self?.postTextScale = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.showVoteButtonsStream {
                self?.showVoteButtons = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.showNsfwStream {
                self?.showNsfw = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.blurNsfwStream {
                self?.blurNsfw = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.fetchLinkEmbedsStream {
                self?.fetchLinkEmbeds = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.markPostsReadStream {
                self?.markPostsRead = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.markPostsReadOnScrollStream {
                self?.markPostsReadOnScroll = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.hideReadPostsStream {
                self?.hideReadPosts = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.hideReadPostsModeStream {
                self?.hideReadPostsMode = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.explorerAutoRefreshEnabledStream {
                self?.explorerAutoRefresh = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.explorerRefreshIntervalStream {
                self?.explorerRefreshInterval = value
            }
        })

        preferenceObservationTasks.append(Task { @MainActor [weak self] in
            for await value in preferencesService.urlSanitizerConfigStream {
                self?.urlSanitizerConfig = value
            }
        })
    }

    /// Preview-only init with seed values and no service dependencies.
    /// Mutations write back to local state only.
    init(preview: Void = ()) {
        dependencies = nil
        accountKeychainId = ""
        externalLinkRequestedContinuation = AsyncStream<URL>.makeStream().continuation
        externalLinkRequested = AsyncStream { _ in }
        draftsOutboxRequestedContinuation = AsyncStream<Void>.makeStream().continuation
        draftsOutboxRequested = AsyncStream { _ in }

        allPostSortTypes = Components.Schemas.SortType.allCases
        allCommentSortTypes = Components.Schemas.CommentSortType.allCases
        defaultPostSortType = .Hot
        defaultCommentSortType = .Hot
        openExternalLink = .safariViewController
        openExternalLinkInSafariVCReaderMode = true
        openExternalLinkAsUniversalLinkInApp = true
        openInBrowserInstance = .myInstance
        shareLinkInstance = .originalInstance
        urlSanitizerConfig = .default
        appTheme = .system
        accentColor = .lemmy
        postDensity = .comfortable
        thumbnailPosition = .left
        postTextScale = 0
        showVoteButtons = true
        showNsfw = false
        blurNsfw = true
        fetchLinkEmbeds = true
        hasAcknowledgedNsfwAge = false
        markPostsRead = true
        markPostsReadOnScroll = false
        hideReadPosts = false
        hideReadPostsMode = .onRefresh
        postSwipeActions = .defaultPosts
        commentSwipeActions = .defaultComments
        storageSize = "128 MB"
        storageFileUrl = URL(fileURLWithPath: "/tmp")
        explorerAutoRefresh = true
        explorerRefreshInterval = .daily
        communityDataLastUpdated = nil
    }

    deinit {
        externalLinkRequestedContinuation.finish()
        draftsOutboxRequestedContinuation.finish()
        for task in preferenceObservationTasks {
            task.cancel()
        }
    }

    // MARK: Inputs

    func openDraftsOutbox() {
        draftsOutboxRequestedContinuation.yield(())
    }

    func testExternalLink(_ url: URL) {
        externalLinkRequestedContinuation.yield(url)
    }

    func updateDefaultPostSort(_ value: Components.Schemas.SortType) {
        defaultPostSortType = value
        // The default post sort is a per-account value (the getter reads it from
        // the account's stored record), so it must persist to the account store,
        // not UserDefaults. Without this it reset to the baseline on relaunch.
        accountService?.setDefaultSortType(value, forAccountKeychainId: accountKeychainId)
        // Best-effort: mirror the choice up to the server (`save_user_settings`)
        // so it follows the account across devices. Signed-out accounts no-op
        // server-side; a network failure is fine — the local value above stands.
        if let accountService {
            let scope = accountService.scope(forAccountKeychainId: accountKeychainId)
            Task { try? await scope.lemmyService.setDefaultSortType(value) }
        }
    }

    func updateDefaultCommentSort(_ value: Components.Schemas.CommentSortType) {
        defaultCommentSortType = value
        preferencesService?.defaultCommentSortType = value
    }

    func updateOpenExternalLink(_ value: Preferences.OpenExternalLink) {
        openExternalLink = value
        preferencesService?.openExternalLinks = value
    }

    func updateOpenExternalLinkInSafariVCReaderMode(_ value: Bool) {
        openExternalLinkInSafariVCReaderMode = value
        preferencesService?.openExternalLinksInSafariVCReaderMode = value
    }

    func updateOpenExternalLinkAsUniversalLinkInApp(_ value: Bool) {
        openExternalLinkAsUniversalLinkInApp = value
        preferencesService?.openUniversalLinkInApp = value
    }

    func updateOpenInBrowserInstance(_ value: Preferences.LinkInstance) {
        openInBrowserInstance = value
        preferencesService?.openInBrowserInstance = value
    }

    func updateShareLinkInstance(_ value: Preferences.LinkInstance) {
        shareLinkInstance = value
        preferencesService?.shareLinkInstance = value
    }

    // MARK: URL hygiene

    private func mutateSanitizerConfig(_ mutate: (inout URLSanitizerConfig) -> Void) {
        var updated = urlSanitizerConfig
        mutate(&updated)
        guard updated != urlSanitizerConfig else { return }
        urlSanitizerConfig = updated
        preferencesService?.urlSanitizerConfig = updated
    }

    func updateSanitizerEnabled(_ value: Bool) {
        mutateSanitizerConfig { $0.isEnabled = value }
    }

    func updateStripTrackingParams(_ value: Bool) {
        mutateSanitizerConfig { $0.stripTrackingParams = value }
    }

    func updateUnwrapRedirectors(_ value: Bool) {
        mutateSanitizerConfig { $0.unwrapRedirectors = value }
    }

    func updateUpgradeToHTTPS(_ value: Bool) {
        mutateSanitizerConfig { $0.upgradeToHTTPS = value }
    }

    func updateDeAMP(_ value: Bool) {
        mutateSanitizerConfig { $0.deAMP = value }
    }

    func updateRedirectToFrontEnds(_ value: Bool) {
        mutateSanitizerConfig { $0.redirectToFrontEnds = value }
    }

    func updateFrontEndEnabled(_ service: FrontEndService, _ value: Bool) {
        mutateSanitizerConfig { config in
            config.frontEnds = config.frontEnds.map { entry in
                guard entry.service == service else { return entry }
                return FrontEndConfig(service: service, isEnabled: value, host: entry.host)
            }
        }
    }

    func updateFrontEndHost(_ service: FrontEndService, _ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateSanitizerConfig { config in
            config.frontEnds = config.frontEnds.map { entry in
                guard entry.service == service else { return entry }
                return FrontEndConfig(service: service, isEnabled: entry.isEnabled, host: trimmed)
            }
        }
    }

    func resetFrontEndHost(_ service: FrontEndService) {
        let defaultHost = FrontEndCatalog.entry(for: service).defaultHost
        updateFrontEndHost(service, defaultHost)
    }

    func updateAppTheme(_ value: AppTheme) {
        guard value != appTheme else { return }
        appTheme = value
        preferencesService?.appTheme = value
        Haptics.tap()
    }

    func updateAccentColor(_ value: AccentColor) {
        guard value != accentColor else { return }
        accentColor = value
        preferencesService?.accentColor = value
        Haptics.tap()
    }

    // MARK: Reading / display (M8)

    func updatePostDensity(_ value: PostDensity) {
        guard value != postDensity else { return }
        postDensity = value
        preferencesService?.postDensity = value
        Haptics.tap()
    }

    func updateThumbnailPosition(_ value: ThumbnailPosition) {
        guard value != thumbnailPosition else { return }
        thumbnailPosition = value
        preferencesService?.thumbnailPosition = value
        Haptics.tap()
    }

    func updatePostTextScale(_ value: CGFloat) {
        guard value != postTextScale else { return }
        postTextScale = value
        preferencesService?.postTextScale = value
    }

    func updateShowVoteButtons(_ value: Bool) {
        guard value != showVoteButtons else { return }
        showVoteButtons = value
        preferencesService?.showVoteButtons = value
        Haptics.tap()
    }

    func acknowledgeNsfwAge() {
        hasAcknowledgedNsfwAge = true
        preferencesService?.hasAcknowledgedNsfwAge = true
    }

    func updateShowNsfw(_ value: Bool) {
        guard value != showNsfw else { return }
        showNsfw = value
        // Writing the local preference is enough: the post lists observe
        // `showNsfwStream` and re-fetch with the new request param, and the
        // frontpage list mirrors the value to the server for signed-in
        // accounts. Discover reads the same preference.
        preferencesService?.showNsfw = value
        Haptics.tap()
    }

    func updateBlurNsfw(_ value: Bool) {
        guard value != blurNsfw else { return }
        blurNsfw = value
        // Local write is enough: post lists / post detail observe
        // `blurNsfwStream` and re-apply blur in place, and the frontpage list
        // mirrors the value to the server for signed-in accounts.
        preferencesService?.blurNsfw = value
        Haptics.tap()
    }

    func updateFetchLinkEmbeds(_ value: Bool) {
        guard value != fetchLinkEmbeds else { return }
        fetchLinkEmbeds = value
        preferencesService?.fetchLinkEmbeds = value
    }

    func updateMarkPostsRead(_ value: Bool) {
        guard value != markPostsRead else { return }
        markPostsRead = value
        preferencesService?.markPostsRead = value
    }

    func updateMarkPostsReadOnScroll(_ value: Bool) {
        guard value != markPostsReadOnScroll else { return }
        markPostsReadOnScroll = value
        preferencesService?.markPostsReadOnScroll = value
    }

    func updateHideReadPosts(_ value: Bool) {
        guard value != hideReadPosts else { return }
        hideReadPosts = value
        preferencesService?.hideReadPosts = value
    }

    func updateHideReadPostsMode(_ value: HideReadPostsFilter.Mode) {
        guard value != hideReadPostsMode else { return }
        hideReadPostsMode = value
        preferencesService?.hideReadPostsMode = value
    }

    // MARK: Swipe actions

    /// Assigns `action` to a single post swipe `slot` and persists the config.
    func updatePostSwipeAction(_ action: SwipeAction, for slot: SwipeActionSlot) {
        let updated = postSwipeActions.setting(action, for: slot)
        guard updated != postSwipeActions else { return }
        postSwipeActions = updated
        preferencesService?.postSwipeActions = updated
    }

    /// Assigns `action` to a single comment swipe `slot` and persists the
    /// config. Invalid pairings (e.g. assigning a non-comment action) are kept
    /// as-is; the cell layer sanitizes before driving the gesture.
    func updateCommentSwipeAction(_ action: SwipeAction, for slot: SwipeActionSlot) {
        let updated = commentSwipeActions.setting(action, for: slot)
        guard updated != commentSwipeActions else { return }
        commentSwipeActions = updated
        preferencesService?.commentSwipeActions = updated
    }

    /// Restores post swipe actions to the shipped defaults.
    func resetPostSwipeActions() {
        postSwipeActions = .defaultPosts
        preferencesService?.postSwipeActions = .defaultPosts
        Haptics.tap()
    }

    /// Restores comment swipe actions to the shipped defaults.
    func resetCommentSwipeActions() {
        commentSwipeActions = .defaultComments
        preferencesService?.commentSwipeActions = .defaultComments
        Haptics.tap()
    }

    // MARK: Community directory (Explorer)

    func updateExplorerAutoRefresh(_ value: Bool) {
        guard value != explorerAutoRefresh else { return }
        explorerAutoRefresh = value
        preferencesService?.explorerAutoRefreshEnabled = value
    }

    func updateExplorerRefreshInterval(_ value: Preferences.ExplorerRefreshInterval) {
        guard value != explorerRefreshInterval else { return }
        explorerRefreshInterval = value
        preferencesService?.explorerRefreshInterval = value
    }

    /// Force a full network refresh of the community/instance directory. Updates
    /// the "last updated" stamp on success; flags a failure otherwise. Ignored
    /// while a refresh is already running.
    func refreshCommunityDataNow() {
        guard let explorerService, !isRefreshingCommunityData else { return }
        isRefreshingCommunityData = true
        communityDataRefreshFailed = false
        Haptics.tap()

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isRefreshingCommunityData = false }
            do {
                try await explorerService.refreshAll()
                communityDataLastUpdated = appDatabase?.explorerLastFetchedAtSync()
            } catch {
                communityDataRefreshFailed = true
            }
        }
    }
}
