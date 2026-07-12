//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import Testing
import UIKit
@testable import Spud

// MARK: - Test doubles

/// Minimal `ImageServiceType` stub — `fetch(_:thumbnail:)` never yields so
/// the factory does not attempt any loading during construction. Protocol
/// default implementations cover all other methods.
private final class NullImageService: ImageServiceType, @unchecked Sendable {
    func fetch(_ url: URL, thumbnail _: URL?) -> AsyncStream<ImageLoadingState> {
        AsyncStream { $0.finish() }
    }
}

@MainActor
private struct ComposerFakeDependencies:
    HasAccountService,
    HasAlertService,
    HasImageService,
    HasPreferencesService
{
    let accountService: AccountServiceType
    let alertService: AlertServiceType
    let imageService: ImageServiceType
    let preferencesService: PreferencesServiceType

    init() {
        let appDatabase = try! AppDatabase.inMemory()
        accountService = AccountService(appDatabase: appDatabase)
        alertService = AlertService()
        imageService = NullImageService()
        preferencesService = PreferencesService()
    }
}

// MARK: - Tests

/// Verifies that the `makeSheet` factory methods on `NewPostViewController`
/// and `ComposerViewController` set `modalPresentationStyle = .pageSheet`
/// before configuring the sheet detents. Without this, the default
/// `.formSheet` on iPad makes `sheetPresentationController` nil and the
/// detents silently never apply.
@MainActor
struct ComposerPresentationTests {
    @Test
    func newPostSheet_isPageSheet_soDetentsApplyOnIPad() throws {
        let deps = ComposerFakeDependencies()
        let nav = NewPostViewController.makeSheet(
            serverCommunityId: nil,
            initialCommunityName: nil,
            accountKeychainId: "kc-test",
            dependencies: deps,
            onQueued: { _ in }
        )
        let navController = try #require(nav as? UINavigationController)
        #expect(navController.modalPresentationStyle == UIModalPresentationStyle.pageSheet)
        #expect(navController.sheetPresentationController != nil)
    }

    @Test
    func composerSheet_isPageSheet_soDetentsApplyOnIPad() throws {
        let deps = ComposerFakeDependencies()
        let nav = ComposerViewController.makeSheet(
            target: .postReply(serverPostId: 1),
            accountKeychainId: "kc-test",
            dependencies: deps
        )
        let navController = try #require(nav as? UINavigationController)
        #expect(navController.modalPresentationStyle == UIModalPresentationStyle.pageSheet)
        #expect(navController.sheetPresentationController != nil)
    }

    @Test
    func editPostSheet_isPageSheet_soDetentsApplyOnIPad() throws {
        let deps = ComposerFakeDependencies()
        let nav = NewPostViewController.makeEditSheet(
            serverPostId: 42,
            serverCommunityId: Lemmy.CommunityID(1),
            communityName: "testcommunity",
            title: "Test post title",
            body: nil,
            url: nil,
            nsfw: false,
            accountKeychainId: "kc-test",
            dependencies: deps
        )
        let navController = try #require(nav as? UINavigationController)
        #expect(navController.modalPresentationStyle == UIModalPresentationStyle.pageSheet)
        #expect(navController.sheetPresentationController != nil)
    }
}
