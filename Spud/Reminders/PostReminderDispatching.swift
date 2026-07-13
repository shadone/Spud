//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// The denormalized whole-post (or comment-subtree, Phase 3) fields needed to
/// set a "Remind Me…" time or activity reminder (spec §4 /
/// `ReminderService.setTimeReminder`/`setActivityReminder`), gathered by the
/// conformer from its own row model (`PostDetailHeaderRow` in post detail,
/// `PostListRow` in the feed, or `PostDetailCommentRow` for a comment's
/// subtree) so the shared menu builder below never needs to know about any of
/// the row types.
struct RemindMeMenuTarget {
    let postServerId: Int64
    /// The reminder's routing/permalink URL - the POST's ap_id for a
    /// whole-post target, or the COMMENT's ap_id (`originalCommentUrl`) for a
    /// subtree target, so a fired subtree reminder's notification tap opens
    /// the post scrolled to that comment (`objectAtURL` classification).
    let apId: String
    let title: String
    let communityName: String
    let instanceHost: String
    let thumbnailUrl: String?
    /// The row's current comment count - the fallback baseline for
    /// `setActivityReminder` when a fresher sync read comes back nil (e.g.
    /// the post/comment row was evicted between long-press and tap). For a
    /// whole-post target this is the post's comment count; for a subtree
    /// target it's the root comment's `childCount` (descendant count).
    let numberOfComments: Int64
    /// `ReminderRecord.wholePostSentinel` (the default) for a whole-post
    /// "Remind Me…" (post-detail overflow menu / feed cell long-press), or a
    /// comment's server id to scope the reminder to that comment's SUBTREE
    /// (Phase 3, comment long-press context menu). Threaded through every
    /// `ReminderService` call and the `activeReminderKindsSync` checkmark
    /// read below, so a whole-post reminder and one or more subtree
    /// reminders (on different comments) coexist independently on the same
    /// post - existing whole-post callers that don't pass this get the
    /// sentinel and are unaffected.
    let rootCommentServerId: Int64

    /// - Parameter rootCommentServerId: defaults to
    ///   `ReminderRecord.wholePostSentinel` so every existing whole-post
    ///   caller (post detail, feed cell) compiles unchanged; only the
    ///   comment context menu (Phase 3) passes a comment's server id.
    init(
        postServerId: Int64,
        apId: String,
        title: String,
        communityName: String,
        instanceHost: String,
        thumbnailUrl: String?,
        numberOfComments: Int64,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) {
        self.postServerId = postServerId
        self.apId = apId
        self.title = title
        self.communityName = communityName
        self.instanceHost = instanceHost
        self.thumbnailUrl = thumbnailUrl
        self.numberOfComments = numberOfComments
        self.rootCommentServerId = rootCommentServerId
    }
}

/// Shared "Remind Me…" (whole post) menu building + dispatch for every screen
/// offering a reminder on a post — the post-detail ••• overflow menu and the
/// feed cell long-press context menu (plan Task 6).
///
/// Mirrors the `PostVoteDispatching`/`PostSaveDispatching` split in
/// `PostActions.swift`: conformers supply the account scope, alert service,
/// and app database (all three already exposed by both screens as
/// `postActionsAccountScope`/`postActionsAlertService`/`appDatabase`); the
/// default implementations here build the `UIMenu` and drive
/// `ReminderService`.
@MainActor
protocol PostReminderDispatching: UIViewController {
    var postActionsAccountScope: AccountScope { get }
    var postActionsAlertService: AlertServiceType { get }
    var appDatabase: AppDatabase { get }

    /// Called after a reminder is set or cancelled, so a conformer with a
    /// CACHED `UIMenu` (post detail's overflow bar-button item, rebuilt only
    /// when its header row changes) can rebuild it to reflect the new
    /// "Cancel reminder" state. The feed's context menu is rebuilt fresh on
    /// every long-press, so it can leave this a no-op.
    func remindMeMenuDidChange()
}

