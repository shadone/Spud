// SpudTests/SpudUserActivityTests.swift
import CoreSpotlight
import Foundation
import Testing
@testable import Spud

struct SpudUserActivityTests {
    private let postURL = URL(string: "info.ddenis.spud://internal/resolve?url=https://lemmy.world/post/5")!

    @Test
    func viewPost_setsTypeURLAndEligibility() throws {
        let activity = try #require(SpudUserActivity.viewPost(routingURL: postURL, title: "Hello", isNsfw: false))
        #expect(activity.activityType == SpudUserActivity.viewPostType)
        #expect(activity.userInfo?["url"] as? String == postURL.absoluteString)
        #expect(activity.persistentIdentifier == postURL.absoluteString)
        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch)
        #expect(activity.isEligibleForPrediction)
    }

    @Test
    func viewPost_returnsNilForNsfw() {
        #expect(SpudUserActivity.viewPost(routingURL: postURL, title: "Hello", isNsfw: true) == nil)
    }

    @Test
    func routingURL_decodesOwnActivity() throws {
        let activity = try #require(SpudUserActivity.viewPost(routingURL: postURL, title: "Hello", isNsfw: false))
        #expect(SpudUserActivity.routingURL(from: activity) == postURL)
    }

    @Test
    func routingURL_decodesSpotlightItemTap() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: postURL.absoluteString]
        #expect(SpudUserActivity.routingURL(from: activity) == postURL)
    }

    @Test
    func routingURL_returnsNilForUnknownActivity() {
        let activity = NSUserActivity(activityType: "com.example.other")
        #expect(SpudUserActivity.routingURL(from: activity) == nil)
    }
}
