//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Testing
@testable import Spud

/// Tests for ``OfflineDownloadOptionsViewModel`` — the chooser that lets the
/// user pick how many posts an offline download saves.
///
/// `PreferencesService` is backed by the shared `UserDefaults`; each test seeds
/// the `offlineDownloadPostCount` / `offlineDownloadArchiveLinks` keys explicitly
/// before asserting, so the tests are self-contained. Serialized so concurrent
/// tests don't race those shared keys. Each mutating test also `defer`-restores
/// its key to the documented default: `PreferencesService()` has no injectable
/// storage, so this target (hosted inside the `Spud` app target per
/// `project.yml`) writes the REAL `info.ddenis.Spud` `UserDefaults.standard`
/// domain — the same one a later `SpudUITests` launch reads from, and
/// `ResetFilesystem` does not reliably clear it (see `QuickSwitchViewModelTests`'s
/// doc comment for the concrete UI-test failure this caused elsewhere).
@MainActor
@Suite(.serialized)
struct OfflineDownloadOptionsViewModelTests {
    private func makeViewModel(
        preferences: PreferencesService,
        onStart: @escaping (Int, Bool) -> Void = { _, _ in }
    ) -> OfflineDownloadOptionsViewModel {
        OfflineDownloadOptionsViewModel(
            preferencesService: preferences,
            onStart: onStart
        )
    }

    @Test
    func seedsFromRememberedPreference() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadPostCount = .default }
        prefs.offlineDownloadPostCount = .fiveHundred

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .fiveHundred)
    }

    @Test
    func defaultsToOneHundredWhenUnset() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadPostCount = .default }
        prefs.offlineDownloadPostCount = .default

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .oneHundred)
        #expect(viewModel.postCount.count == 100)
    }

    @Test
    func updatePostCountPersistsThrough() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadPostCount = .default }
        prefs.offlineDownloadPostCount = .oneHundred
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostCount(.twoHundredFifty)

        // Reflected on the view model AND written through to preferences so the
        // next launch's chooser opens on this choice.
        #expect(viewModel.postCount == .twoHundredFifty)
        #expect(prefs.offlineDownloadPostCount == .twoHundredFifty)
    }

    @Test
    func startHandsBackChosenCountAndArchiveFlag() {
        let prefs = PreferencesService()
        defer {
            prefs.offlineDownloadPostCount = .default
            prefs.offlineDownloadArchiveLinks = false
        }
        var startedCount: Int?
        var startedArchive: Bool?
        let viewModel = makeViewModel(preferences: prefs, onStart: { count, archive in
            startedCount = count
            startedArchive = archive
        })

        viewModel.updatePostCount(.fiveHundred)
        viewModel.updateArchiveLinks(true)
        viewModel.start()

        #expect(startedCount == 500)
        #expect(startedArchive == true)
    }

    @Test
    func seedsArchiveLinksFromRememberedPreference() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadArchiveLinks = false }
        prefs.offlineDownloadArchiveLinks = true

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.archiveLinks == true)
    }

    @Test
    func archiveLinksDefaultsOff() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadArchiveLinks = false }
        prefs.offlineDownloadArchiveLinks = false

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.archiveLinks == false)
    }

    @Test
    func updateArchiveLinksPersistsThrough() {
        let prefs = PreferencesService()
        defer { prefs.offlineDownloadArchiveLinks = false }
        prefs.offlineDownloadArchiveLinks = false
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateArchiveLinks(true)

        // Reflected on the view model AND written through to preferences so the
        // next launch's chooser opens on this choice.
        #expect(viewModel.archiveLinks == true)
        #expect(prefs.offlineDownloadArchiveLinks == true)
    }
}