@MainActor
extension PostReminderDispatching {
    /// Builds the "Remind Me" submenu (SF Symbol `bell`) for `target`: a
    /// `UIAction` per `ReminderPreset` (spec order via `RemindMeMenu.items()`),
    /// a "Pick a time…" action presenting the custom-time sheet, a
    /// self-toggling "When there are new comments" action (checkmarked when a
    /// live `activity` reminder exists), and — when a live `time` reminder
    /// already exists on this target (`activeReminderKindsSync`) — a
    /// destructive "Cancel reminder" action. Time and activity reminders are
    /// independent: each toggles/checkmarks on its own state, so a post can
    /// carry both at once. Mirrors `makeMuteCommunityMenu` (post detail / feed).
    func makeRemindMeMenu(for target: RemindMeMenuTarget) -> UIMenu {
        var children: [UIMenuElement] = RemindMeMenu.items().map { item in
            switch item {
            case let .preset(preset):
                UIAction(title: preset.menuTitle) { [weak self] _ in
                    self?.setReminder(
                        target: target,
                        fireAt: preset.resolvedDate(now: Date(), calendar: .current),
                        timeDescription: preset.menuTitle
                    )
                }

            case .customTime:
                UIAction(
                    title: NSLocalizedString("Pick a time…", comment: "Remind Me menu action to choose a custom reminder time"),
                    image: UIImage(systemName: "calendar.badge.clock")
                ) { [weak self] _ in
                    self?.presentRemindMeTimePicker(for: target)
                }

            case .activityNewComments:
                UIAction(
                    title: NSLocalizedString(
                        "When there are new comments",
                        comment: "Remind Me menu action to follow a post and be notified as its discussion grows"
                    ),
                    image: UIImage(systemName: "bubble.left.and.bubble.right"),
                    state: hasActiveActivityReminder(target: target) ? .on : .off
                ) { [weak self] _ in
                    self?.toggleActivityReminder(target: target)
                }
            }
        }

        if hasActiveTimeReminder(target: target) {
            children.append(UIAction(
                title: NSLocalizedString("Cancel reminder", comment: "Remind Me menu action to cancel an existing reminder on this post"),
                // `alarm` rather than `bell.slash` - the latter is also
                // `makeMuteCommunityMenu`'s "Mute community" symbol, and both
                // actions can appear together in the same post-detail overflow
                // menu, so sharing a symbol would make them hard to tell apart
                // at a glance.
                image: UIImage(systemName: "alarm"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.cancelReminder(postServerId: target.postServerId, rootCommentServerId: target.rootCommentServerId)
            })
        }

        return UIMenu(
            title: NSLocalizedString("Remind Me…", comment: "Overflow/context-menu submenu title to set a reminder on a post"),
            image: UIImage(systemName: "bell"),
            children: children
        )
    }

    /// Whether a live (still-`scheduled`) time reminder exists on `target`'s
    /// scope (the whole post, or - Phase 3 - the comment subtree named by its
    /// `rootCommentServerId`) under the current account — drives the menu's
    /// "Cancel reminder" affordance. A synchronous GRDB read (mirrors the
    /// pattern used to gate the moderation submenu), safe to call while
    /// building a `UIMenu`.
    private func hasActiveTimeReminder(target: RemindMeMenuTarget) -> Bool {
        activeReminderKinds(target: target).contains(ReminderRecord.Kind.time.rawValue)
    }

    /// Whether a live activity reminder (`scheduled` **or** `fired` - a fired
    /// follow keeps polling, see `activeReminderKindsSync`) exists on
    /// `target`'s scope under the current account — drives the "When there
    /// are new comments" action's checkmark. Sibling of
    /// `hasActiveTimeReminder`; the two kinds are independent so each reads
    /// (and checkmarks) its own state.
    private func hasActiveActivityReminder(target: RemindMeMenuTarget) -> Bool {
        activeReminderKinds(target: target).contains(ReminderRecord.Kind.activity.rawValue)
    }

    /// Reads the active reminder kinds for `(target.postServerId,
    /// target.rootCommentServerId)` - a whole-post target and a subtree
    /// target on the same post never see each other's kinds, so a subtree
    /// follow's checkmark can never leak onto (or be masked by) the
    /// whole-post menu, or a sibling subtree on a different comment.
    private func activeReminderKinds(target: RemindMeMenuTarget) -> Set<String> {
        guard
            let accountId = appDatabase.accountRowIdSync(forKeychainId: postActionsAccountScope.accountKeychainId)
        else {
            return []
        }
        return appDatabase.activeReminderKindsSync(
            accountId: accountId,
            postServerId: target.postServerId,
            rootCommentServerId: target.rootCommentServerId
        )
    }

    /// Sets (or replaces) a whole-post time reminder for `fireAt`, then shows
    /// a confirmation toast and refreshes the caller's cached menu, if any.
    /// - Parameter timeDescription: the human-readable time shown in the
    ///   confirmation toast (a preset's `menuTitle`, or a formatted date for
    ///   a custom pick).
    private func setReminder(target: RemindMeMenuTarget, fireAt: Date, timeDescription: String) {
        // Both the preset actions and the custom-time picker (via
        // `presentRemindMeTimePicker`) funnel through here, so this single
        // guard covers every "Remind Me…" surface (post detail and feed): a
        // blank `apId` would produce a reminder with a broken routing URL, so
        // treat it as a safe no-op instead of persisting a bad row.
        guard !target.apId.isEmpty else { return }
        Haptics.tap()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await postActionsAccountScope.reminderService.setTimeReminder(
                    postServerId: target.postServerId,
                    apId: target.apId,
                    fireAt: fireAt,
                    titleSnapshot: target.title,
                    communityName: target.communityName,
                    instanceHost: target.instanceHost,
                    thumbnailUrl: target.thumbnailUrl,
                    rootCommentServerId: target.rootCommentServerId
                )
                remindMeMenuDidChange()
                showReminderToast(String(
                    format: NSLocalizedString(
                        "Reminder set — %@",
                        comment: "Toast confirming a time reminder was scheduled; %@ is the time, e.g. \"Tomorrow\" or \"Jul 15, 9:00 AM\""
                    ),
                    timeDescription
                ))
            } catch {
                postActionsAlertService.handle(error, for: .setReminder)
            }
        }
    }

    /// Cancels the time reminder on `postServerId`'s scope (whole-post, or -
    /// Phase 3 - the comment subtree named by `rootCommentServerId`), if any,
    /// showing a confirmation toast and refreshing the caller's cached menu.
    /// A no-op (not an error) if no reminder exists, so this can always be
    /// wired to the destructive "Cancel reminder" action without a race
    /// check.
    private func cancelReminder(postServerId: Int64, rootCommentServerId: Int64) {
        Haptics.tap()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await postActionsAccountScope.reminderService.removeTimeReminder(
                    postServerId: postServerId,
                    rootCommentServerId: rootCommentServerId
                )
                remindMeMenuDidChange()
                showReminderToast(NSLocalizedString("Reminder cleared.", comment: "Toast confirming a reminder was cancelled"))
            } catch {
                postActionsAlertService.handle(error, for: .setReminder)
            }
        }
    }

    /// Toggles the activity ("When there are new comments") follow on
    /// `target`'s scope (whole-post, or - Phase 3 - the comment subtree named
    /// by `rootCommentServerId`): sets it if not already active, removes it
    /// if it is. Unlike the time reminder's separate preset/cancel actions,
    /// this single menu item is both the setter and the unsetter - re-reads
    /// the live active state at tap time (rather than trusting the checkmark
    /// computed when the menu was built) so a stale cached menu can never
    /// toggle the wrong direction. A no-op if `target.apId` is blank,
    /// mirroring `setReminder`'s guard.
    private func toggleActivityReminder(target: RemindMeMenuTarget) {
        guard !target.apId.isEmpty else { return }
        Haptics.tap()
        let isCurrentlyActive = hasActiveActivityReminder(target: target)
        Task { [weak self] in
            guard let self else { return }
            do {
                if isCurrentlyActive {
                    try await postActionsAccountScope.reminderService.removeActivityReminder(
                        postServerId: target.postServerId,
                        rootCommentServerId: target.rootCommentServerId
                    )
                    remindMeMenuDidChange()
                    showReminderToast(NSLocalizedString(
                        "Stopped following.",
                        comment: "Toast confirming a post's activity (new-comments) reminder was removed"
                    ))
                } else {
                    // Baseline against the freshest count we have: a live sync
                    // read if the target is cached locally, falling back to
                    // the row's own count (gathered when the menu's target was
                    // built) if not. A whole-post target baselines against the
                    // post's `numberOfComments`; a subtree target (Phase 3)
                    // baselines against the root COMMENT's `childCount`
                    // (descendant count) instead - the poll's count source for
                    // that scope (see `ReminderService.setActivityReminder`).
                    let baselineCount = if target.rootCommentServerId == ReminderRecord.wholePostSentinel {
                        Int64(
                            appDatabase.postNumberOfCommentsSync(
                                forKeychainId: postActionsAccountScope.accountKeychainId,
                                serverPostId: target.postServerId
                            ) ?? Int(target.numberOfComments)
                        )
                    } else {
                        Int64(
                            appDatabase.commentChildCountSync(
                                forKeychainId: postActionsAccountScope.accountKeychainId,
                                serverCommentId: target.rootCommentServerId
                            ) ?? Int(target.numberOfComments)
                        )
                    }
                    try await postActionsAccountScope.reminderService.setActivityReminder(
                        postServerId: target.postServerId,
                        apId: target.apId,
                        baselineCount: baselineCount,
                        titleSnapshot: target.title,
                        communityName: target.communityName,
                        instanceHost: target.instanceHost,
                        thumbnailUrl: target.thumbnailUrl,
                        rootCommentServerId: target.rootCommentServerId
                    )
                    remindMeMenuDidChange()
                    showReminderToast(NSLocalizedString(
                        "You'll be notified of new comments.",
                        comment: "Toast confirming a post's activity (new-comments) reminder was set"
                    ))
                }
            } catch {
                postActionsAlertService.handle(error, for: .setReminder)
            }
        }
    }

    /// Presents the "Pick a time…" sheet (form sheet - identical on iPhone
    /// and iPad), validating the chosen date is strictly in the future
    /// (`validCustomReminderDate`) before setting the reminder. A past pick
    /// is rejected with a warning haptic and no reminder is set - the sheet
    /// has already dismissed itself by then, so there's nowhere to show an
    /// inline error; the user can reopen the picker.
    private func presentRemindMeTimePicker(for target: RemindMeMenuTarget) {
        let picker = RemindMeTimePickerViewController { [weak self] pickedDate in
            guard let self, let validated = validCustomReminderDate(pickedDate, now: Date()) else {
                Haptics.warning()
                return
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            setReminder(target: target, fireAt: validated, timeDescription: formatter.string(from: validated))
        }
        let navigationController = UINavigationController(rootViewController: picker)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }

    private func showReminderToast(_ message: String) {
        guard let window = view.window else { return }
        ToastPresenter.shared.show(message, in: window)
    }
}
