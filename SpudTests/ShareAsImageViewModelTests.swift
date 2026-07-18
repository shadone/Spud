//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import Spud

/// Unit coverage for ``ShareAsImageViewModel`` — the editor's testable core:
/// option mutations, alt-text override lifecycle, chain-depth clamping against
/// the actual content, and the persistence path (which must strip the runtime
/// `nsfwRevealed` flag). Each test builds its `PreferencesService` on a fresh
/// private suite (`PreferencesService.ephemeral()`), so nothing leaks into the
/// shared `.standard` domain a later `SpudUITests` launch reads from.
@MainActor
struct ShareAsImageViewModelTests {
    // MARK: - Fixtures

    private func postContent(body: String? = "A short body.") -> ShareCardContent {
        let summary = ShareCardContent.PostSummary(
            title: "A title",
            bodyPlain: body,
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 3402,
            commentCount: 612,
            published: Date(timeIntervalSince1970: 1_752_336_180),
            permalink: URL(string: "https://lemmy.ml/post/1284920")!,
            mediaUrl: nil,
            mediaAspectIsWide: false,
            isNsfw: false
        )
        return ShareCardContent(post: summary, chain: [], kind: .post)
    }

    /// A comment chain with `ancestorCount` ancestors above the shared comment.
    private func commentContent(ancestorCount: Int) -> ShareCardContent {
        var chain: [ShareCardContent.ChainItem] = []
        for index in 0..<ancestorCount {
            chain.append(ShareCardContent.ChainItem(
                authorHandle: "u/ancestor\(index)@lemmy.ml",
                score: Int64(index),
                bodyPlain: "Ancestor \(index)",
                published: Date(timeIntervalSince1970: 1_752_336_000),
                isDestination: false,
                permalink: nil
            ))
        }
        chain.append(ShareCardContent.ChainItem(
            authorHandle: "u/op@lemmy.ml",
            score: 52,
            bodyPlain: "The shared comment.",
            published: Date(timeIntervalSince1970: 1_752_336_180),
            isDestination: true,
            permalink: URL(string: "https://lemmy.ml/comment/998877")!
        ))
        let summary = ShareCardContent.PostSummary(
            title: "Parent post",
            bodyPlain: nil,
            communityName: "Linux",
            communityHandle: "c/linux@lemmy.ml",
            communityIconUrl: nil,
            creatorHandle: "u/torvalds@lemmy.ml",
            score: 10,
            commentCount: 5,
            published: Date(timeIntervalSince1970: 1_752_330_000),
            permalink: URL(string: "https://lemmy.ml/comment/998877")!,
            mediaUrl: nil,
            mediaAspectIsWide: false,
            isNsfw: false
        )
        return ShareCardContent(post: summary, chain: chain, kind: .comment)
    }

    private func makeViewModel(
        content: ShareCardContent,
        configure: (PreferencesService) -> Void = { _ in }
    ) -> ShareAsImageViewModel {
        let prefs = PreferencesService.ephemeral()
        configure(prefs)
        return ShareAsImageViewModel(content: content, preferencesService: prefs)
    }

    // MARK: - Body treatment cycling

    @Test
    func cycleBodyTreatment_advancesFullTruncateTitleOnly() {
        let viewModel = makeViewModel(content: postContent()) { prefs in
            var options = prefs.shareAsImageOptions
            options.bodyTreatment = .full
            prefs.shareAsImageOptions = options
        }
        #expect(viewModel.options.bodyTreatment == .full)

        viewModel.cycleBodyTreatment()
        #expect(viewModel.options.bodyTreatment == .truncate)

        viewModel.cycleBodyTreatment()
        #expect(viewModel.options.bodyTreatment == .titleOnly)

        viewModel.cycleBodyTreatment()
        #expect(viewModel.options.bodyTreatment == .full)
    }

    // MARK: - Toggles

    @Test
    func toggles_flipTheirFlags() {
        let viewModel = makeViewModel(content: postContent())

        let redacted = viewModel.options.redactIdentities
        viewModel.toggleRedactIdentities()
        #expect(viewModel.options.redactIdentities == !redacted)

        let community = viewModel.options.showCommunityAndCreator
        viewModel.toggleCommunityAndCreator()
        #expect(viewModel.options.showCommunityAndCreator == !community)

        let stats = viewModel.options.showStats
        viewModel.toggleStats()
        #expect(viewModel.options.showStats == !stats)

        let media = viewModel.options.showMedia
        viewModel.toggleMedia()
        #expect(viewModel.options.showMedia == !media)

        let via = viewModel.options.showViaSpudMark
        viewModel.toggleViaSpudMark()
        #expect(viewModel.options.showViaSpudMark == !via)
    }

