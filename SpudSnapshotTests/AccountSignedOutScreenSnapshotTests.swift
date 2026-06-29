//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Full-screen snapshot of the signed-out (anonymous) Account tab
/// (`AccountSignedOutView`): the centered guest header (avatar placeholder + bold
/// title + subtitle), the "Reading from <host>" row, the Create account / Log in
/// buttons, and the Settings row — mirroring the signed-in Account tab's grouped
/// style.
///
/// The view takes a plain host string and inert callbacks, so it renders
/// deterministically with no DB or async settling. `.image(size:traits:)` is
/// device- and runtime-sensitive — record on the reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class AccountSignedOutScreenSnapshotTests: XCTestCase {
    private let teal = Color(uiColor: UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1))

    func test_accountSignedOut_populated() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = AccountSignedOutView(
                instanceHostname: "lemmy.world",
                accent: teal,
                onChangeInstance: { },
                onCreateAccount: { },
                onLogIn: { },
                onSettings: { }
            )

            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 844)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(userInterfaceStyle: style)),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
