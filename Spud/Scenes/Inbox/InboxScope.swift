//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The segment selected in the inbox's segmented control.
enum InboxScope: Int, CaseIterable {
    case replies
    case mentions
    case reminders
    case messages

    var title: String {
        switch self {
        case .replies:
            NSLocalizedString("Replies", comment: "Inbox scope: comment replies")
        case .mentions:
            NSLocalizedString("Mentions", comment: "Inbox scope: mentions")
        case .reminders:
            NSLocalizedString("Reminders", comment: "Inbox scope: post reminders")
        case .messages:
            NSLocalizedString("Messages", comment: "Inbox scope: private messages")
        }
    }
}

/// The phase the inbox screen is in for the active scope. Drives which of the
/// designed states the view controller renders.
enum InboxPhase: Equatable {
    case loading
    case loaded
    case error
}