    // MARK: - NSFW reveal is runtime-only

    @Test
    func nsfwReveal_isRuntimeOnly_neverPersisted() {
        let prefs = PreferencesService.ephemeral()
        let viewModel = ShareAsImageViewModel(content: postContent(), preferencesService: prefs)

        viewModel.toggleNsfwRevealed()
        // The runtime option holds the reveal so the live preview updates,
        #expect(viewModel.options.nsfwRevealed == true)

        // but persisting it strips the flag (the codec never encodes it), so the
        // next editor open — even for the same post — starts spoilered again.
        viewModel.persist()
        #expect(prefs.shareAsImageOptions.nsfwRevealed == false)
    }

    // MARK: - Chain-depth clamping

    @Test
    func chainDepth_clampsToAvailableAncestorsAtInit() {
        // 2 ancestors available, but the saved options ask for 8.
        let viewModel = makeViewModel(content: commentContent(ancestorCount: 2)) { prefs in
            var options = prefs.shareAsImageOptions
            options.chainDepth = 8
            prefs.shareAsImageOptions = options
        }
        #expect(viewModel.maxChainDepth == 2)
        #expect(viewModel.options.chainDepth == 2)
    }

    @Test
    func chainDepth_incrementDecrement_stayWithinBounds() {
        let viewModel = makeViewModel(content: commentContent(ancestorCount: 3))
        #expect(viewModel.maxChainDepth == 3)

        // Drive it above the ceiling.
        for _ in 0..<10 {
            viewModel.incrementChainDepth()
        }
        #expect(viewModel.options.chainDepth == 3)

        // Drive it below the floor.
        for _ in 0..<10 {
            viewModel.decrementChainDepth()
        }
        #expect(viewModel.options.chainDepth == 0)
    }

    @Test
    func chainDepth_isZeroForAPostCard() {
        let viewModel = makeViewModel(content: postContent()) { prefs in
            var options = prefs.shareAsImageOptions
            options.chainDepth = 5
            prefs.shareAsImageOptions = options
        }
        #expect(viewModel.maxChainDepth == 0)
        #expect(viewModel.options.chainDepth == 0)
        #expect(viewModel.isComment == false)
    }

    // MARK: - Alt text override

    @Test
    func altText_defaultsToAutoAndTracksOptions() {
        let content = postContent()
        let viewModel = makeViewModel(content: content)
        #expect(viewModel.isAltTextAuto == true)
        #expect(viewModel.currentAltText == ShareCardAltText.make(content: content, options: viewModel.options))
    }

    @Test
    func altText_overrideRetainedAcrossOptionChanges() {
        let viewModel = makeViewModel(content: postContent())
        viewModel.setAltTextOverride("A hand-written description.")
        #expect(viewModel.isAltTextAuto == false)
        #expect(viewModel.currentAltText == "A hand-written description.")

        // Changing options must NOT clobber the user's override.
        viewModel.cycleBodyTreatment()
        viewModel.toggleStats()
        #expect(viewModel.currentAltText == "A hand-written description.")
        #expect(viewModel.isAltTextAuto == false)
    }

    @Test
    func altText_resetRestoresAuto() {
        let content = postContent()
        let viewModel = makeViewModel(content: content)
        viewModel.setAltTextOverride("Custom.")
        viewModel.resetAltTextToAuto()
        #expect(viewModel.isAltTextAuto == true)
        #expect(viewModel.currentAltText == ShareCardAltText.make(content: content, options: viewModel.options))
    }

    @Test
    func altText_blankOverrideFallsBackToAuto() {
        let viewModel = makeViewModel(content: postContent())
        viewModel.setAltTextOverride("   \n ")
        #expect(viewModel.isAltTextAuto == true)
    }

    // MARK: - Persistence (each output action calls persist())

    @Test
    func persist_writesCurrentOptionsBackToPreferences() {
        let prefs = PreferencesService.ephemeral()
        let viewModel = ShareAsImageViewModel(content: postContent(), preferencesService: prefs)

        viewModel.setAppearance(.dark)
        viewModel.setCanvas(.square)
        viewModel.toggleStats()
        viewModel.persist()

        let saved = prefs.shareAsImageOptions
        #expect(saved.appearance == .dark)
        #expect(saved.canvas == .square)
        #expect(saved.showStats == viewModel.options.showStats)
    }
}
