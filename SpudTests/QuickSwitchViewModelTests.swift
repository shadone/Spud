//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUIKit
import Testing
@testable import Spud

/// `PreferencesService()` has no injectable storage (`@UserDefaultsBacked`
/// hardcodes `.standard`), so every instance here reads/writes the REAL
/// `UserDefaults.standard` domain. `SpudTests` is hosted inside the `Spud`
/// app target (`project.yml`'s `dependencies: - target: Spud`), so that
/// domain is the SAME `info.ddenis.Spud` UserDefaults a later `SpudUITests`
/// launch of the real app reads from (and `ResetFilesystem` does not
/// reliably clear it — see `SignedInVoteUITests`'s discovery that this
/// leaked `showVoteButtons = false` into its first cold launch in a full
/// `make test` run). Every test that mutates a preference restores its
/// documented default via `defer` so this target never leaves stray state
/// for whichever process reads `.standard` next. Also serialized: these tests
/// share that same mutable `.standard` domain, and Swift Testing runs a
/// struct's `@Test` funcs in parallel by default.
@MainActor
@Suite(.serialized)
struct QuickSwitchViewModelTests {
    private func makeViewModel(
        preferences: PreferencesService,
        currentSort: Components.Schemas.SortType = .Hot,
        onSelectSort: @escaping (Components.Schemas.SortType) -> Void = { _ in }
    ) -> QuickSwitchViewModel {
        QuickSwitchViewModel(
            preferencesService: preferences,
            currentSort: currentSort,
            onSelectSort: onSelectSort
        )
    }

    @Test
    func seedsFromPreferences() {
        let prefs = PreferencesService()
        defer {
            prefs.postDensity = .comfortable
            prefs.thumbnailPosition = .left
            prefs.showVoteButtons = true
        }
        prefs.postDensity = .compact
        prefs.thumbnailPosition = .right
        prefs.showVoteButtons = false

        let viewModel = makeViewModel(preferences: prefs, currentSort: .New)

        #expect(viewModel.postDensity == .compact)
        #expect(viewModel.thumbnailPosition == .right)
        #expect(viewModel.showVoteButtons == false)
        #expect(viewModel.currentSort == .New)
    }

    @Test
    func updatePostDensityWritesThrough() {
        let prefs = PreferencesService()
        defer { prefs.postDensity = .comfortable }
        prefs.postDensity = .comfortable
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updatePostDensity(.compact)

        #expect(viewModel.postDensity == .compact)
        #expect(prefs.postDensity == .compact)
    }

    @Test
    func updateThumbnailPositionWritesThrough() {
        let prefs = PreferencesService()
        defer { prefs.thumbnailPosition = .left }
        prefs.thumbnailPosition = .left
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateThumbnailPosition(.hidden)

        #expect(viewModel.thumbnailPosition == .hidden)
        #expect(prefs.thumbnailPosition == .hidden)
    }

    @Test
    func updateShowVoteButtonsWritesThrough() {
        let prefs = PreferencesService()
        defer { prefs.showVoteButtons = true }
        prefs.showVoteButtons = true
        let viewModel = makeViewModel(preferences: prefs)

        viewModel.updateShowVoteButtons(false)

        #expect(viewModel.showVoteButtons == false)
        #expect(prefs.showVoteButtons == false)
    }

    @Test
    func updateShowNsfwWritesThrough() {
        let prefs = PreferencesService()
        defer { prefs.showNsfw = false }
        prefs.showNsfw = false
        let viewModel = makeViewModel(preferences: prefs)
        #expect(viewModel.showNsfw == false)

        viewModel.updateShowNsfw(true)

        #expect(viewModel.showNsfw == true)
        #expect(prefs.showNsfw == true)
    }

    @Test
    func selectSortInvokesCallbackAndUpdatesCurrent() {
        let prefs = PreferencesService()
        var selected: Components.Schemas.SortType?
        let viewModel = makeViewModel(
            preferences: prefs,
            currentSort: .Hot,
            onSelectSort: { selected = $0 }
        )

        viewModel.selectSort(.New)

        #expect(selected == .New)
        #expect(viewModel.currentSort == .New)
    }
}
