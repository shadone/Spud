//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog
import SpudUtilKit
import UserNotifications

private let logger = Logger.reminders

/// The notification content + deep-link built for a fired reminder. A pure
/// value produced by `ReminderNotificationFactory` - carries everything
/// `ReminderNotificationScheduling.schedule` needs to build a
/// `UNMutableNotificationContent`, with no dependency on `UserNotifications`
/// itself, so the builder is unit-testable without a simulator/device.
public struct ReminderNotificationContent: Sendable, Equatable {
    /// The notification's title - the post's `titleSnapshot`.
    public let title: String
    /// The notification's body, e.g. "c/news@example.com · Tap to revisit".
    public let body: String
    /// The `URL.SpudInternalLink.objectAtURL` deep-link, as a string (for
    /// `UNNotificationContent.userInfo`, which is not typed). The
    /// notification-tap delegate (`AppDelegate`) reads this back out under
    /// ``userInfoRoutingURLKey`` and routes it through `AppCoordinator.open`,
    /// the same funnel every other system entry point uses.
    public let routingURLString: String

    public init(title: String, body: String, routingURLString: String) {
        self.title = title
        self.body = body
        self.routingURLString = routingURLString
    }
}

public extension ReminderNotificationContent {
    /// The `UNMutableNotificationContent.userInfo` key `routingURLString` is
    /// stored under. Single source of truth shared by
    /// `UNReminderNotificationScheduler.schedule` (writer, SpudDataKit) and
    /// `AppDelegate`'s notification-tap delegate (reader, the app target) so
    /// the two sides can never drift apart.
    static let userInfoRoutingURLKey = "spudRoutingURL"
}

/// Builds the pure notification content + deep-link for a fired reminder. No
/// `UserNotifications` dependency - this is the only piece of the notification
/// layer covered by a unit test (`ReminderNotificationContentTests`); the
/// `UN*` glue is exercised on-device instead.
public enum ReminderNotificationFactory {
    /// Builds the content for a fired time reminder (Phase 1's only kind).
    ///
    /// - Parameters:
    ///   - titleSnapshot: the post's title, denormalized onto the reminder
    ///     record at set-time (`ReminderRecord.titleSnapshot`).
    ///   - communityName: the post's community, bare name (no `!`/`@`).
    ///   - instanceHost: the community's home instance host.
    ///   - apId: the post's canonical ActivityPub URL
    ///     (`ReminderRecord.apId`), turned into a
    ///     `URL.SpudInternalLink.objectAtURL` deep-link that resolves via
    ///     `resolve_object` at tap time - so the tap still works even if the
    ///     local post cache row has since been evicted.
    public static func timeReminderContent(
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        apId: String
    ) -> ReminderNotificationContent {
        let body = String(
            format: NSLocalizedString(
                "c/%1$@@%2$@ · Tap to revisit",
                comment: "Fired reminder notification body; %1$@ is the community name, %2$@ is its instance host"
            ),
            communityName,
            instanceHost
        )

        guard let apURL = URL(string: apId) else {
            // Should never happen in practice - apId is denormalized from a
            // resolved post's own canonical URL at reminder-set time. Degrade to
            // a notification with no working deep link rather than crashing on
            // a malformed stored URL.
            logger.error("timeReminderContent: apId is not a valid URL: \(apId, privacy: .public)")
            return ReminderNotificationContent(title: titleSnapshot, body: body, routingURLString: "")
        }

        let routingURL = URL.SpudInternalLink.objectAtURL(url: apURL).url
        return ReminderNotificationContent(title: titleSnapshot, body: body, routingURLString: routingURL.absoluteString)
    }

