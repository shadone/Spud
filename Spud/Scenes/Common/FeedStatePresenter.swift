//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// A screen-agnostic description of a failed-load surface: the glyph, copy, and
/// the actions to offer. Each screen renders this into its own UI (e.g. a
/// `UIContentUnavailableConfiguration`) and wires the action closures.
struct FeedErrorDescriptor: Equatable {
    enum Action: Equatable { case retry, workOffline, copyDetails }

    struct ButtonSpec: Equatable {
        let title: String
        let action: Action
    }

    let symbolName: String
    let title: String
    let message: String
    let primary: ButtonSpec
    let secondary: ButtonSpec?
}

enum FeedStatePresenter {
    static func descriptor(for kind: LoadFailure.Kind, host: String?) -> FeedErrorDescriptor {
        let tryAgain = FeedErrorDescriptor.ButtonSpec(
            title: NSLocalizedString("Try again", comment: "Feed error-state primary action"),
            action: .retry
        )

        switch kind {
        case .offline:
            return FeedErrorDescriptor(
                symbolName: "wifi.slash",
                title: NSLocalizedString("You're offline", comment: "Feed offline-state title"),
                message: NSLocalizedString(
                    "Spud will retry automatically when you're back online.",
                    comment: "Feed offline-state message"
                ),
                primary: tryAgain,
                secondary: nil
            )

        case .unreachable:
            let title: String
            if let host {
                title = String(
                    format: NSLocalizedString(
                        "Couldn't reach %@",
                        comment: "Feed error-state title; %@ is the instance host, e.g. lemmy.world"
                    ),
                    host
                )
            } else {
                title = NSLocalizedString(
                    "Couldn't reach the server",
                    comment: "Feed error-state title when the instance host is unknown"
                )
            }
            return FeedErrorDescriptor(
                symbolName: "globe",
                title: title,
                message: NSLocalizedString(
                    "The server may be down or your connection is unstable.",
                    comment: "Feed unreachable-state message"
                ),
                primary: tryAgain,
                secondary: FeedErrorDescriptor.ButtonSpec(
                    title: NSLocalizedString("Work offline", comment: "Feed error-state secondary action"),
                    action: .workOffline
                )
            )

        case .malformedResponse:
            let message: String
            if let host {
                message = String(
                    format: NSLocalizedString(
                        "Spud couldn't read the response from %@. This might be a bug.",
                        comment: "Feed malformed-response message; %@ is the instance host"
                    ),
                    host
                )
            } else {
                message = NSLocalizedString(
                    "Spud couldn't read the server's response. This might be a bug.",
                    comment: "Feed malformed-response message when the host is unknown"
                )
            }
            return FeedErrorDescriptor(
                symbolName: "exclamationmark.triangle",
                title: NSLocalizedString("Something went wrong", comment: "Feed malformed-response title"),
                message: message,
                primary: tryAgain,
                secondary: FeedErrorDescriptor.ButtonSpec(
                    title: NSLocalizedString("Copy details", comment: "Feed malformed-response secondary action"),
                    action: .copyDetails
                )
            )
        }
    }
}
