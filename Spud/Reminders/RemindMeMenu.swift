//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// One item of the "Remind Me…" menu (spec §2.1). `.activityNewComments`
/// (Phase 2) is the "When there are new comments" whole-post follow - unlike
/// the time-based `.preset`/`.customTime` items (which share one destructive
/// "Cancel reminder" action, built separately in `PostReminderDispatching`),
/// it renders as a single self-toggling action (checkmarked when a live
/// activity reminder exists on the target, tapping it sets or removes).
enum RemindMeMenuItem: Equatable {
    case preset(ReminderPreset)
    case customTime
    case activityNewComments
}

/// Pure model for the "Remind Me…" submenu (modeled on the existing
/// `MuteDuration` submenu): the ordered list of items to render, independent
/// of `UIMenu`/`UIAction`. UIKit wiring (icons, dispatch, the "Cancel
/// reminder" affordance) lives in `PostReminderDispatching`.
enum RemindMeMenu {
    /// The 5 time presets (`ReminderPreset.allCases`, in their declared spec
    /// order), followed by `.customTime` ("Pick a time…"), followed by
    /// `.activityNewComments` ("When there are new comments") - the menu's
    /// canonical display order. Time and activity reminders are independent
    /// (a post can have both live at once), so `.activityNewComments` is
    /// listed unconditionally rather than as an alternative to the presets.
    static func items() -> [RemindMeMenuItem] {
        ReminderPreset.allCases.map { .preset($0) } + [.customTime, .activityNewComments]
    }
}
