//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import UIKit

/// Single entry point for "open the in-app instance screen for this host".
///
/// Replaces the open-instance-else-browser logic that was duplicated across the
/// Discover, Person, PostDetail, Search, and Community scenes. The actual
/// resolution (Explorer directory hit vs. live `/api/v3/site` probe vs. browser
/// fallback) lives in ``InstanceOrLoadingViewController``; this just pushes it
/// onto the presenting controller's navigation stack.
enum InstanceRouter {
    typealias Dependencies = InstanceOrLoadingViewController.Dependencies

    /// Pushes the in-app instance screen for `host` onto `presenter`'s
    /// navigation stack. Known hosts (Explorer directory or already resolved
    /// this session) open instantly; unknown hosts show a brief spinner while
    /// the host is probed, then open in-app if it speaks the Lemmy `/api/v3`
    /// API (PieFed included) or fall back to the browser otherwise.
    @MainActor
    static func openInstance(
        host: String,
        from presenter: UIViewController,
        accountKeychainId: String,
        dependencies: Dependencies
    ) {
        // A directory hit (or a host already resolved this session) needs no
        // probe — push the instance screen directly. Pushing the loading
        // wrapper and having it swap itself out mid-push animation flashes a
        // blank frame, so only use the wrapper when a network probe is needed.
        if let record = dependencies.appDatabase.explorerInstanceSync(baseurl: host)
            ?? ResolvedInstanceCache.shared.record(forHost: host)
        {
            let vc = InstanceExploreViewController(
                record: record,
                accountKeychainId: accountKeychainId,
                dependencies: dependencies
            )
            presenter.navigationController?.pushViewController(vc, animated: true)
            return
        }

        let vc = InstanceOrLoadingViewController(
            host: host,
            accountKeychainId: accountKeychainId,
            dependencies: dependencies
        )
        presenter.navigationController?.pushViewController(vc, animated: true)
    }
}
