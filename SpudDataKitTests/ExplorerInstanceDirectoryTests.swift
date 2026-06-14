//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudUtilKit
import XCTest
@testable import SpudDataKit

final class ExplorerInstanceDirectoryTests: XCTestCase {
    private var nextId: Int64 = 0

    private func row(
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

    func test_sortByUsers_descending() {
        let rows = [row("a.test", users: 10), row("b.test", users: 99), row("c.test", users: 50)]
        let sorted = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .users
        )
        XCTAssertEqual(sorted.map(\.hostname), ["b.test", "c.test", "a.test"])
    }

    func test_sortByName_caseInsensitiveAscending() {
        let rows = [row("Beta.test"), row("alpha.test")]
        let sorted = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(), sort: .name
        )
        XCTAssertEqual(sorted.map(\.hostname), ["alpha.test", "Beta.test"])
    }

    func test_filterRegistrationOpen() {
        let rows = [row("open.test", open: true), row("closed.test", open: false)]
        let filtered = ExplorerInstanceDirectory.apply(
            to: rows, query: "", filter: .init(registrationOpenOnly: true), sort: .recommended
        )
        XCTAssertEqual(filtered.map(\.hostname), ["open.test"])
    }

    func test_filterHideNsfwAndLanguage() {
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
        XCTAssertEqual(filtered.map(\.hostname), ["sfw.en"])
    }

    func test_query_matchesHostname() {
        let rows = [row("lemmy.world"), row("sopuli.xyz")]
        let filtered = ExplorerInstanceDirectory.apply(
            to: rows, query: "sopuli", filter: .init(), sort: .recommended
        )
        XCTAssertEqual(filtered.map(\.hostname), ["sopuli.xyz"])
    }

    func test_availableLanguages_distinctSorted() {
        let rows = [row("a", langs: ["en", "de"]), row("b", langs: ["en", "fr"])]
        XCTAssertEqual(ExplorerInstanceDirectory.availableLanguages(in: rows), ["de", "en", "fr"])
    }

    func test_filterIsActive() {
        XCTAssertFalse(ExplorerInstanceFilter().isActive)
        XCTAssertTrue(ExplorerInstanceFilter(hideNsfw: true).isActive)
        XCTAssertTrue(ExplorerInstanceFilter(language: "en").isActive)
    }
}
