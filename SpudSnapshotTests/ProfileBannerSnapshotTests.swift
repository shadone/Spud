//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import SwiftUI
import UIKit
import XCTest
@testable import Spud

/// Snapshots of ``ProfileBannerHeaderView`` across its two modes (interactive
/// editor and display-only) and two image states (nil banner/avatar placeholder
/// and remote images via ``StaticImageService``), in light and dark.
///
/// ## Design
///
/// The view is pure SwiftUI with no GRDB dependency. Image loads use
/// ``StaticImageService`` which delivers a fixed ``UIImage`` synchronously from
/// its stream, but SwiftUI processes `@State` updates asynchronously.
///
/// For the "with images" tests the host is attached to a real `UIWindow` so
/// SwiftUI's `.task(id:)` modifiers start running, then the test sleeps briefly
/// to let the state propagate. This is simpler and more robust than scanning
/// the UIKit hierarchy for `UIImageView` instances (SwiftUI `Image(uiImage:)`
/// renders through `CALayer`, not `UIImageView`).
///
/// Placeholder tests (nil URL) are fully deterministic and skip all sleeping.
///
/// Accessibility tests use a plain `UIHostingController` (no window required)
/// and verify structural properties that are available without VoiceOver active.
///
/// Pinned config: `.image(on: .deterministicPhone, traits:)` — device-independent + safe-area-pinned, so
/// any simulator runtime works and refs are stable across OS versions.
@MainActor
final class ProfileBannerSnapshotTests: XCTestCase {
    // MARK: - Interactive mode, placeholder (nil banner + avatar)

