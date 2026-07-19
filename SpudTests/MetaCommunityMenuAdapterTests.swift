//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import SpudDataKit
import SpudUtilKit
import Testing
@testable import Spud

/// Minimal `MetaCommunityListItem` test factory.
private extension MetaCommunityListItem {
    static func fixture(
        id: Int64 = 42,
        name: String = "tincidunt",
        title: String? = nil,
        communityActorId: String = "https://lemmy.world/c/tincidunt",
        iconUrl: String? = nil,
        confidence: MetaConfidence = .high,
        subscribedState: CommunitySubscribedState = .notSubscribed,
        isFavorite: Bool = false
    ) -> MetaCommunityListItem {
        MetaCommunityListItem(
            id: id,
            name: name,
            title: title,
            communityActorId: communityActorId,
            iconUrl: iconUrl,
            confidence: confidence,
            subscribedState: subscribedState,
            isFavorite: isFavorite
        )
    }
}

struct MetaCommunityMenuAdapterTests {
    @Test
    func mapsServerCommunityIdFromItemId() {
        let item = MetaCommunityListItem.fixture(id: 42)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.serverCommunityId == Lemmy.CommunityID(42))
    }

    @Test
    func mapsNameVerbatim() {
        let item = MetaCommunityListItem.fixture(name: "tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.name == "tincidunt")
    }

    @Test
    func qualifiedNameIsNameAtActorIdHost() {
        let item = MetaCommunityListItem.fixture(name: "tincidunt", communityActorId: "https://lemmy.world/c/tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.qualifiedName == "tincidunt@lemmy.world")
    }

    @Test
    func instanceIsBuiltFromActorIdHost() {
        let item = MetaCommunityListItem.fixture(communityActorId: "https://lemmy.world/c/tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.instance == InstanceActorId(from: "lemmy.world"))
    }

    @Test
    func instanceCarriesPortWhenActorIdHasOne() {
        let item = MetaCommunityListItem.fixture(communityActorId: "https://lemmy.local:8536/c/tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.instance == InstanceActorId(from: "lemmy.local:8536"))
    }

    @Test
    func iconUrlIsParsedFromItemIconUrlString() {
        let item = MetaCommunityListItem.fixture(iconUrl: "https://lemmy.world/icon.png")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.iconUrl == URL(string: "https://lemmy.world/icon.png"))
    }

    @Test
    func iconUrlIsNilWhenItemIconUrlIsNil() {
        let item = MetaCommunityListItem.fixture(iconUrl: nil)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.iconUrl == nil)
    }

    @Test
    func communityUrlIsItemCommunityActorIdVerbatim() {
        let item = MetaCommunityListItem.fixture(communityActorId: "https://lemmy.world/c/tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.communityUrl == "https://lemmy.world/c/tincidunt")
    }

    /// Meta-community items carry no subscriber count; the menu never renders
    /// `subscribersText`, so the adapter always supplies the empty string
    /// rather than fabricating a number.
    @Test
    func subscribersTextIsAlwaysEmpty() {
        let item = MetaCommunityListItem.fixture()
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.subscribersText == "")
    }

    /// Meta-community items carry no NSFW flag; the menu never reads
    /// `isNsfw`, so the adapter always supplies `false` rather than guessing.
    @Test
    func isNsfwIsAlwaysFalse() {
        let item = MetaCommunityListItem.fixture()
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.isNsfw == false)
    }

    @Test
    func nilWhenActorIdHostIsUnparseable() {
        let item = MetaCommunityListItem.fixture(communityActorId: "not a url")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result == nil)
    }

    @Test
    func nilWhenActorIdHasNoHost() {
        // A relative/host-less "URL" parses but carries no host.
        let item = MetaCommunityListItem.fixture(communityActorId: "/c/tincidunt")
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result == nil)
    }

    // MARK: - followState <-> subscribedState mapping

    @Test
    func followState_subscribedMapsToAccepted() {
        let item = MetaCommunityListItem.fixture(subscribedState: .subscribed)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.followState == .accepted)
    }

    @Test
    func followState_notSubscribedMapsToNotFollowing() {
        let item = MetaCommunityListItem.fixture(subscribedState: .notSubscribed)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.followState == .notFollowing)
    }

    @Test
    func followState_pendingMapsToPending() {
        let item = MetaCommunityListItem.fixture(subscribedState: .pending)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.followState == .pending)
    }

    @Test
    func followState_approvalRequiredMapsToApprovalRequired() {
        let item = MetaCommunityListItem.fixture(subscribedState: .approvalRequired)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.followState == .approvalRequired)
    }

    @Test
    func followState_deniedMapsToDenied() {
        let item = MetaCommunityListItem.fixture(subscribedState: .denied)
        let result = MetaCommunityMenuAdapter.searchResult(for: item)
        #expect(result?.followState == .denied)
    }
}