    /// Builds the content for a fired activity reminder (Phase 2's "notify me
    /// as the discussion grows", generalized in Phase 3 to a comment
    /// subtree's "new replies" follow), posted ad-hoc by the foreground poll
    /// (`ReminderService.pollDueActivityReminders`) rather than scheduled
    /// up-front.
    ///
    /// - Parameters:
    ///   - titleSnapshot: the post's title, denormalized onto the reminder
    ///     record at set-time (`ReminderRecord.titleSnapshot`).
    ///   - communityName: the post's community, bare name (no `!`/`@`).
    ///   - instanceHost: the community's home instance host.
    ///   - apId: the post's canonical ActivityPub URL
    ///     (`ReminderRecord.apId`), turned into a
    ///     `URL.SpudInternalLink.objectAtURL` deep-link, same as
    ///     ``timeReminderContent(titleSnapshot:communityName:instanceHost:apId:)``.
    ///     For a subtree follow the caller passes the COMMENT's ap_id instead
    ///     (Task 4), so the tap still opens the post scrolled to that comment.
    ///   - newCount: the number of new comments observed since the reminder's
    ///     baseline (`ReminderActivityRule.shouldFire`'s `newComments`). Never
    ///     0 in practice - the rule never fires on zero new comments.
    ///   - rootCommentServerId: `ReminderRecord.wholePostSentinel` (the
    ///     default) for a whole-post follow, or a comment's server id for a
    ///     subtree follow - only used to pick the body copy ("new comments"
    ///     vs "new replies"); it plays no part in the deep link.
    public static func activityReminderContent(
        titleSnapshot: String,
        communityName: String,
        instanceHost: String,
        apId: String,
        newCount: Int,
        rootCommentServerId: Int64 = ReminderRecord.wholePostSentinel
    ) -> ReminderNotificationContent {
        let isSubtree = rootCommentServerId != ReminderRecord.wholePostSentinel

        // Two separate localized formats (rather than stitching a pluralized
        // noun into one template) so a singular "1 new comment"/"1 new reply"
        // doesn't read "1 new comments"/"1 new replies" - both use positional
        // specifiers so the count can still be reordered relative to the
        // community handle in translation.
        let bodyFormat: String = if isSubtree {
            newCount == 1
                ? NSLocalizedString(
                    "%1$d new reply · c/%2$@@%3$@",
                    comment: "Fired subtree-activity-reminder notification body, singular; %1$d is always 1, %2$@ is the community name, %3$@ is its instance host"
                )
                : NSLocalizedString(
                    "%1$d new replies · c/%2$@@%3$@",
                    comment: "Fired subtree-activity-reminder notification body, plural; %1$d is the new-reply count, %2$@ is the community name, %3$@ is its instance host"
                )
        } else {
            newCount == 1
                ? NSLocalizedString(
                    "%1$d new comment · c/%2$@@%3$@",
                    comment: "Fired activity-reminder notification body, singular; %1$d is always 1, %2$@ is the community name, %3$@ is its instance host"
                )
                : NSLocalizedString(
                    "%1$d new comments · c/%2$@@%3$@",
                    comment: "Fired activity-reminder notification body, plural; %1$d is the new-comment count, %2$@ is the community name, %3$@ is its instance host"
                )
        }
        let body = String(format: bodyFormat, newCount, communityName, instanceHost)

        guard let apURL = URL(string: apId) else {
            // Should never happen in practice - see the matching guard in
            // `timeReminderContent`.
            logger.error("activityReminderContent: apId is not a valid URL: \(apId, privacy: .public)")
            return ReminderNotificationContent(title: titleSnapshot, body: body, routingURLString: "")
        }

        let routingURL = URL.SpudInternalLink.objectAtURL(url: apURL).url
        return ReminderNotificationContent(title: titleSnapshot, body: body, routingURLString: routingURL.absoluteString)
    }

    /// Builds the content for a fired community "new posts" follow, posted
    /// ad-hoc by the foreground poll (`ReminderService.pollDueCommunityFollows`)
    /// rather than scheduled up-front - mirrors `activityReminderContent`.
    ///
    /// Unlike `timeReminderContent`/`activityReminderContent`, the deep link
    /// routes to the COMMUNITY (`URL.SpudInternalLink.community`), not a post
    /// - there's no single post to open, the follow is on the community
    /// itself.
    ///
    /// - Parameters:
    ///   - title: the community's display title, denormalized onto the
    ///     reminder record at follow-time (`ReminderRecord.titleSnapshot`).
    ///   - communityName: the community's bare name (no `!`/`@`).
    ///   - instanceHost: the community's home instance host, used both for
    ///     the body copy's qualified handle and to resolve the deep link's
    ///     `InstanceActorId` (bare stored host string, same construction
    ///     `SiteListRow.forTypedInstance`'s call sites use).
    ///   - newCount: the number of new posts observed since the follow's
    ///     watermark (`CommunityFollowRule.shouldFire`'s `newPosts`). Never 0
    ///     in practice - the rule never fires on zero new posts.
    ///   - isSaturated: whether the fetched page was entirely new posts AND
    ///     reached `CommunityFollowRule.saturationThreshold` - there may be
    ///     more beyond the single fetched page, so the body reads "N+ new
    ///     posts" instead of an exact count.
    public static func communityFollowContent(
        title: String,
        communityName: String,
        instanceHost: String,
        newCount: Int,
        isSaturated: Bool
    ) -> ReminderNotificationContent {
        // Three separate localized formats (rather than stitching a
        // pluralized/saturated noun into one template), same rationale as
        // `activityReminderContent` - all three use positional specifiers so
        // the count can still be reordered relative to the community handle
        // in translation.
        let bodyFormat: String = if isSaturated {
            NSLocalizedString(
                "%1$d+ new posts · c/%2$@@%3$@",
                comment: "Fired community-follow notification body, saturated (more posts than the fetched page could show); %1$d is the new-post count, %2$@ is the community name, %3$@ is its instance host"
            )
        } else if newCount == 1 {
            NSLocalizedString(
                "%1$d new post · c/%2$@@%3$@",
                comment: "Fired community-follow notification body, singular; %1$d is always 1, %2$@ is the community name, %3$@ is its instance host"
            )
        } else {
            NSLocalizedString(
                "%1$d new posts · c/%2$@@%3$@",
                comment: "Fired community-follow notification body, plural; %1$d is the new-post count, %2$@ is the community name, %3$@ is its instance host"
            )
        }
        let body = String(format: bodyFormat, newCount, communityName, instanceHost)

        // `instanceHost` is a bare host string (no scheme) - prepend one so
        // `InstanceActorId(from:)` parses it as a host rather than falling
        // through to its naive regex fallback, mirroring the construction
        // `MainWindow`'s custom-instance seam uses ahead of
        // `SiteListRow.forTypedInstance`.
        // `InstanceActorId(from: String)` succeeds even on an empty host
        // (`URLComponents(string: "https://").host == ""`, non-nil), so the
        // nil check alone isn't enough - `isValid` catches an empty host too.
        guard let instance = InstanceActorId(from: "https://\(instanceHost)"), instance.isValid else {
            // Should never happen in practice - instanceHost is denormalized
            // from a resolved community's own instance at follow-set time.
            // Degrade to a notification with no working deep link rather than
            // crashing on a malformed stored host.
            logger.error("communityFollowContent: instanceHost is not a valid host: \(instanceHost, privacy: .public)")
            return ReminderNotificationContent(title: title, body: body, routingURLString: "")
        }

        let routingURL = URL.SpudInternalLink.community(name: communityName, instance: instance).url
        return ReminderNotificationContent(title: title, body: body, routingURLString: routingURL.absoluteString)
    }
}