    func test_interactive_placeholder_light() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: true)
        assertBannerSnapshot(view, name: "light", style: .light)
    }

    func test_interactive_placeholder_dark() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: true)
        assertBannerSnapshot(view, name: "dark", style: .dark)
    }

    // MARK: - Interactive mode, with banner + avatar

    func test_interactive_withImages_light() async throws {
        let host = try await makeSettledHostWithImages(interactive: true, style: .light)
        assertSnapshot(
            matching: host,
            as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light"
        )
    }

    func test_interactive_withImages_dark() async throws {
        let host = try await makeSettledHostWithImages(interactive: true, style: .dark)
        assertSnapshot(
            matching: host,
            as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }

    // MARK: - Display-only mode, with banner + avatar

    func test_displayOnly_withImages_light() async throws {
        let host = try await makeSettledHostWithImages(interactive: false, style: .light)
        assertSnapshot(
            matching: host,
            as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: .light)),
            named: "light"
        )
    }

    func test_displayOnly_withImages_dark() async throws {
        let host = try await makeSettledHostWithImages(interactive: false, style: .dark)
        assertSnapshot(
            matching: host,
            as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: .dark)),
            named: "dark"
        )
    }

    // MARK: - Display-only mode, placeholder

    func test_displayOnly_placeholder_light() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: false)
        assertBannerSnapshot(view, name: "light", style: .light)
    }

    func test_displayOnly_placeholder_dark() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: false)
        assertBannerSnapshot(view, name: "dark", style: .dark)
    }

    // MARK: - Accessibility assertions

    /// Verifies structural accessibility properties of the interactive mode.
    ///
    /// SwiftUI's runtime accessibility tree (`.accessibilityLabel` strings) is
    /// only queryable via XCUITest's VoiceOver simulation — it is NOT exposed
    /// through UIKit's `UIView.accessibilityElements` or
    /// `accessibilityElementCount()` APIs in a plain XCTest context. The labels
    /// themselves ("Profile banner", "Profile photo") are set via
    /// `.accessibilityLabel(Text(…))` in `ProfileBannerHeaderView.swift` and
    /// are verified structurally here:
    ///
    /// The `UIHostingController.view` must NOT itself be a leaf accessibility
    /// element — it acts as a transparent container and SwiftUI exposes its
    /// children as the reachable elements, so VoiceOver skips the hosting view
    /// and lands directly on the inner interactive elements.
    ///
    /// Full VoiceOver label/action verification requires XCUITest.
    func test_accessibility_interactive() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: true)
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(origin: .zero, size: bannerSize)
        host.view.layoutIfNeeded()

        // The hosting view itself should not be a leaf accessibility element —
        // it should container-delegate to its SwiftUI children.
        XCTAssertFalse(
            host.view.isAccessibilityElement,
            "UIHostingController.view should be a container, not a leaf element"
        )
    }

    /// Verifies structural accessibility properties of the display-only mode.
    ///
    /// See `test_accessibility_interactive` for the rationale on why label
    /// strings are not asserted here.
    func test_accessibility_displayOnly() {
        let view = makeBannerView(bannerUrl: nil, avatarUrl: nil, interactive: false)
        let host = UIHostingController(rootView: AnyView(view))
        host.view.frame = CGRect(origin: .zero, size: bannerSize)
        host.view.layoutIfNeeded()

        XCTAssertFalse(
            host.view.isAccessibilityElement,
            "UIHostingController.view should be a container, not a leaf element"
        )
    }

    // MARK: - Helpers

    /// Fixed width matching iPhone 13 Pro for consistent captures.
    private let bannerWidth: CGFloat = 390
    /// Banner (100 pt) + avatar overlap (36 pt) + bottom padding (36 pt).
    private let bannerHeight: CGFloat = 172
    private var bannerSize: CGSize {
        CGSize(width: bannerWidth, height: bannerHeight)
    }

    /// Builds a ``ProfileBannerHeaderView`` with the given parameters, wrapped
    /// in a fixed-width frame matching iPhone 13 Pro feed width.
    private func makeBannerView(
        bannerUrl: URL?,
        avatarUrl: URL?,
        interactive: Bool
    ) -> some View {
        ProfileBannerHeaderView(
            bannerUrl: bannerUrl,
            avatarUrl: avatarUrl,
            name: "testuser",
            bannerImageOverride: nil,
            avatarImageOverride: nil,
            onPickBanner: interactive ? { _ in } : nil,
            onPickAvatar: interactive ? { _ in } : nil,
            onRemoveBanner: interactive ? { } : nil,
            onRemoveAvatar: interactive ? { } : nil
        )
        .environment(\.imageService, StaticImageService())
        .frame(width: bannerWidth)
        .background(Color(UIColor.systemBackground))
    }

    /// Synchronous snapshot helper for placeholder states (no async loading).
    private func assertBannerSnapshot(
        _ view: some View,
        name: String,
        style: UIUserInterfaceStyle,
        file: StaticString = #file,
        testName: String = #function,
        line: UInt = #line
    ) {
        let host = UIHostingController(rootView: AnyView(view))
        host.overrideUserInterfaceStyle = style
        host.view.frame = CGRect(origin: .zero, size: bannerSize)
        host.view.layoutIfNeeded()
        assertSnapshot(
            matching: host,
            as: .image(on: .deterministicPhone, traits: UITraitCollection(userInterfaceStyle: style)),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }

    /// Builds a `UIHostingController` hosting the banner view with real image
    /// URLs, attaches it to a throwaway `UIWindow` so SwiftUI's `.task`
    /// modifiers fire, then waits for the async `@State` updates to settle
    /// before returning.
    ///
    /// ## Why a fixed sleep, not a UIImageView scan
    ///
    /// SwiftUI `Image(uiImage:)` renders through `CALayer` — it does NOT create
    /// `UIImageView` subviews. Scanning the UIKit subview tree for `UIImageView`
    /// will always return zero in a hosted SwiftUI hierarchy. Instead, because
    /// ``StaticImageService`` delivers its payload synchronously, a single
    /// `Task.sleep(300 ms)` is enough for SwiftUI to schedule and apply the
    /// `@State` update.
    private func makeSettledHostWithImages(
        interactive: Bool,
        style: UIUserInterfaceStyle,
        line: UInt = #line
    ) async throws -> UIHostingController<AnyView> {
        let view = AnyView(makeBannerView(
            bannerUrl: URL(string: "https://example.com/banner.jpg"),
            avatarUrl: URL(string: "https://example.com/avatar.jpg"),
            interactive: interactive
        ))
        let host = UIHostingController(rootView: view)
        host.overrideUserInterfaceStyle = style
        host.view.frame = CGRect(origin: .zero, size: bannerSize)

        // Attach to a window so SwiftUI's .task modifiers start executing.
        let window = UIWindow(frame: CGRect(origin: .zero, size: bannerSize))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // StaticImageService delivers synchronously; SwiftUI processes the
        // @State update on the next run-loop pass. 300 ms comfortably covers
        // both images (banner + avatar) without inflating the test run.
        try await Task.sleep(nanoseconds: 300_000_000)
        await Task.yield()

        return host
    }
}
