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

    /// Test-only: delete the on-disk `AppDatabase` directory in the App Group
    /// container BEFORE it is first opened, so a UI test starts from a truly
    /// fresh install even on a dirty simulator. The App Group database survives
    /// SBT's `ResetFilesystem` and `simctl uninstall`; a persisted default
    /// account left by an earlier suite makes both seeds above no-op. Handled at
    /// the top of `AppDelegate.init` (before the DI graph opens `AppDatabase`).
    /// DEBUG-only seam; never set by the shipping app.
    case wipeAppDatabase = "SPUDWipeAppDatabase"
}
