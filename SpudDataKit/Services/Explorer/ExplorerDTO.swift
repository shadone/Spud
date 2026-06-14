//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

// Decodable mirrors of the Lemmy Explorer (data.lemmyverse.net) output schema.
// Only the fields Spud persists are modelled; unknown JSON keys are ignored.
// Schema reference: tgxn/lemmy-explorer types/output.ts + types/storage.ts.

/// Multi-part dataset metadata: `GET /data/{set}.json` -> `{ "count": N }`.
struct ExplorerMultipartMetadataDTO: Decodable {
    let count: Int
}

struct ExplorerInstanceDTO: Decodable {
    let baseurl: String
    let url: String?
    let name: String?
    let desc: String?
    let version: String?
    let nsfw: Bool?
    let downvotes: Bool?
    let isPrivate: Bool?
    let regMode: Int?
    let open: Bool?
    let fed: Bool?
    let score: Double?
    let isSuspicious: Bool?
    let icon: String?
    let banner: String?
    let langs: [String]?
    let tags: [String]?
    let usage: Usage?
    let counts: Counts?
    let uptime: Uptime?
    let blocks: Blocks?

    struct Usage: Decodable {
        let users: Users?

        struct Users: Decodable {
            let total: Int?
            let activeHalfyear: Int?
            let activeMonth: Int?
        }
    }

    struct Counts: Decodable {
        let posts: Int?
        let comments: Int?
        let communities: Int?
    }

    struct Uptime: Decodable {
        let latency: Double?
        let uptimeAlltime: String?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case latency
            case uptimeAlltime = "uptime_alltime"
            case status
        }
    }

    struct Blocks: Decodable {
        let incoming: Int?
        let outgoing: Int?
    }

    enum CodingKeys: String, CodingKey {
        case baseurl, url, name, desc, version, nsfw, downvotes
        case isPrivate = "private"
        case regMode = "reg_mode"
        case open, fed, score, isSuspicious, icon, banner, langs, tags
        case usage, counts, uptime, blocks
    }
}

struct ExplorerCommunityDTO: Decodable {
    let baseurl: String
    let url: String
    let name: String?
    let title: String?
    let desc: String?
    let icon: String?
    let banner: String?
    let nsfw: Bool?
    let score: Double?
    let isSuspicious: Bool?
    /// Community creation date as Unix epoch milliseconds (lemmyverse top-level
    /// `published`). Drives the "Newest" sort.
    let published: Int64?
    let counts: Counts?

    struct Counts: Decodable {
        let subscribers: Int?
        let posts: Int?
        let comments: Int?
        let usersActiveDay: Int?
        let usersActiveWeek: Int?
        let usersActiveMonth: Int?
        let usersActiveHalfYear: Int?

        enum CodingKeys: String, CodingKey {
            case subscribers, posts, comments
            case usersActiveDay = "users_active_day"
            case usersActiveWeek = "users_active_week"
            case usersActiveMonth = "users_active_month"
            case usersActiveHalfYear = "users_active_half_year"
        }
    }
}

// MARK: - DTO -> Record

extension ExplorerInstanceDTO {
    func makeRecord(updatedAt: Date) -> ExplorerInstanceRecord {
        ExplorerInstanceRecord(
            baseurl: baseurl,
            url: url,
            name: name ?? baseurl,
            descriptionText: desc,
            version: version,
            usersTotal: Int64(usage?.users?.total ?? 0),
            usersActiveMonth: Int64(usage?.users?.activeMonth ?? 0),
            usersActiveHalfYear: Int64(usage?.users?.activeHalfyear ?? 0),
            numberOfCommunities: Int64(counts?.communities ?? 0),
            numberOfPosts: Int64(counts?.posts ?? 0),
            numberOfComments: Int64(counts?.comments ?? 0),
            uptimeAllTime: uptime?.uptimeAlltime.flatMap { Double($0) },
            latency: uptime?.latency,
            uptimeStatus: uptime?.status.map { Int64($0) },
            regMode: Int64(regMode ?? -1),
            isOpenRegistration: open ?? false,
            isNsfw: nsfw ?? false,
            allowsDownvotes: downvotes ?? true,
            isPrivate: isPrivate ?? false,
            federationEnabled: fed ?? true,
            score: score ?? 0,
            isSuspicious: isSuspicious ?? false,
            iconUrl: icon,
            bannerUrl: banner,
            langs: langs?.joined(separator: ","),
            tags: tags?.joined(separator: ","),
            blocksIncoming: blocks?.incoming.map { Int64($0) },
            blocksOutgoing: blocks?.outgoing.map { Int64($0) },
            updatedAt: updatedAt
        )
    }
}

extension ExplorerCommunityDTO {
    func makeRecord(updatedAt: Date) -> ExplorerCommunityRecord {
        ExplorerCommunityRecord(
            url: url,
            baseurl: baseurl,
            name: name ?? url,
            title: title,
            descriptionText: desc,
            iconUrl: icon,
            bannerUrl: banner,
            isNsfw: nsfw ?? false,
            numberOfSubscribers: Int64(counts?.subscribers ?? 0),
            numberOfPosts: Int64(counts?.posts ?? 0),
            numberOfComments: Int64(counts?.comments ?? 0),
            usersActiveDay: Int64(counts?.usersActiveDay ?? 0),
            usersActiveWeek: Int64(counts?.usersActiveWeek ?? 0),
            usersActiveMonth: Int64(counts?.usersActiveMonth ?? 0),
            usersActiveHalfYear: Int64(counts?.usersActiveHalfYear ?? 0),
            score: score ?? 0,
            isSuspicious: isSuspicious ?? false,
            publishedAt: published.map { Date(timeIntervalSince1970: Double($0) / 1000) },
            updatedAt: updatedAt
        )
    }
}
