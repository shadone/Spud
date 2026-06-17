// SpudTests/SpudUserActivityTests.swift
import CoreSpotlight
import XCTest
@testable import Spud

final class SpudUserActivityTests: XCTestCase {
    private let postURL = URL(string: "info.ddenis.spud://internal/resolve?url=https://lemmy.world/post/5")!

    func test_viewPost_setsTypeURLAndEligibility() {
        let activity = SpudUserActivity.viewPost(routingURL: postURL, title: "Hello")
        XCTAssertEqual(activity.activityType, SpudUserActivity.viewPostType)
        XCTAssertEqual(activity.userInfo?["url"] as? String, postURL.absoluteString)
        XCTAssertEqual(activity.persistentIdentifier, postURL.absoluteString)
        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertTrue(activity.isEligibleForSearch)
        XCTAssertTrue(activity.isEligibleForPrediction)
    }

    func test_routingURL_decodesOwnActivity() {
        let activity = SpudUserActivity.viewPost(routingURL: postURL, title: "Hello")
        XCTAssertEqual(SpudUserActivity.routingURL(from: activity), postURL)
    }

    func test_routingURL_decodesSpotlightItemTap() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: postURL.absoluteString]
        XCTAssertEqual(SpudUserActivity.routingURL(from: activity), postURL)
    }

    func test_routingURL_returnsNilForUnknownActivity() {
        let activity = NSUserActivity(activityType: "com.example.other")
        XCTAssertNil(SpudUserActivity.routingURL(from: activity))
    }
}
