//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import LemmyKit
import SpudUtilKit

/// The namespace for types used by ``PreferencesService``.
enum Preferences { }

@MainActor
protocol PreferencesServiceType: AnyObject {
    var defaultCommentSortType: Components.Schemas.CommentSortType { get set }
    var defaultCommentSortTypeStream: AsyncStream<Components.Schemas.CommentSortType> { get }

    /// Describes how to open external links from posts and comments.
    var openExternalLinks: Preferences.OpenExternalLink { get set }
    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> { get }

    /// Specifies whether to open Reader mode when opening external link in SFSafariViewController.
    var openExternalLinksInSafariVCReaderMode: Bool { get set }
    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> { get }

    /// When opening external link first check if it's a universal link first and then open it in the app.
    var openUniversalLinkInApp: Bool { get set }
}

@MainActor
protocol HasPreferencesService {
    var preferencesService: PreferencesServiceType { get }
}

@MainActor
class PreferencesService: PreferencesServiceType {
    @UserDefaultsBacked(key: "defaultCommentSortType")
    var defaultCommentSortType: Components.Schemas.CommentSortType = .Hot

    var defaultCommentSortTypeStream: AsyncStream<Components.Schemas.CommentSortType> {
        Self.stream(from: $defaultCommentSortType)
    }

    @UserDefaultsBacked(key: "openExternalLinks")
    var openExternalLinks: Preferences.OpenExternalLink = .safariViewController

    var openExternalLinksStream: AsyncStream<Preferences.OpenExternalLink> {
        Self.stream(from: $openExternalLinks)
    }

    @UserDefaultsBacked(key: "openExternalLinksInSafariVCReaderMode")
    var openExternalLinksInSafariVCReaderMode = true

    var openExternalLinksInSafariVCReaderModeStream: AsyncStream<Bool> {
        Self.stream(from: $openExternalLinksInSafariVCReaderMode)
    }

    @UserDefaultsBacked(key: "openUniversalLinkInApp")
    var openUniversalLinkInApp: Bool = true

    /// Bridges a Combine publisher into an AsyncStream so callers don't
    /// need to import Combine. Cancelling the stream cancels the
    /// underlying subscription.
    private static func stream<Value: Sendable>(
        from publisher: AnyPublisher<Value, Never>
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task {
                for await value in publisher.values {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
