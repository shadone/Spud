//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUIKit
import UIKit

/// The denormalized whole-post fields needed to set a "Remind Me…" time
/// reminder (spec §4 / `ReminderService.setTimeReminder`), gathered by the
/// conformer from its own row model (`PostDetailHeaderRow` in post detail,
/// `PostListRow` in the feed) so the shared menu builder below never needs to
/// know about either row type.
struct RemindMeMenuTarget {
    let postServerId: Int64
    let apId: String
    let title: String
    let communityName: String
    let instanceHost: String
    let thumbnailUrl: String?
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
    /// a "Pick a time…" action presenting the custom-time sheet, and — when a
    /// live `time` reminder already exists on this target
    /// (`activeReminderKindsSync`) — a destructive "Cancel reminder" action.
    /// Mirrors `makeMuteCommunityMenu` (post detail / feed).
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
            }
        }

        if hasActiveTimeReminder(postServerId: target.postServerId) {
            children.append(UIAction(
                title: NSLocalizedString("Cancel reminder", comment: "Remind Me menu action to cancel an existing reminder on this post"),
                image: UIImage(systemName: "bell.slash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.cancelReminder(postServerId: target.postServerId)
            })
        }

        return UIMenu(
            title: NSLocalizedString("Remind Me", comment: "Overflow/context-menu submenu title to set a reminder on a post"),
            image: UIImage(systemName: "bell"),
            children: children
        )
    }

    /// Whether a live (still-`scheduled`) time reminder exists on the whole
    /// post `postServerId` under the current account — drives the menu's
    /// "Cancel reminder" affordance. A synchronous GRDB read (mirrors the
    /// pattern used to gate the moderation submenu), safe to call while
    /// building a `UIMenu`.
    private func hasActiveTimeReminder(postServerId: Int64) -> Bool {
        guard
            let accountId = appDatabase.accountRowIdSync(forKeychainId: postActionsAccountScope.accountKeychainId)
        else {
            return false
        }
        return appDatabase.activeReminderKindsSync(
            accountId: accountId,
            postServerId: postServerId,
            rootCommentServerId: ReminderRecord.wholePostSentinel
        ).contains(ReminderRecord.Kind.time.rawValue)
    }

    /// Sets (or replaces) a whole-post time reminder for `fireAt`, then shows
    /// a confirmation toast and refreshes the caller's cached menu, if any.
    /// - Parameter timeDescription: the human-readable time shown in the
    ///   confirmation toast (a preset's `menuTitle`, or a formatted date for
    ///   a custom pick).
    private func setReminder(target: RemindMeMenuTarget, fireAt: Date, timeDescription: String) {
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
                    thumbnailUrl: target.thumbnailUrl
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

    /// Cancels the whole-post time reminder, if any, showing a confirmation
    /// toast and refreshing the caller's cached menu. A no-op (not an error)
    /// if no reminder exists, so this can always be wired to the destructive
    /// "Cancel reminder" action without a race check.
    private func cancelReminder(postServerId: Int64) {
        Haptics.tap()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await postActionsAccountScope.reminderService.removeTimeReminder(postServerId: postServerId)
                remindMeMenuDidChange()
                showReminderToast(NSLocalizedString("Reminder cleared.", comment: "Toast confirming a reminder was cancelled"))
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
