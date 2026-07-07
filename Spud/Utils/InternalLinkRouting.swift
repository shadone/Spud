//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import OSLog
import SpudDataKit
import SpudUtilKit

private let logger = Logger.app

/// Shared routing for body-text links across the markdown-rendering screens
/// (post detail, community detail, person profile).
///
/// A tapped body link arrives as a `URL` that the host first runs through
/// `MarkdownInternalLink.resolve(_:)` (turning a `spud-markdown://` mention or
/// community link into the app's internal `info.ddenis.spud://` link). The host
/// then calls `routeInternalLink(_:)`, which decodes `url.spud` and dispatches
/// to the conforming screen's leaf `routeTo*` methods.
///
/// The default implementation owns the routing *decision* — including the
/// federated `resolve_object` round-trip for `.objectAtURL` (e.g. a user
/// mention in a community description, whose local id is unknown until
/// resolved) and the `LemmyURLParser` fallback for a bare web URL. Each screen
/// only supplies how to actually open a person / community / post / instance /
/// external URL in its own navigation context.
@MainActor
protocol InternalLinkRouting: AnyObject {
    /// Used to gate the `LemmyURLParser` fallback on known instances.
    var linkRouterAppDatabase: AppDatabase { get }

    /// The account-scoped service used to resolve a federated `.objectAtURL`.
    var linkRouterLemmyService: LemmyServiceType { get }

    func routeToPerson(personId: Lemmy.PersonID, instance: InstanceActorId)
    func routeToCommunity(name: String, instance: InstanceActorId)
    func routeToPost(postId: Lemmy.PostID, instance: InstanceActorId)
    func routeToInstance(_ instance: InstanceActorId)
    func routeToExternal(_ url: URL)
}

extension InternalLinkRouting {
    /// Decodes an internal `info.ddenis.spud://` link (or classifies a bare web
    /// URL) and routes it to the appropriate leaf handler. Non-internal URLs
    /// that don't classify as Lemmy content fall through to `routeToExternal`.
    func routeInternalLink(_ url: URL) {
        switch url.spud {
        case let .person(personId, instance):
            routeToPerson(personId: personId, instance: instance)

        case let .community(name, instance):
            routeToCommunity(name: name, instance: instance)

        case let .post(postId, instance):
            routeToPost(postId: postId, instance: instance)

        case let .objectAtURL(canonicalURL):
            // Don't retain the screen across the resolve round-trip; if it's
            // dismissed mid-flight we skip the navigation rather than push onto
            // a stack that's gone (the weak-self Task pattern used elsewhere).
            Task { @MainActor [weak self] in await self?.resolveAndRoute(canonicalURL) }

        case let .instance(instance):
            routeToInstance(instance)

        case .none:
            // Not an internal link. Classify it as a Lemmy URL (known-instance
            // gated); fall back to the screen's external-link handling.
            let isKnown: (String) -> Bool = { [linkRouterAppDatabase] host in
                linkRouterAppDatabase.explorerInstanceSync(baseurl: host) != nil
            }
            if let internalLink = LemmyURLParser.classify(url: url, isKnownInstance: isKnown) {
                routeInternalLink(internalLink.url)
                return
            }
            routeToExternal(url)
        }
    }

    /// Resolves a federated object under the current account, then routes by
    /// type. Comments and unresolved links fall back to the external handler.
    private func resolveAndRoute(_ canonicalURL: URL) async {
        let resolved: ResolvedLemmyObject
        do {
            resolved = try await linkRouterLemmyService.resolveObject(query: canonicalURL.absoluteString)
        } catch {
            logger.error("resolve_object failed for \(canonicalURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            routeToExternal(canonicalURL)
            return
        }
        switch resolved {
        case let .post(postId, instance):
            routeToPost(postId: postId, instance: instance)
        case let .community(name, instance):
            routeToCommunity(name: name, instance: instance)
        case let .person(personId, instance):
            routeToPerson(personId: personId, instance: instance)
        case let .comment(postId, _, instance):
            // Open the comment's parent post in-app. (Scrolling a body link to the
            // exact comment is handled for deep-link / share permalinks via
            // AppCoordinator; here we at least keep the link in-app rather than
            // bouncing to Safari.)
            routeToPost(postId: postId, instance: instance)
        case .unresolved:
            routeToExternal(canonicalURL)
        }
    }
}
