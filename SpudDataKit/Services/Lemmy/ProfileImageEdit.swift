//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A pending change to the signed-in account's avatar or banner image, carried
/// from the Edit Profile editor into `LemmyServiceType.saveProfile` for the
/// durable server push.
///
/// Modeled as three explicit states so a save can tell "left alone" apart from
/// "cleared": only `.set` and `.removed` reach the server (via the neutral
/// `setAvatar`/`setBanner` and `removeAvatar`/`removeBanner` endpoints), while
/// `.unchanged` leaves both the server value and the local mirror untouched.
///
/// `.set` carries the raw encoded image bytes rather than an already-uploaded
/// url because the neutral profile-image endpoints take bytes: v4 posts them to
/// a dedicated multipart endpoint, and v3 uploads them to pict-rs then writes the
/// resulting url — the version split is hidden inside LemmyKit.
public enum ProfileImageEdit: Sendable, Equatable {
    /// The image was not touched in this edit — leave the server value and the
    /// local mirror as-is.
    case unchanged

    /// The image was replaced with a freshly-picked image. Carries the raw
    /// encoded bytes plus a filename and MIME type for the upload.
    case set(imageData: Data, fileName: String, contentType: String)

    /// The image was cleared.
    case removed
}
