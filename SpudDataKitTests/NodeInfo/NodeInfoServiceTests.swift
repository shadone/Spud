// SpudDataKitTests/NodeInfo/NodeInfoServiceTests.swift
import Foundation
import Testing
@testable import SpudDataKit

private actor CallCounter { var count = 0
    func bump() {
        count += 1
    }
}

private struct FakeFetcher: NodeInfoFetching {
    let result: Result<(softwareName: String, softwareVersion: String?), Error>
    let counter: CallCounter?
    let sleepSeconds: Double?
    init(
        _ result: Result<(softwareName: String, softwareVersion: String?), Error>,
        counter: CallCounter? = nil,
        sleepSeconds: Double? = nil
    ) {
        self.result = result
        self.counter = counter
        self.sleepSeconds = sleepSeconds
    }

    func fetch(host: String) async throws -> (softwareName: String, softwareVersion: String?) {
        await counter?.bump()
        if let sleepSeconds { try await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000)) }
        return try result.get()
    }
}

private struct FetchBoom: Error { }

struct NodeInfoServiceTests {
    @Test
    func detectsAndCachesOnSuccess() async throws {
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(("lemmy", "0.19.5"))),
            appDatabase: .inMemory()
        )
        let result = await service.detect(host: "Lemmy.World")
        #expect(result == .known(.lemmy, version: "0.19.5"))
    }

    @Test
    func freshCacheHitDoesNotRefetch() async throws {
        let counter = CallCounter()
        let service = try NodeInfoService(
            fetcher: FakeFetcher(.success(("piefed", "1.0")), counter: counter),
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
            fetcher: FakeFetcher(.success(("lemmy", "0.19.5")), counter: counter),
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
            fetcher: FakeFetcher(.success(("lemmy", nil)), sleepSeconds: 10),
            appDatabase: .inMemory(),
            timeout: 0.05
        )
        #expect(await service.detect(host: "slow.example") == .unknown)
    }
}
