//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudUtilKit

/// A typed navigation target an App Intent (or other entry point) wants to reach.
/// Routed by `AppCoordinator.navigate(_:)` into the live `MainWindow`, or stored
/// as `pendingNavigation` and replayed once a window is ready (cold launch).
enum AppNavigation: Equatable {
    case feed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?)
    case search(query: String)
    case newPost
    case inbox
    case community(name: String, instance: InstanceActorId)
}

/// The navigation surface the router drives. `MainWindow` conforms; tests use a
/// spy so routing is verified without a real window.
@MainActor
protocol AppNavigating: AnyObject {
    func selectFeed(listing: Components.Schemas.ListingType, sort: Components.Schemas.SortType?)
    func selectSearch(query: String)
    func presentNewPost()
    func selectInbox()
    func display(communityName: String, instance: InstanceActorId, accountKeychainId: String)
}
