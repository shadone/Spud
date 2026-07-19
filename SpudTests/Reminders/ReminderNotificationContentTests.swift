//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import SpudUtilKit
import Testing

/// Covers `ReminderNotificationFactory.timeReminderContent` - the only pure,
/// unit-testable slice of the notification layer (spec Task 4). The
/// `UNUserNotificationCenter`-backed scheduler and the `AppDelegate`
/// notification-tap delegate are exercised on-device instead.
struct ReminderNotificationContentTests {
    @Test
    func titleIsTheSnapshot() {
        let content = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: "A great post about cats",
            communityName: "cats",
            instanceHost: "lemmy.world",
            apId: "https://lemmy.world/post/123"
        )
        #expect(content.title == "A great post about cats")
    }

    @Test
    func bodyContainsTheQualifiedCommunityHandle() {
        let content = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: "A great post about cats",
            communityName: "news",
            instanceHost: "example.com",
            apId: "https://example.com/post/456"
        )
        #expect(content.body.contains("c/news@example.com"))
    }

    @Test
    func routingURLStringMatchesTheObjectAtURLDeepLink() throws {
        let apId = "https://lemmy.world/post/789"
        let content = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: "Some title",
            communityName: "world",
            instanceHost: "lemmy.world",
            apId: apId
        )
        let expected = try URL.SpudInternalLink.objectAtURL(url: #require(URL(string: apId))).url.absoluteString
        #expect(content.routingURLString == expected)
    }

    @Test
    func malformedApIdDegradesRatherThanCrashing() {
        // apId is denormalized from a resolved post's own canonical URL at
        // reminder-set time, so this should never happen in practice - but the
        // factory must degrade gracefully (empty routing URL, title/body still
        // populated) rather than force-unwrap and crash.
        let content = ReminderNotificationFactory.timeReminderContent(
            titleSnapshot: "Some title",
            communityName: "world",
            instanceHost: "lemmy.world",
            apId: ""
        )
        #expect(content.routingURLString == "")
        #expect(content.title == "Some title")
    }

    // MARK: - communityFollowContent

    @Test
    func communityFollowSingularBody() {
        let content = ReminderNotificationFactory.communityFollowContent(
            title: "News",
            communityName: "news",
            instanceHost: "example.com",
            newCount: 1,
            isSaturated: false
        )
        #expect(content.title == "News")
        #expect(content.body == "1 new post · c/news@example.com")
    }

    @Test
    func communityFollowPluralBody() {
        let content = ReminderNotificationFactory.communityFollowContent(
            title: "News",
            communityName: "news",
            instanceHost: "example.com",
            newCount: 4,
            isSaturated: false
        )
        #expect(content.body == "4 new posts · c/news@example.com")
    }

    @Test
    func communityFollowSaturatedBody() {
        let content = ReminderNotificationFactory.communityFollowContent(
            title: "News",
            communityName: "news",
            instanceHost: "example.com",
            newCount: 10,
            isSaturated: true
        )
        #expect(content.body == "10+ new posts · c/news@example.com")
    }

    @Test
    func communityFollowRoutingURLPointsAtTheCommunityDeepLink() throws {
        let content = ReminderNotificationFactory.communityFollowContent(
            title: "News",
            communityName: "news",
            instanceHost: "example.com",
            newCount: 2,
            isSaturated: false
        )
        let instance = try #require(InstanceActorId(from: "https://example.com"))
        let expected = URL.SpudInternalLink.community(name: "news", instance: instance).url

        let routingURL = try #require(URL(string: content.routingURLString))
        // Assert prefix/host+path, not the whole string - the query
        // parameter order is an implementation detail.
        #expect(routingURL.scheme == expected.scheme)
        #expect(routingURL.host == expected.host)
        #expect(routingURL.path == expected.path)
    }

    @Test
    func communityFollowMalformedInstanceHostDegradesRatherThanCrashing() {
        // instanceHost is denormalized from a resolved community's own
        // instance at follow-set time, so this should never happen in
        // practice - but the factory must degrade gracefully rather than
        // force-unwrap and crash.
        let content = ReminderNotificationFactory.communityFollowContent(
            title: "News",
            communityName: "news",
            instanceHost: "",
            newCount: 1,
            isSaturated: false
        )
        #expect(content.routingURLString == "")
        #expect(content.title == "News")
    }
}
