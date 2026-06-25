//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Observation
import OSLog
import SpudDataKit
import SpudUtilKit

private let logger = Logger.app

/// View model for the community screen header. Holds plain @Observable state
/// driven by `appDatabase.observeCommunity`. The post feed below the header is
/// owned by an embedded `PostListViewController`, not this model.
@MainActor
@Observable
final class CommunityViewModel {
    /// Bare community name, e.g. "world".
    var name: String = ""
    /// Human-facing title, falling back to `name` when absent.
    var title: String = ""
    /// Canonical "!name@instance" handle, e.g. "!world@lemmy.world".
    var qualifiedName: String = ""
    /// The community's federation actor id (e.g. "https://lemmy.world/c/world"),
    /// used as the key for client-local muting. nil until the record loads.
    var actorId: String?
    var descriptionMarkdown: String?
    var iconUrl: URL?
    var bannerUrl: URL?
    var subscribersText: String = ""
    var postsText: String = ""
    var subscribed: CommunitySubscribedState = .notSubscribed

    /// Activity line for the vitality strip ("N active this week  ·  M this
    /// month"), sourced from the bundled Explorer directory. nil when the
    /// community isn't in the directory (so the strip stays hidden).
    var vitalityText: String?

    /// True when the community has marked itself as NSFW.
    var isNsfw: Bool = false

    /// Whether this community is currently blocked by the backing account.
    /// Sourced from `getSite` -> `my_user` (blocks aren't persisted on the
    /// community record); set by the view controller. Updated optimistically
    /// when the user blocks/unblocks.
    var isBlocked: Bool = false
    /// True once the block state has been resolved from the server.
    var blockStateKnown: Bool = false

    /// True once the first GRDB snapshot for this community has arrived.
    var hasLoaded = false

    let serverCommunityId: Components.Schemas.CommunityID

    @ObservationIgnored
    private let appDatabase: AppDatabase
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    init(
        accountRowId: Int64,
        serverCommunityId: Components.Schemas.CommunityID,
        appDatabase: AppDatabase
    ) {
        self.serverCommunityId = serverCommunityId
        self.appDatabase = appDatabase

        observationTask = Task { [weak self] in
            for await record in appDatabase.observeCommunity(
                forAccountId: accountRowId,
                serverCommunityId: Int64(serverCommunityId)
            ) {
                if Task.isCancelled { break }
                guard let record else { continue }
                await MainActor.run { self?.apply(record: record) }
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func apply(record: CommunityRecord) {
        hasLoaded = true
        name = record.name ?? ""
        title = record.title ?? record.name ?? ""
        qualifiedName = Self.qualifiedName(name: record.name, actorId: record.actorId)
        actorId = record.actorId
        descriptionMarkdown = record.descriptionText
        iconUrl = record.iconUrl.flatMap { URL(string: $0) }
        bannerUrl = record.bannerUrl.flatMap { URL(string: $0) }
        subscribersText = CommentsFormatter.string(from: record.numberOfSubscribers)
        postsText = CommentsFormatter.string(from: record.numberOfPosts)
        subscribed = record.subscribed
        isNsfw = record.isNsfw
        loadVitalityIfNeeded()
    }

    /// Resolve the community's network activity from the Explorer directory once
    /// its actor id is known. The directory is bundled and static within a
    /// session, so a single indexed lookup is enough.
    private func loadVitalityIfNeeded() {
        guard vitalityText == nil, let actorId else { return }
        guard let explorer = appDatabase.explorerCommunitySync(url: actorId) else { return }
        let week = CommentsFormatter.string(from: explorer.usersActiveWeek)
        let month = CommentsFormatter.string(from: explorer.usersActiveMonth)
        let weekText = String(
            format: NSLocalizedString("%@ active this week", comment: "Community vitality: weekly active users"),
            week
        )
        let monthText = String(
            format: NSLocalizedString("%@ this month", comment: "Community vitality: monthly active users"),
            month
        )
        vitalityText = "\(weekText)  ·  \(monthText)"
    }

    /// Builds the "!name@instance" handle from the bare name and the
    /// community's federation actor id (e.g. "https://lemmy.world/c/world").
    static func qualifiedName(name: String?, actorId: String?) -> String {
        guard let name else { return "" }
        guard
            let actorId,
            let url = URL(string: actorId),
            let host = url.host
        else {
            return "!\(name)"
        }
        return "!\(name)@\(host)"
    }
}
