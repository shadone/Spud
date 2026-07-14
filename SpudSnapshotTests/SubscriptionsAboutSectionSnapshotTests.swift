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

/// Screen snapshot of the Communities tab's always-visible "About <instance>"
/// section, light and dark: a high-confidence meta community row rendered
/// directly, plus a low-confidence one folded under a "More on this instance"
/// disclosure, with Favourite (always) and Subscribe (signed-in) controls.
///
/// `SubscriptionsViewModel.metaCommunities` / `metaInstanceName` are plain
/// `@Observable var`s populated live from `AppDatabase.observeMetaCommunities`
/// in production, but the view model also accepts a direct assignment — this
/// test constructs a view model with `accountRowId: nil` (so no observation or
/// resolver task starts; see the `guard let accountRowId else { return }` at
/// the top of the initializer) and assigns fixed `MetaCommunityListItem`s
/// straight onto the property, so the render is a pure function of that state
/// with no async GRDB observation to race against.
///
/// `.image(size:traits:)` is device- and runtime-sensitive; record on the
/// reference iPhone 17 Pro, iOS 26.3.
@MainActor
final class SubscriptionsAboutSectionSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SnapshotDeterminism.pinAccent()
        SnapshotDeterminism.pinStatusBarHidden()
    }

    private func makeViewModel(appDatabase: AppDatabase, isSignedIn: Bool) -> SubscriptionsViewModel {
        SubscriptionsViewModel(
            accountRowId: nil,
            isSignedIn: isSignedIn,
            appDatabase: appDatabase,
            accountScope: nil,
            metaCommunityService: nil,
            onFeedRequested: { _ in },
            onExploreRequested: { }
        )
    }

    /// A mix of one high-confidence (rendered directly, subscribed) and one
    /// low-confidence (folded under the disclosure, not subscribed, not
    /// favourited) meta community — enough to exercise every visual state the
    /// row supports in a single render.
    private func makeFixedMetaCommunities() -> [MetaCommunityListItem] {
        [
            MetaCommunityListItem(
                id: 1,
                name: "announcements",
                title: "Announcements",
                communityActorId: "https://lemmy.world/c/announcements",
                iconUrl: nil,
                confidence: .high,
                subscribedState: .subscribed,
                isFavorite: true
            ),
            MetaCommunityListItem(
                id: 2,
                name: "offtopic",
                title: nil,
                communityActorId: "https://lemmy.world/c/offtopic",
                iconUrl: nil,
                confidence: .low,
                subscribedState: .notSubscribed,
                isFavorite: false
            ),
        ]
    }

    /// Signed-in: both the Favourite star and the centralized Subscribe button
    /// render for every row.
    func test_aboutSection_signedIn() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let appDatabase = try AppDatabase.inMemory()
            let viewModel = makeViewModel(appDatabase: appDatabase, isSignedIn: true)
            viewModel.metaInstanceName = "lemmy.world"
            viewModel.metaCommunities = makeFixedMetaCommunities()

            let view = SubscriptionsView(viewModel: viewModel)
            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 700)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: style == .dark ? "dark" : "light"
            )
        }
    }

    /// Signed-out: the section still renders (favourite + browsing are useful
    /// without an account), but the Subscribe button is gone from every row —
    /// an anonymous account has no server-side subscribe state to mutate.
    func test_aboutSection_signedOut_hidesSubscribe() throws {
        let appDatabase = try AppDatabase.inMemory()
        let viewModel = makeViewModel(appDatabase: appDatabase, isSignedIn: false)
        viewModel.metaInstanceName = "lemmy.world"
        viewModel.metaCommunities = makeFixedMetaCommunities()

        let view = SubscriptionsView(viewModel: viewModel)
        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 390, height: 700)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.layoutIfNeeded()

        assertSnapshot(
            matching: host,
            as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                UITraitCollection(userInterfaceStyle: .light),
                SnapshotDeterminism.contentSizeTrait,
            ])),
            named: "light"
        )
    }

    /// `MetaCommunityAboutRow` in isolation for both subscribe-state pill
    /// variants (the not-subscribed "+ Subscribe" case only ever appears
    /// inside the collapsed "More on this instance" disclosure in the two
    /// tests above, so it's never actually visible in those recorded PNGs) —
    /// confirms both the accent "Subscribe" pill and the muted "Subscribed"
    /// pill render cleanly side by side, independent of the disclosure's
    /// expanded/collapsed state.
    func test_row_bothSubscribeStates() {
        let items = makeFixedMetaCommunities()

        for style in [UIUserInterfaceStyle.light, .dark] {
            let view = VStack(spacing: 0) {
                ForEach(items) { item in
                    MetaCommunityAboutRow(
                        item: item, showsSubscribe: true,
                        onSubscribe: { }, onFavorite: { }
                    )
                    .padding()
                }
            }
            let host = UIHostingController(rootView: view)
            let size = CGSize(width: 390, height: 220)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()

            assertSnapshot(
                matching: host,
                as: .image(size: size, traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: style),
                    SnapshotDeterminism.contentSizeTrait,
                ])),
                named: style == .dark ? "dark" : "light"
            )
        }
    }
}
