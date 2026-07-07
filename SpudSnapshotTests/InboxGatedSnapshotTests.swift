//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshot of the Inbox screen's capability-gated content-unavailable state:
/// on a Lemmy 1.0 instance (whose v3 compat shim doesn't support the inbox
/// endpoints), the tab stays reachable but explains why instead of showing an
/// empty/error state (design D6, "explain-don't-hide").
///
/// Mirrors `PersonContentUnavailableSnapshotTests` / the `ActivitySnapshotTests`
/// empty-state tests: renders the exact `UIContentUnavailableConfiguration` the
/// `.gated` branch of `InboxViewController.updateContentUnavailable` builds
/// (SF Symbol `clock.badge.questionmark` + `CapabilityGateCopy.copy(for: .inbox,
/// host:)`) as a bare content view, rather than driving the whole screen VC
/// through its account/DB/dependency graph - this state doesn't depend on that
/// machinery beyond the two inputs the config builder takes (capability + host).
@MainActor
final class InboxGatedSnapshotTests: XCTestCase {
    private let width: CGFloat = 390
    private let height: CGFloat = 460

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    /// The exact `UIContentUnavailableConfiguration` the `.gated` branch of
    /// `InboxViewController.updateContentUnavailable` builds.
    private func gatedConfiguration(host: String?) -> UIContentUnavailableConfiguration {
        var config = UIContentUnavailableConfiguration.empty()
        let copy = CapabilityGateCopy.copy(for: .inbox, host: host)
        config.image = UIImage(systemName: "clock.badge.questionmark")
        config.text = copy.title
        config.secondaryText = copy.message
        return config
    }

    private func assertGated(
        host: String?,
        testName: String = #function,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let content = gatedConfiguration(host: host).makeContentView()
            content.frame = CGRect(x: 0, y: 0, width: width, height: height)
            content.backgroundColor = .systemBackground
            content.overrideUserInterfaceStyle = style
            content.layoutIfNeeded()
            assertSnapshot(
                matching: content,
                as: .image(size: CGSize(width: width, height: height), traits: traits(style)),
                named: style == .dark ? "dark" : "light",
                testName: testName,
                line: line
            )
        }
    }

    /// The common case: the instance host is known, so the copy names it.
    func test_gated_knownHost() {
        assertGated(host: "lemmy.example.com")
    }

    /// Fallback case: the host couldn't be resolved (e.g. `instanceActorId`
    /// returned nil) - the copy falls back to a generic "This instance" noun.
    func test_gated_unknownHost() {
        assertGated(host: nil)
    }
}
