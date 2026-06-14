//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The `User-Agent` Spud sends on every outbound HTTP request — Lemmy API calls
/// (via LemmyKit) and image fetches alike.
///
/// iOS' default URLSession agent carries a `CFNetwork/...` token that some Lemmy
/// instances' nginx denylist outright (a bare 403 on every request). A plain
/// `Spud/<version>` agent avoids that filter and identifies the app to admins.
enum AppUserAgent {
    static let value: String = {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "Spud/\(version)"
    }()
}
