//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// One item of the "Remind Me…" menu (spec §2.1). Phase 1 only offers the
/// time trigger; a later phase adds `.activity` (the "When there are new
/// comments" item) to this same enum.
enum RemindMeMenuItem: Equatable {
    case preset(ReminderPreset)
    case customTime
}

/// Pure model for the "Remind Me…" submenu (modeled on the existing
/// `MuteDuration` submenu): the ordered list of items to render, independent
/// of `UIMenu`/`UIAction`. UIKit wiring (icons, dispatch, the "Cancel
/// reminder" affordance) lives in `PostReminderDispatching`.
enum RemindMeMenu {
    /// The 5 time presets (`ReminderPreset.allCases`, in their declared spec
    /// order) followed by `.customTime` ("Pick a time…") - the menu's
    /// canonical display order.
    static func items() -> [RemindMeMenuItem] {
        ReminderPreset.allCases.map { .preset($0) } + [.customTime]
    }
}
