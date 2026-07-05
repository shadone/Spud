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
/// Each test builds its `PreferencesService` on a fresh, private `UserDefaults`
/// suite (`PreferencesService.ephemeral()`) and seeds the
/// `offlineDownloadPostCount` / `offlineDownloadArchiveLinks` keys explicitly,
/// so the tests are self-contained and never touch the shared `.standard`
/// (`info.ddenis.Spud`) domain a later `SpudUITests` launch reads from. That
/// isolation removes the need for the old `.serialized` + `defer`-restore
/// workaround: nothing is shared, so parallel `@Test` funcs can't race.
@MainActor
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
        let prefs = PreferencesService.ephemeral()
        prefs.offlineDownloadPostCount = .fiveHundred

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .fiveHundred)
    }

    @Test
    func defaultsToOneHundredWhenUnset() {
        let prefs = PreferencesService.ephemeral()
        prefs.offlineDownloadPostCount = .default

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .oneHundred)
        #expect(viewModel.postCount.count == 100)
    }

    @Test
    func updatePostCountPersistsThrough() {
        let prefs = PreferencesService.ephemeral()
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
        let prefs = PreferencesService.ephemeral()
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
        let prefs = PreferencesService.ephemeral()
        prefs.offlineDownloadArchiveLinks = true

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.archiveLinks == true)
    }

    @Test
    func archiveLinksDefaultsOff() {
        let prefs = PreferencesService.ephemeral()
        prefs.offlineDownloadArchiveLinks = false

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.archiveLinks == false)
    }

    @Test
    func updateArchiveLinksPersistsThrough() {
        let prefs = PreferencesService.ephemeral()
        prefs.offlineDownloadArchiveLinks = false
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateArchiveLinks(true)

        // Reflected on the view model AND written through to preferences so the
        // next launch's chooser opens on this choice.
        #expect(viewModel.archiveLinks == true)
        #expect(prefs.offlineDownloadArchiveLinks == true)
    }
}
