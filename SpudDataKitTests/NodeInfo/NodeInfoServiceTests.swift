//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

private actor CallCounter { var count = 0
    func bump() {
        count += 1
    }
}

private struct FakeFetcher: NodeInfoFetching {
    let result: Result<FetchedNodeInfo, Error>
    let counter: CallCounter?
    let sleepSeconds: Double?
    init(
        _ result: Result<FetchedNodeInfo, Error>,
        counter: CallCounter? = nil,
        sleepSeconds: Double? = nil
    ) {
        self.result = result
        self.counter = counter
        self.sleepSeconds = sleepSeconds
    }

    func fetch(host _: String) async throws -> FetchedNodeInfo {
        await counter?.bump()
        if let sleepSeconds { try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000)) }
        return try result.get()
    }
}

/// Convenience for building a probe result in tests without spelling out every
/// optional usage field.
private func fetched(
    _ name: String,
    _ version: String? = nil,
    openRegistrations: Bool? = nil,
    usersTotal: Int64? = nil,
    usersActiveMonth: Int64? = nil,
    usersActiveHalfyear: Int64? = nil,
    localPosts: Int64? = nil,
    localComments: Int64? = nil
) -> FetchedNodeInfo {
    FetchedNodeInfo(
        softwareName: name,
        softwareVersion: version,
        openRegistrations: openRegistrations,
        usersTotal: usersTotal,
        usersActiveMonth: usersActiveMonth,
        usersActiveHalfyear: usersActiveHalfyear,
        localPosts: localPosts,
        localComments: localComments
    )
}

private struct FetchBoom: Error { }

struct NodeInfoServiceTests {
    // MARK: - detect (unchanged behavior)

    @Test
    func detectsAndCachesOnSuccess() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy", "0.19.5"))),
            appDatabase: .inMemory()
        )
        let result = await service.detect(host: "Lemmy.World")
        #expect(result == .known(.lemmy, version: "0.19.5"))
    }

    @Test
    func freshCacheHitDoesNotRefetch() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("piefed", "1.0")), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.detect(host: "piefed.social")
        _ = await service.detect(host: "piefed.social")
        #expect(await counter.count == 1)
    }

    @Test
    func staleCacheRefetches() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy", "0.19.5")), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.detect(host: "a.example", maxAge: 3600)
        // maxAge 0 forces the existing row to count as stale.
        _ = await service.detect(host: "a.example", maxAge: 0)
        #expect(await counter.count == 2)
    }

    @Test
    func fetchErrorYieldsUnknown() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.failure(FetchBoom())),
            appDatabase: .inMemory()
        )
        #expect(await service.detect(host: "blocked.example") == .unknown)
    }

    @Test
    func timeoutYieldsUnknown() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy")), sleepSeconds: 10),
            appDatabase: .inMemory(),
            timeout: 0.05
        )
        #expect(await service.detect(host: "slow.example") == .unknown)
    }

    // MARK: - metadata

    @Test
    func metadataReturnsFullPayloadOnSuccess() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched(
                "lemmy", "0.19.5",
                openRegistrations: true,
                usersTotal: 1000, usersActiveMonth: 200, usersActiveHalfyear: 500,
                localPosts: 3000, localComments: 9000
            ))),
            appDatabase: .inMemory()
        )
        let metadata = try #require(await service.metadata(host: "Lemmy.World"))
        #expect(metadata.software == .lemmy)
        #expect(metadata.version == "0.19.5")
        #expect(metadata.openRegistrations == true)
        #expect(metadata.usersTotal == 1000)
        #expect(metadata.usersActiveMonth == 200)
        #expect(metadata.usersActiveHalfyear == 500)
        #expect(metadata.localPosts == 3000)
        #expect(metadata.localComments == 9000)
    }

    @Test
    func metadataFreshCacheHitDoesNotRefetch() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy", "0.19.5", usersTotal: 5)), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.metadata(host: "lemmy.world")
        _ = await service.metadata(host: "lemmy.world")
        #expect(await counter.count == 1)
    }

    @Test
    func metadataStaleCacheRefetches() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy", "0.19.5")), counter: counter),
            appDatabase: .inMemory()
        )
        _ = await service.metadata(host: "a.example", maxAge: 3600)
        _ = await service.metadata(host: "a.example", maxAge: 0)
        #expect(await counter.count == 2)
    }

    @Test
    func metadataFetchErrorYieldsNil() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.failure(FetchBoom())),
            appDatabase: .inMemory()
        )
        #expect(await service.metadata(host: "blocked.example") == nil)
    }

    @Test
    func metadataTimeoutYieldsNil() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy")), sleepSeconds: 10),
            appDatabase: .inMemory(),
            timeout: 0.05
        )
        #expect(await service.metadata(host: "slow.example") == nil)
    }

    // MARK: - single-row coherence (one probe, one row, shared by both accessors)

    @Test
    func metadataProbePopulatesRowThatDetectServesWithoutRefetch() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched("lemmy", "0.19.5", openRegistrations: true)), counter: counter),
            appDatabase: .inMemory()
        )
        // metadata probes first, then detect must serve from the same fresh row.
        _ = await service.metadata(host: "shared.example")
        let detection = await service.detect(host: "shared.example")
        #expect(detection == .known(.lemmy, version: "0.19.5"))
        #expect(await counter.count == 1)
    }

    @Test
    func detectProbePopulatesRowThatMetadataServesWithoutRefetch() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(fetched(
                "lemmy", "0.19.5",
                openRegistrations: false, usersTotal: 42
            )), counter: counter),
            appDatabase: .inMemory()
        )
        // detect probes first; the row it writes must carry the FULL metadata so
        // a following metadata call reads real values from cache, not nil.
        _ = await service.detect(host: "shared.example")
        let metadata = try #require(await service.metadata(host: "shared.example"))
        #expect(await counter.count == 1)
        #expect(metadata.openRegistrations == false)
        #expect(metadata.usersTotal == 42)
    }
}
