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
                "c/%@@%@ · Tap to revisit",
                comment: "Fired reminder notification body; first %@ is the community name, second %@ is its instance host"
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

    public func cancel(requestId: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
