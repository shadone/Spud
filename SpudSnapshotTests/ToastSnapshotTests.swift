//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the toast pill in both forms: plain text (confirmation /
/// failure toasts) and with a trailing accent "Undo" button. Rendered on a
/// fixed-size, pinned-scale host so references are device-independent.
///
/// The pill's background is a real Liquid Glass `UIVisualEffectView`
/// (`ToastView`'s `glassView`) since Task 16 of the Liquid Glass conversion:
/// like any `UIVisualEffectView` material, it (and everything nested in its
/// `contentView` — here, the whole message/button stack) renders as invisible
/// under the default offscreen `.image(size:traits:)` strategy, which draws via
/// `layer.render(in:)` and does not composite `UIVisualEffectView` content. This
/// suite captures with `drawHierarchyInKeyWindow: true` instead, the same fix
/// `PostDetailHeaderSnapshotTests`/`PostListNsfwBlurSnapshotTests` use for their
/// own `UIVisualEffectView`-bearing renders.
@MainActor
final class ToastSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pin the host scene's status bar hidden so this on-screen
        // (`drawHierarchyInKeyWindow`) capture is immune to the sim's persisted
        // orientation state. See `SnapshotDeterminism.pinStatusBarHidden()`.
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private let width: CGFloat = 390

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
            SnapshotDeterminism.contentSizeTrait,
        ])
    }

    private func host(_ toast: ToastView, height: CGFloat) -> UIView {
        let size = CGSize(width: width, height: height)
        let container = UIView(frame: CGRect(origin: .zero, size: size))
        container.backgroundColor = .systemBackground
        toast.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
        ])
        container.layoutIfNeeded()
        return container
    }

    func test_plainToast_light() {
        assertPlain(style: .light)
    }

    func test_plainToast_dark() {
        assertPlain(style: .dark)
    }

    func test_undoToast_light() {
        assertUndo(style: .light)
    }

    func test_undoToast_dark() {
        assertUndo(style: .dark)
    }

    private func assertPlain(style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = host(ToastView(message: "Back to where you were"), height: 96)
        assertSnapshot(
            matching: view,
            as: .image(drawHierarchyInKeyWindow: true, size: view.bounds.size, traits: traits(style)),
            named: style == .dark ? "dark" : "light", testName: testName, line: line
        )
    }

    private func assertUndo(style: UIUserInterfaceStyle, testName: String = #function, line: UInt = #line) {
        let view = host(ToastView(message: "Jumped to top", actionTitle: "Undo", action: { }), height: 96)
        assertSnapshot(
            matching: view,
            as: .image(drawHierarchyInKeyWindow: true, size: view.bounds.size, traits: traits(style)),
            named: style == .dark ? "dark" : "light", testName: testName, line: line
        )
    }
}
