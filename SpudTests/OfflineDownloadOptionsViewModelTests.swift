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
/// the `offlineDownloadPostCount` key explicitly before asserting, so the tests
/// are self-contained. Serialized so concurrent tests don't race that shared key.
@MainActor
@Suite(.serialized)
struct OfflineDownloadOptionsViewModelTests {
    private func makeViewModel(
        preferences: PreferencesService,
        onStart: @escaping (Int) -> Void = { _ in }
    ) -> OfflineDownloadOptionsViewModel {
        OfflineDownloadOptionsViewModel(
            preferencesService: preferences,
            onStart: onStart
        )
    }

    @Test
    func seedsFromRememberedPreference() {
        let prefs = PreferencesService()
        prefs.offlineDownloadPostCount = .fiveHundred

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .fiveHundred)
    }

    @Test
    func defaultsToOneHundredWhenUnset() {
        let prefs = PreferencesService()
        prefs.offlineDownloadPostCount = .default

        let viewModel = makeViewModel(preferences: prefs)

        #expect(viewModel.postCount == .oneHundred)
        #expect(viewModel.postCount.count == 100)
    }

    @Test
    func updatePostCountPersistsThrough() {
        let prefs = PreferencesService()
        prefs.offlineDownloadPostCount = .oneHundred
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostCount(.twoHundredFifty)

        // Reflected on the view model AND written through to preferences so the
        // next launch's chooser opens on this choice.
        #expect(viewModel.postCount == .twoHundredFifty)
        #expect(prefs.offlineDownloadPostCount == .twoHundredFifty)
    }

    @Test
    func startHandsBackChosenCount() {
        let prefs = PreferencesService()
        var started: Int?
        let viewModel = makeViewModel(preferences: prefs, onStart: { started = $0 })

        viewModel.updatePostCount(.fiveHundred)
        viewModel.start()

        #expect(started == 500)
    }
}
