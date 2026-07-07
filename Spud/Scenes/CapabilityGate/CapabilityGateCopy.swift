//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Localized title + message for the capability-gate sheet presented when the
/// user attempts an action the home instance's API doesn't support yet (an
/// older Lemmy version still on the v3 compat shim). Pure and total over
/// `InstanceCapability` — the UI gating tasks (post/comment/community actions)
/// call `copy(for:host:)` and hand the result to
/// `UIViewController.presentCapabilityGate(for:host:sourceView:)`.
struct CapabilityGateCopy: Equatable {
    let title: String
    let message: String

    /// Builds the copy for a blocked `capability`. `host` is the instance's
    /// hostname (e.g. "lemmy.world"); when unknown, the message falls back to
    /// a generic "This instance" noun.
    static func copy(for capability: InstanceCapability, host: String?) -> CapabilityGateCopy {
        let title: String
        let verbPhrase: String
        switch capability {
        case .personProfiles:
            title = NSLocalizedString(
                "Profiles aren't available yet",
                comment: "Capability gate sheet title: profiles unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "open profiles",
                comment: "Capability gate sheet body verb phrase: viewing a person's profile"
            )
        case .inbox:
            title = NSLocalizedString(
                "Inbox isn't available yet",
                comment: "Capability gate sheet title: inbox unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "load your inbox",
                comment: "Capability gate sheet body verb phrase: loading replies and mentions"
            )
        case .privateMessages:
            title = NSLocalizedString(
                "Messages aren't available yet",
                comment: "Capability gate sheet title: private messages unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "send or receive messages",
                comment: "Capability gate sheet body verb phrase: private messaging"
            )
        case .imageUpload:
            title = NSLocalizedString(
                "Image upload isn't available yet",
                comment: "Capability gate sheet title: image upload unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "upload images",
                comment: "Capability gate sheet body verb phrase: uploading an image"
            )
        case .serverUserSettings:
            title = NSLocalizedString(
                "Profile editing isn't available yet",
                comment: "Capability gate sheet title: saving profile settings unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "save profile changes",
                comment: "Capability gate sheet body verb phrase: saving profile edits"
            )
        case .hidePosts:
            title = NSLocalizedString(
                "Hiding posts isn't available yet",
                comment: "Capability gate sheet title: hiding posts unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "hide posts",
                comment: "Capability gate sheet body verb phrase: hiding a post"
            )
        case .markPostsRead:
            // Never presented (service-only soft-degrade); kept so the table
            // stays total over InstanceCapability.
            title = NSLocalizedString(
                "Read syncing isn't available yet",
                comment: "Capability gate sheet title: read-state sync unsupported by the instance's API version"
            )
            verbPhrase = NSLocalizedString(
                "sync read posts",
                comment: "Capability gate sheet body verb phrase: syncing read state to the server"
            )
        }

        let message = String(
            format: NSLocalizedString(
                "%1$@ runs a newer version of Lemmy. Spud can't %2$@ there yet — support is coming in an update.",
                comment: "Capability gate sheet body; %1$@ is the instance host (or a generic fallback noun), %2$@ the blocked action"
            ),
            host ?? NSLocalizedString(
                "This instance",
                comment: "Capability gate sheet body: fallback noun when the instance host is unknown"
            ),
            verbPhrase
        )

        return CapabilityGateCopy(title: title, message: message)
    }
}