/// Schedules/cancels the OS local notification behind a reminder. Injected
/// into `ReminderService` (the per-account actor that owns reminder
/// lifecycle) so it stays unit-testable against a fake; the production
/// implementation is `UNReminderNotificationScheduler`.
public protocol ReminderNotificationScheduling: Sendable {
    /// Requests notification authorization if not yet determined, and returns
    /// whether notifications are (now) allowed. Callers should invoke this
    /// lazily on first use (`ReminderService.setTimeReminder`), never at
    /// launch, so the OS permission prompt only ever appears as a direct
    /// consequence of an explicit "Remind Me…" action.
    func requestAuthorization() async -> Bool

    /// Whether notification authorization is currently granted, without
    /// prompting the user.
    func authorizationGranted() async -> Bool

    /// Schedules a local notification for `content` to fire at `fireAt`,
    /// identified by `requestId`. Scheduling under an id that's already
    /// pending replaces it (matches `UNUserNotificationCenter.add`'s
    /// identifier semantics), which is how `ReminderService` re-schedules a
    /// reminder that's set a second time for the same target.
    func schedule(requestId: String, fireAt: Date, content: ReminderNotificationContent) async

    /// Posts a local notification for `content` **immediately**, identified by
    /// `requestId`. Used by the activity-reminder poll
    /// (`ReminderService.pollDueActivityReminders`) when
    /// `ReminderActivityRule.shouldFire` trips - unlike `schedule`, there is
    /// no future `fireAt` to wait for; the poll already observed the
    /// fired condition just now. Distinct from `schedule`'s
    /// `UNCalendarNotificationTrigger` path used by time reminders, which
    /// fires at a specific wall-clock date even if the app never runs again
    /// before then.
    func postNow(requestId: String, content: ReminderNotificationContent) async

    /// Cancels a previously-scheduled notification request by id. A no-op if
    /// no such request is pending (e.g. it already fired, or permission was
    /// never granted so nothing was ever scheduled).
    func cancel(requestId: String) async
}

/// `UNUserNotificationCenter`-backed `ReminderNotificationScheduling`.
///
/// `@unchecked Sendable`: `UNUserNotificationCenter` predates Swift
/// concurrency's `Sendable` annotations, but Apple's documentation guarantees
/// it's safe to use from any thread/queue (it's the same shared instance
/// notification-service and share extensions call into), so wrapping it here
/// is sound - mirrors `ImageService`'s same-shaped wrap of non-Sendable system
/// APIs.
public final class UNReminderNotificationScheduler: ReminderNotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("requestAuthorization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    public func authorizationGranted() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    public func schedule(requestId: String, fireAt: Date, content: ReminderNotificationContent) async {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.sound = .default
        notificationContent.userInfo = [ReminderNotificationContent.userInfoRoutingURLKey: content.routingURLString]

        // A calendar trigger (rather than a time-interval one) fires at the
        // wall-clock date the user picked even across the app being
        // suspended/relaunched or the device rebooting in between - the OS
        // owns the fire, not an in-process timer.
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(identifier: requestId, content: notificationContent, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.error("schedule(\(requestId, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func postNow(requestId: String, content: ReminderNotificationContent) async {
        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = content.title
        notificationContent.body = content.body
        notificationContent.sound = .default
        notificationContent.userInfo = [ReminderNotificationContent.userInfoRoutingURLKey: content.routingURLString]

        // A short (rather than nil) time-interval trigger: `UNUserNotificationCenter`
        // requires a non-zero interval, and a 1-second delay is indistinguishable
        // from "now" to the user while still going through the normal trigger path
        // (nil triggers deliver instantly but are documented as best suited to
        // silent/background pushes, not user-visible alerts).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(identifier: requestId, content: notificationContent, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            logger.error("postNow(\(requestId, privacy: .public)) failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func cancel(requestId: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
