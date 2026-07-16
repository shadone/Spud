//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Localized title + message for the capability-gate sheet presented when the
/// user attempts an action the home instance's API doesn't support yet. Pure
/// and total over `InstanceCapability` — the UI gating tasks (post/comment/
/// community actions) call `copy(for:host:software:)` and hand the result to
/// `UIViewController.presentCapabilityGate(for:host:software:sourceView:)`.
///
/// The message wording is software-aware: on Lemmy the gap is framed as "this
/// instance is on an older version" (accurate — every gap Spud has today on
/// Lemmy is a version-shim gap), but that framing is FALSE on PieFed (and any
/// other non-Lemmy software this ever applies to) — a PieFed gap is a missing
/// dialect implementation, not a version lag. `software` defaults to `.lemmy`
/// so call sites that can't (yet) reach the account's resolved software keep
/// today's wording unchanged.
struct CapabilityGateCopy: Equatable {
    let title: String
    let message: String

    /// Builds the copy for a blocked `capability`. `host` is the instance's
    /// hostname (e.g. "lemmy.world"); when unknown, the message falls back to
    /// a generic "This instance" noun. `software` selects the message framing
    /// — see the type doc comment.
    static func copy(for capability: InstanceCapability, host: String?, software: InstanceSoftware = .lemmy) -> CapabilityGateCopy {
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

        let hostText = host ?? NSLocalizedString(
            "This instance",
            comment: "Capability gate sheet body: fallback noun when the instance host is unknown"
        )

        // Lemmy: every gap Spud has today is a v3-compat-shim version lag, so
        // naming "a newer version of Lemmy" is accurate and actionable. Any
        // other software (PieFed today) gets neutral wording instead — its
        // gaps are a missing dialect implementation, not a version lag, so
        // blaming "a newer version of Lemmy" would be simply false there.
        let messageFormat = software == .lemmy
            ? NSLocalizedString(
                "%1$@ runs a newer version of Lemmy. Spud can't %2$@ there yet — support is coming in an update.",
                comment: "Capability gate sheet body (Lemmy); %1$@ is the instance host (or a generic fallback noun), %2$@ the blocked action"
            )
            : NSLocalizedString(
                "%1$@ doesn't support this yet. Spud can't %2$@ there — support may come in a future update.",
                comment: "Capability gate sheet body (non-Lemmy software); %1$@ is the instance host (or a generic fallback noun), %2$@ the blocked action"
            )
        let message = String(format: messageFormat, hostText, verbPhrase)

        return CapabilityGateCopy(title: title, message: message)
    }
}
