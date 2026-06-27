//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import Testing
@testable import SpudDataKit

struct ExplorerInstanceDirectoryTests {
    private var nextId: Int64 = 0

    private mutating func row(
        _ host: String,
        score: Double = 0,
        users: Int64? = nil,
        active: Int64? = nil,
        uptime: Double? = nil,
        nsfw: Bool = false,
        open: Bool = false,
        langs: [String] = []
    ) -> SiteListRow {
        nextId += 1
        return SiteListRow(
            id: nextId,
            instance: InstanceActorId(from: "https://\(host)")!,
            hostname: host,
            name: nil,
            descriptionText: nil,
            iconUrl: nil,
            score: score,
            usersTotal: users,
            usersActiveMonth: active,
            uptimeAllTime: uptime,
            isNsfw: nsfw,
            isOpenRegistration: open,
            languageCodes: langs,
            tags: []
        )
    }

    @Test
    mutating func sortByUsers_descending() {
        let rows = [row("a.test", users: 10), row("b.test", users: 99), row("c.test", users: 50)]
        let sorted = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .users
        )
        #expect(sorted.map(\.hostname) == ["b.test", "c.test", "a.test"])
    }

    @Test
    mutating func sortByName_caseInsensitiveAscending() {
        let rows = [row("Beta.test"), row("alpha.test")]
        let sorted = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name
        )
        #expect(sorted.map(\.hostname) == ["alpha.test", "Beta.test"])
    }

    @Test
    mutating func filterRegistrationOpen() {
        let rows = [row("open.test", open: true), row("closed.test", open: false)]
        let filtered = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(registrationOpenOnly: true), sort: .recommended
        )
        #expect(filtered.map(\.hostname) == ["open.test"])
    }

    @Test
    mutating func filterHideNsfwAndLanguage() {
        let rows = [
            row("sfw.de", nsfw: false, langs: ["de"]),
            row("nsfw.en", nsfw: true, langs: ["en"]),
            row("sfw.en", nsfw: false, langs: ["en"]),
        ]
        let filtered = ExplorerInstanceDirectory.apply(
            to: rows,
            query: "",
            filter: .init(hideNsfw: true, language: "en"),
            sort: .recommended
        )
        #expect(filtered.map(\.hostname) == ["sfw.en"])
    }

    @Test
    mutating func query_matchesHostname() {
        let rows = [row("lemmy.world"), row("sopuli.xyz")]
        let filtered = ExplorerInstanceDirectory.apply(
            to: rows, query: "sopuli", filter: .init(), sort: .recommended
        )
        #expect(filtered.map(\.hostname) == ["sopuli.xyz"])
    }

    @Test
    mutating func availableLanguages_distinctSorted() {
        let rows = [row("a", langs: ["en", "de"]), row("b", langs: ["en", "fr"])]
        #expect(ExplorerInstanceDirectory.availableLanguages(in: rows) == ["de", "en", "fr"])
    }

    @Test
    mutating func filterIsActive() {
        #expect(!(ExplorerInstanceFilter().isActive))
        #expect(ExplorerInstanceFilter(hideNsfw: true).isActive)
        #expect(ExplorerInstanceFilter(language: "en").isActive)
    }
}
