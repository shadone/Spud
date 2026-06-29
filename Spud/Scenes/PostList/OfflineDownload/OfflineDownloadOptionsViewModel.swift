//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUIKit

/// Backs ``OfflineDownloadOptionsView`` — the small chooser shown before an
/// offline download starts, letting the user pick how many posts to save.
///
/// The selection is seeded from (and persisted back to) ``PreferencesService``
/// so the chooser remembers the user's last choice across launches; writes go
/// straight through on each change (the chooser is short-lived and the only
/// writer while open, like ``QuickSwitchViewModel``).
///
/// Deliberately structured as an `@Observable` options view model over a small
/// set of bindable choices so a later slice can add a further option (e.g. a
/// "Also save linked web pages" toggle) by adding one stored property + its
/// `update…` method — no restructuring.
@MainActor
@Observable
final class OfflineDownloadOptionsViewModel {
    private let preferencesService: PreferencesServiceType

    /// Invoked when the user taps Download. Carries the chosen post count so the
    /// hosting controller can start the download with it.
    private let onStart: (_ maxPosts: Int) -> Void

    /// All selectable post-count presets, for the picker.
    let allPostCounts: [Preferences.OfflineDownloadPostCount] = Preferences.OfflineDownloadPostCount.allCases

    /// The currently selected post-count preset. Seeded from the remembered
    /// preference; updated via ``updatePostCount(_:)`` (which also persists it).
    var postCount: Preferences.OfflineDownloadPostCount

    init(
        preferencesService: PreferencesServiceType,
        onStart: @escaping (_ maxPosts: Int) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onStart = onStart
        postCount = preferencesService.offlineDownloadPostCount
    }

    /// Updates the selected preset and persists it so the next launch's chooser
    /// opens on this choice.
    func updatePostCount(_ value: Preferences.OfflineDownloadPostCount) {
        postCount = value
        preferencesService.offlineDownloadPostCount = value
        Haptics.tap()
    }

    /// Confirms the chooser: hands the chosen post count back to the controller,
    /// which dismisses the chooser and starts the progress flow.
    func start() {
        Haptics.tap()
        onStart(postCount.count)
    }
}
