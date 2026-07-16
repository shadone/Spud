//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import Testing
@testable import Spud

struct FeedStatePresenterTests {
    @Test
    func offlineDescriptor() {
        let d = FeedStatePresenter.descriptor(for: .offline, host: "lemmy.world")
        #expect(d.symbolName == "wifi.slash")
        #expect(d.title == "You're offline")
        #expect(d.primary?.action == .retry)
        #expect(d.secondary == nil)
    }

    @Test
    func offlineDescriptorHidesViewDownloadedWhenNoDownloadedContent() {
        let d = FeedStatePresenter.descriptor(for: .offline, host: "lemmy.world", hasDownloadedContent: false)
        // No downloaded content: no point routing to an empty Downloaded feed.
        #expect(d.secondary == nil)
    }

    @Test
    func offlineDescriptorOffersViewDownloadedWhenDownloadedContentExists() {
        let d = FeedStatePresenter.descriptor(for: .offline, host: "lemmy.world", hasDownloadedContent: true)
        #expect(d.primary?.action == .retry)
        #expect(d.secondary?.action == .viewDownloaded)
        #expect(d.secondary?.title == "View downloaded content")
    }

    @Test
    func unreachableDescriptorInterpolatesHost() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: "lemmy.world")
        #expect(d.symbolName == "globe")
        #expect(d.title == "Couldn't reach lemmy.world")
        #expect(d.primary?.action == .retry)
        #expect(d.secondary?.action == .workOffline)
    }

    @Test
    func unreachableFallsBackWhenHostNil() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: nil)
        #expect(d.title == "Couldn't reach the server")
    }

    @Test
    func malformedDescriptorOffersCopyDetails() {
        let d = FeedStatePresenter.descriptor(for: .malformedResponse, host: "lemmy.world")
        #expect(d.symbolName == "exclamationmark.triangle")
        #expect(d.title == "Something went wrong")
        #expect(d.primary?.action == .retry)
        #expect(d.secondary?.action == .copyDetails)
    }

    @Test
    func notSupportedDescriptorHasNoRetryAffordance() {
        // Non-retriable: retrying can never succeed until the account's home
        // instance/dialect gains the capability, so unlike the other three
        // kinds this one offers neither a primary nor a secondary action.
        let d = FeedStatePresenter.descriptor(for: .notSupported, host: "lemmy.world")
        #expect(d.symbolName == "circle.slash")
        #expect(d.title == "Not available on this instance")
        #expect(d.primary == nil)
        #expect(d.secondary == nil)
    }
}
