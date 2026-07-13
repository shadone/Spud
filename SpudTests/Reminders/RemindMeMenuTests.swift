//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Covers `RemindMeMenu.items()` — the pure ordered menu model consumed by
/// the "Remind Me…" `UIMenu` builders in `PostReminderDispatching`. The
/// `UIMenu`/view-controller wiring is exercised by build + reviewer, per the
/// plan (Task 6).
struct RemindMeMenuTests {
    @Test
    func itemsAreThePresetsInSpecOrderFollowedByCustomTime() {
        #expect(RemindMeMenu.items() == [
            .preset(.inThreeHours),
            .preset(.thisEvening),
            .preset(.tomorrow),
            .preset(.inTwoDays),
            .preset(.inAWeek),
            .customTime,
        ])
    }
}
