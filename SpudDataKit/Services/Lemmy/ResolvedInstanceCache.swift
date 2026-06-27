//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Process-lifetime, in-memory cache of ``ExplorerInstanceRecord``s synthesized
/// from a live `/api/v3/site` probe of a host that is *not* in the bundled
/// Lemmy Explorer directory.
///
/// Deliberately separate from the curated `explorerInstance` table: Discover
/// and the instance list read that table, and a synthesized remote record
/// (whose only confirmation is that it answered `/api/v3/site`) must not leak
/// into those curated surfaces. The cache lets a repeat tap on the same host
/// within a session reopen the in-app instance screen instantly without a
/// second network round-trip. It is never persisted; a relaunch re-probes.
@MainActor
public final class ResolvedInstanceCache {
    public static let shared = ResolvedInstanceCache()

    private var recordsByHost: [String: ExplorerInstanceRecord] = [:]

    public init() { }

    /// The cached synthesized record for `host`, or nil if not yet resolved
    /// this session. Host lookups are case-insensitive to match how
    /// ``InstanceActorId`` normalizes hosts.
    public func record(forHost host: String) -> ExplorerInstanceRecord? {
        recordsByHost[host.lowercased()]
    }

    /// Caches `record` under its `baseurl` for the rest of the session.
    public func store(_ record: ExplorerInstanceRecord) {
        recordsByHost[record.baseurl.lowercased()] = record
    }
}
