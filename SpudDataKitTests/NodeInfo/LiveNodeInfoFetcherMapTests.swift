//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import DiasporaNodeInfo
import Foundation
import Testing
@testable import SpudDataKit

/// Decode-level coverage for `LiveNodeInfoFetcher.map`: exercises the pure
/// `NodeInfo` -> `FetchedNodeInfo` mapping (empty-name throw, empty-version
/// normalization, all six usage accessors) WITHOUT a live network host, by
/// constructing package payload values via the 2.0 memberwise inits the
/// package ships "for testing or fixture purposes".
struct LiveNodeInfoFetcherMapTests {
    private func v2_0Info(
        name: String = "lemmy",
        version: String = "0.19.5",
        openRegistrations: Bool = true,
        usersTotal: Int64? = 1000,
        usersActiveMonth: Int64? = 200,
        usersActiveHalfyear: Int64? = 500,
        localPosts: Int64? = 3000,
        localComments: Int64? = 9000
    ) -> NodeInfo {
        .v2_0(.init(
            version: "2.0",
            software: .init(name: name, version: version),
            protocols: [],
            openRegistrations: openRegistrations,
            usage: .init(
                users: .init(
                    total: usersTotal,
                    activeHalfyear: usersActiveHalfyear,
                    activeMonth: usersActiveMonth
                ),
                localPosts: localPosts,
                localComments: localComments
            )
        ))
    }

    @Test
    func mapsFullV2_0Payload() throws {
        let fetched = try LiveNodeInfoFetcher.map(v2_0Info())
        #expect(fetched.softwareName == "lemmy")
        #expect(fetched.softwareVersion == "0.19.5")
        #expect(fetched.openRegistrations == true)
        #expect(fetched.usersTotal == 1000)
        #expect(fetched.usersActiveMonth == 200)
        #expect(fetched.usersActiveHalfyear == 500)
        #expect(fetched.localPosts == 3000)
        #expect(fetched.localComments == 9000)
    }

    @Test
    func mapsVersionAgnosticallyAcrossV2_1() throws {
        // The convenience accessors branch on the schema case; prove the mapper
        // reads a v2.1 payload just the same.
        let info = NodeInfo.v2_1(.init(
            version: "2.1",
            software: .init(name: "piefed", version: "1.2.3", repository: "https://example", homepage: nil),
            protocols: [],
            openRegistrations: false,
            usage: .init(
                users: .init(total: 7, activeHalfyear: 3, activeMonth: 1),
                localPosts: nil,
                localComments: nil
            )
        ))
        let fetched = try LiveNodeInfoFetcher.map(info)
        #expect(fetched.softwareName == "piefed")
        #expect(fetched.softwareVersion == "1.2.3")
        #expect(fetched.openRegistrations == false)
        #expect(fetched.usersTotal == 7)
        // A node that omits post/comment usage maps those to nil, not zero.
        #expect(fetched.localPosts == nil)
        #expect(fetched.localComments == nil)
    }

    @Test
    func emptyVersionMapsToNil() throws {
        let fetched = try LiveNodeInfoFetcher.map(v2_0Info(version: ""))
        #expect(fetched.softwareVersion == nil)
    }

    @Test
    func emptyNameThrows() {
        #expect(throws: LiveNodeInfoFetcher.MissingSoftwareName.self) {
            _ = try LiveNodeInfoFetcher.map(v2_0Info(name: ""))
        }
    }
}
