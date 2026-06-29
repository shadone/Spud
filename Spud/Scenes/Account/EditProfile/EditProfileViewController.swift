//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUIKit
import SwiftUI
import UIKit

/// Hosts the SwiftUI ``EditProfileView`` for the signed-in account. Built as a
/// `UIHostingController` wrapped in a `UINavigationController` for modal
/// presentation, mirroring how the app presents its other SwiftUI editors. Save
/// / Cancel are rendered by the SwiftUI toolbar; both dismiss through the
/// callbacks wired here.
enum EditProfileViewController {
    typealias Dependencies =
        HasAccountService &
        HasAppDatabase &
        HasImageService

    /// Builds the modal editor for the account behind `accountKeychainId`,
    /// resolving the account scope and injecting the image service so the avatar
    /// renders its real image. The returned controller is a
    /// `UINavigationController` ready to `present(...)`.
    @MainActor
    static func makeModal(
        accountKeychainId: String,
        dependencies: Dependencies
    ) -> UIViewController {
        let accountScope = dependencies.accountService.scope(forAccountKeychainId: accountKeychainId)

        // Forward-declared so the view model's `onSaved` and the view's
        // `onCancel` can reach the hosting controller to dismiss it.
        weak var hostRef: UIViewController?

        let viewModel = EditProfileViewModel(
            accountScope: accountScope,
            appDatabase: dependencies.appDatabase,
            accountService: dependencies.accountService,
            onSaved: {
                hostRef?.presentingViewController?.dismiss(animated: true)
            }
        )

        let accent = Color(ThemeManager.currentAccentColor)
        let rootView = EditProfileView(
            viewModel: viewModel,
            accent: accent,
            onCancel: {
                hostRef?.presentingViewController?.dismiss(animated: true)
            }
        )
        .environment(\.imageService, dependencies.imageService)

        let hosting = UIHostingController(rootView: rootView)
        let navigationController = UINavigationController(rootViewController: hosting)
        hostRef = navigationController
        return navigationController
    }
}
