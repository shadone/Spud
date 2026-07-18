//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import SpudDataKit
import UIKit
import XCTest
@testable import Spud

/// Snapshots of the "Share as Image" editor screen (``ShareAsImageViewController``):
/// the scaled live preview centered on the dark stage, the control tray, and the
/// output bar.
///
/// The editor does its own manual, transform-based preview layout in
/// `viewDidLayoutSubviews`, so — like `SummaryViewController` — it must be hosted
/// on a real on-screen ``FixedSafeAreaWindow`` and captured with
/// `drawHierarchyInKeyWindow: true`; an off-screen `.image(on:)` render never
/// runs that layout pass and comes out blank. The card's own colors are fixed
/// (theme-independent), so only the surrounding editor chrome follows the
/// capture's light/dark trait.
///
/// Media is injected synchronously via
/// ``ShareAsImageViewController/injectPreviewMediaForTesting(_:)`` (a `#if DEBUG`
/// seam), so the preview renders the loaded-media state with no network/async
/// timing dependency; the absolute timestamp is pinned via the card's
/// `en_US_POSIX`/`GMT` seam plus a fixed `Date` in the fixture.
@MainActor
final class ShareAsImageSnapshotTests: XCTestCase {
    private let snapshotSize = CGSize(width: 390, height: 844)
    private let lemmyTeal = UIColor(red: 0, green: 0x96 / 255, blue: 0x87 / 255, alpha: 1)

    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    func test_editor_post_light() async {
        await assertEditor(appearance: .light, named: "light")
    }

    func test_editor_post_dark() async {
        await assertEditor(appearance: .dark, named: "dark")
    }

    // MARK: - Rendering

    private func assertEditor(
        appearance: ShareCardOptions.Appearance,
        named: String,
        testName: String = #function,
        line: UInt = #line
    ) async {
        let preferencesService = SnapshotPreferences.ephemeral()
        var options = preferencesService.shareAsImageOptions
        options.appearance = appearance
        preferencesService.shareAsImageOptions = options

        let media = solidImage(
            UIColor(red: 0.20, green: 0.45, blue: 0.72, alpha: 1),
            size: CGSize(width: 400, height: 300)
        )
        let viewController = ShareAsImageViewController(
            content: postContent(),
            imageService: SolidColorImageService(image: media),
            preferencesService: preferencesService,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(identifier: "GMT")!
        )

        let style: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        let navigationController = UINavigationController(rootViewController: viewController)
        let window = FixedSafeAreaWindow(frame: CGRect(origin: .zero, size: snapshotSize))
        window.overrideUserInterfaceStyle = style
        window.tintColor = lemmyTeal
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        RunLoop.current.run(until: Date())

        // Inject the media synchronously, then let the card's own loader Task and
        // the layout settle before capture.
        viewController.injectPreviewMediaForTesting(media)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        window.layoutIfNeeded()

        assertSnapshot(
            matching: navigationController,
            as: .image(
                drawHierarchyInKeyWindow: true,
                size: snapshotSize,
                traits: UITraitCollection(userInterfaceStyle: style)
            ),
            named: named,
            file: #file,
            testName: testName,
            line: line
        )
        window.rootViewController = nil
    }

    // MARK: - Fixtures

    private func postContent() -> ShareCardContent {
        let summary = ShareCardContent.PostSummary(
            title: "Understanding Auto Layout from first principles",
            bodyPlain: "A short lead paragraph that introduces the post before the fold.",
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 3402,
            commentCount: 612,
            published: fixedDate,
            permalink: URL(string: "https://lemmy.ml/post/1284920")!,
            mediaUrl: URL(string: "https://lemmy.ml/pictrs/image/abcdef.png")!,
            mediaAspectIsWide: false,
            isNsfw: false
        )
        return ShareCardContent(post: summary, chain: [], kind: .post)
    }

    /// 2026-07-12 16:03 GMT.
    private let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 12
        components.hour = 16
        components.minute = 3
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar.date(from: components)!
    }()

    private func solidImage(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

/// A fake image service that yields a single solid-color image synchronously, so
/// the editor's preview loader resolves deterministically with no network.
private final class SolidColorImageService: ImageServiceType, @unchecked Sendable {
    private let image: UIImage

    init(image: UIImage) {
        self.image = image
    }

    func fetch(_: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        let image = image
        return AsyncStream { continuation in
            continuation.yield(.ready(image))
            continuation.finish()
        }
    }
}
