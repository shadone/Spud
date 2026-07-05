//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum AppLaunchArgument: String {
    case staticImageService = "SPUDStaticImageService"

    /// Test-only: seed a signed-out default account on discuss.tchncs.de at
    /// launch so UI tests land on the feed. Restores the precondition the old
    /// auto-bootstrap used to provide, now that onboarding gates a fresh
    /// install. Never set by the shipping app.
    case seedSignedOutDefaultAccount = "SPUDSeedSignedOutDefaultAccount"

    /// Test-only: seed a signed-in default account on discuss.tchncs.de at
    /// launch (fixed keychain id, fake JWT) so UI tests can land on the app
    /// already authenticated, without a live login. DEBUG-only seam; never
    /// set by the shipping app.
    case seedSignedInDefaultAccount = "SPUDSeedSignedInDefaultAccount"
}
