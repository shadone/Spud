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
/// so the chooser remembers the user's last choices across launches; writes go
/// straight through on each change (the chooser is short-lived and the only
/// writer while open, like ``QuickSwitchViewModel``).
///
/// Two choices: how many posts to save (a preset picker) and whether to also
/// capture a web archive of each external-link post's page ("Also save linked
/// web pages", default off — heavier/slower).
@MainActor
@Observable
final class OfflineDownloadOptionsViewModel {
    private let preferencesService: PreferencesServiceType

    /// Invoked when the user taps Download. Carries the chosen post count and
    /// whether to archive linked pages so the hosting controller can start the
    /// download with them.
    private let onStart: (_ maxPosts: Int, _ archiveLinks: Bool) -> Void

    /// All selectable post-count presets, for the picker.
    let allPostCounts: [Preferences.OfflineDownloadPostCount] = Preferences.OfflineDownloadPostCount.allCases

    /// The currently selected post-count preset. Seeded from the remembered
    /// preference; updated via ``updatePostCount(_:)`` (which also persists it).
    var postCount: Preferences.OfflineDownloadPostCount

    /// Whether to also capture a web archive of each external-link post's page.
    /// Seeded from the remembered preference; updated via
    /// ``updateArchiveLinks(_:)`` (which also persists it).
    var archiveLinks: Bool

    init(
        preferencesService: PreferencesServiceType,
        onStart: @escaping (_ maxPosts: Int, _ archiveLinks: Bool) -> Void
    ) {
        self.preferencesService = preferencesService
        self.onStart = onStart
        postCount = preferencesService.offlineDownloadPostCount
        archiveLinks = preferencesService.offlineDownloadArchiveLinks
    }

    /// Updates the selected preset and persists it so the next launch's chooser
    /// opens on this choice.
    func updatePostCount(_ value: Preferences.OfflineDownloadPostCount) {
        postCount = value
        preferencesService.offlineDownloadPostCount = value
        Haptics.tap()
    }

    /// Updates the "save linked web pages" toggle and persists it so the next
    /// launch's chooser opens on this choice.
    func updateArchiveLinks(_ value: Bool) {
        archiveLinks = value
        preferencesService.offlineDownloadArchiveLinks = value
        Haptics.tap()
    }

    /// Confirms the chooser: hands the chosen post count + archive option back to
    /// the controller, which dismisses the chooser and starts the progress flow.
    func start() {
        Haptics.tap()
        onStart(postCount.count, archiveLinks)
    }
}
