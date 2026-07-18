import Foundation
import GRDB
import Testing
@testable import SpudDataKit

/// A settable wall clock for driving `StatsService`'s session/bucket logic.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(interval)
    }
}

struct StatsServiceTests {
    private static func makeService(
        db: AppDatabase,
        clock: FakeClock,
        // Never auto-flush by default; most tests call flush() explicitly.
        flushDelay: Duration = .seconds(3600)
    ) -> StatsService {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return StatsService(
            appDatabase: db,
            now: { clock.now },
            calendar: utc,
            flushDelay: flushDelay,
            sessionGap: 300
        )
    }

    private static func total(_ db: AppDatabase, _ key: FunStatKey) async throws -> Double {
        try await db.writer.read { db in
            try Double.fetchOne(
                db,
                sql: "SELECT sum(value) FROM funStat WHERE key = ?",
                arguments: [key.rawValue]
            ) ?? 0
        }
    }

    @Test
    func record_buffersUntilFlush() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.record(.tapCount, amount: 2)
        let beforeFlush = try await Self.total(db, .tapCount)
        #expect(beforeFlush == 0)

        await sut.flush()
        let afterFlush = try await Self.total(db, .tapCount)
        #expect(afterFlush == 2)
    }

    @Test
    func record_accumulatesAcrossFlushes() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.record(.tapCount, amount: 2)
        await sut.flush()
        await sut.record(.tapCount, amount: 3)
        await sut.flush()
        #expect(try await Self.total(db, .tapCount) == 5)
    }

    @Test
    func record_whenDisabled_isNoOpAndDropsBuffer() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.record(.tapCount, amount: 2) // buffered
        await sut.setEnabled(false) // drops the pending buffer
        await sut.record(.tapCount, amount: 5) // ignored
        await sut.flush()
        #expect(try await Self.total(db, .tapCount) == 0)

        await sut.setEnabled(true)
        await sut.record(.tapCount, amount: 1)
        await sut.flush()
        #expect(try await Self.total(db, .tapCount) == 1)
    }

    @Test
    func session_firstBecomeActive_countsOneSession() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.appDidBecomeActive()
        await sut.flush()
        #expect(try await Self.total(db, .sessionCount) == 1)
    }

    @Test
    func session_quickBounceWithinGap_isOneSession() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.appDidBecomeActive()
        clock.advance(by: 60)
        await sut.appWillResignActive()
        clock.advance(by: 120) // 2 min in background: under the 5 min gap
        await sut.appDidBecomeActive()
        await sut.flush()
        #expect(try await Self.total(db, .sessionCount) == 1)
    }

    @Test
    func session_returnAfterGap_countsNewSession() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.appDidBecomeActive()
        clock.advance(by: 60)
        await sut.appWillResignActive()
        clock.advance(by: 301) // past the 5 min gap
        await sut.appDidBecomeActive()
        await sut.flush()
        #expect(try await Self.total(db, .sessionCount) == 2)
    }

    @Test
    func resignActive_recordsForegroundSecondsAndFlushes() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.appDidBecomeActive()
        clock.advance(by: 90)
        await sut.appWillResignActive() // flushes internally
        #expect(try await Self.total(db, .foregroundSeconds) == 90)
        // sessionCount landed in the same flush
        #expect(try await Self.total(db, .sessionCount) == 1)
    }

    @Test
    func record_autoFlushesAfterDelay() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock, flushDelay: .milliseconds(50))

        await sut.record(.tapCount, amount: 2)
        // No explicit flush(): exercises the production scheduleFlush()/timerFlush()
        // path. Poll with a generous timeout instead of a fixed sleep so the test
        // stays deterministic without being tied to the exact flush delay.
        let deadline = Date().addingTimeInterval(5)
        var total: Double = 0
        while Date() < deadline {
            total = try await Self.total(db, .tapCount)
            if total == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(total == 2)
    }

    @Test
    func resetAllStats_clearsTableAndBuffer() async throws {
        let db = try AppDatabase.inMemory()
        let clock = FakeClock(Date(timeIntervalSince1970: 1_784_410_500))
        let sut = Self.makeService(db: db, clock: clock)

        await sut.record(.tapCount, amount: 2)
        await sut.flush()
        await sut.record(.tapCount, amount: 9) // pending, must not survive reset
        await sut.resetAllStats()
        await sut.flush()
        #expect(try await Self.total(db, .tapCount) == 0)
    }
}
