# Offline Download — Retries and Rate Limiting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an offline feed download survive transient server failures (retry with back-off instead of aborting), pace all requests so it never hammers the instance, and finish with what it got when a page permanently fails after some pages already landed.

**Architecture:** Two small, independently testable components under `SpudDataKit/Services/Offline/` — a `RequestPacer` actor (proactive global request spacing + a reactive cool-down on server pushback) and a `withRetry` helper (bounded jittered exponential back-off that reuses the existing `OutboxFailureClass` classifier). Both are wired into `OfflineDownloadService.run` via a single injected `DownloadPacingConfig` (which also carries the tunables and a test-swappable clock/sleep). The page-fetch loop keeps already-persisted posts on a permanent failure and finishes partial; only a zero-pages failure stays fatal.

**Tech Stack:** Swift 6 (strict concurrency, `complete`), Swift `Duration`/`ContinuousClock`, GRDB, Swift Testing, XcodeGen.

## Global Constraints

- **Language/mode:** Swift 6.0 language mode + `SWIFT_STRICT_CONCURRENCY = complete`. All new types Sendable; injected closures `@Sendable`.
- **Target/layer:** All non-UI code lands in `SpudDataKit` (framework). The UI change (Task 6) is in the `Spud` app target. Frameworks never import the app target.
- **Reuse, do not reinvent:** classification is `OutboxFailureClass.classify(_:isOnline:)` from `SpudDataKit/Services/Outbox/OutboxFailureClass.swift` — do NOT write a second classifier.
- **No emojis** in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`, `test:`, `docs:`).
- **Prefer many small files.** New components each get their own file.
- **XcodeGen:** `project.pbxproj` is generated + gitignored. After creating ANY new file, run `make project` before building, or the file isn't in the target and you get spurious "cannot find in scope".
- **Format before commit:** run `mint run swiftformat <touched files>` before every `git add`. The pre-commit hook runs SwiftFormat in lint mode and will reject unformatted staging.
- **Swift Testing note:** these targets use Swift Testing, not XCTest. Suites are `struct`; tests are `@Test func`. xcodebuild prints "Executed 0 tests" for a Swift-Testing target — look for `✔ Test run with N tests ... passed` and per-test `✔`/`✘` lines. `import Testing` does NOT re-export Foundation — add `import Foundation` where you use `URL`/`Date`/`Duration`.
- **Test run command (SpudDataKitTests), single suite:**
  ```sh
  xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
    -only-testing:SpudDataKitTests/<SuiteName> \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -skipPackagePluginValidation -skipMacroValidation \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 60 test
  ```
  (If a second sim is booted, target the booted one by id — `-destination 'platform=iOS Simulator,id=<UUID>'` from `xcrun simctl list devices | grep Booted`.)
- **Branch:** work on `feat/offline-download-retry-rate-limiting` (already created; the spec is committed there).
- **Spec:** `docs/superpowers/specs/2026-07-04-offline-download-retry-rate-limiting-design.md`.

---

### Task 1: `RequestPacer` actor

Proactive throttle: spaces request kickoffs ≥ `minInterval` apart globally, with a `penalize` cool-down for server pushback. Injected clock/sleep make it deterministic.

**Files:**
- Create: `SpudDataKit/Services/Offline/RequestPacer.swift`
- Test: `SpudDataKitTests/RequestPacerTests.swift`

**Interfaces:**
- Consumes: nothing (leaf component).
- Produces:
  ```swift
  actor RequestPacer {
      init(minInterval: Duration,
           now: @escaping @Sendable () -> ContinuousClock.Instant,
           sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void)
      func acquire() async throws            // waits until this request's slot
      func penalize(_ cooldown: Duration)    // pushes every later slot out by cooldown
  }
  ```

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/RequestPacerTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

/// A controllable clock for `RequestPacer`: `now` advances only when `sleepUntil`
/// is asked to wait, so tests never wait in real time yet observe the exact
/// deadlines the pacer reserved.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ContinuousClock.Instant
    private(set) var reservedDeadlines: [ContinuousClock.Instant] = []
    let base: ContinuousClock.Instant

    init() {
        let start = ContinuousClock().now
        base = start
        current = start
    }

    var now: @Sendable () -> ContinuousClock.Instant {
        { [self] in lock.withLock { current } }
    }

    var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void {
        { [self] deadline in
            lock.withLock {
                reservedDeadlines.append(deadline)
                if deadline > current { current = deadline }
            }
        }
    }
}

@Suite(.serialized)
struct RequestPacerTests {
    @Test
    func firstAcquireDoesNotWaitThenSpacesByInterval() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .milliseconds(200), now: clock.now, sleepUntil: clock.sleepUntil)

        try await pacer.acquire()
        try await pacer.acquire()
        try await pacer.acquire()

        #expect(clock.reservedDeadlines.count == 3)
        // First slot is "now" (no wait); each subsequent slot steps by minInterval.
        #expect(clock.base.duration(to: clock.reservedDeadlines[0]) == .zero)
        #expect(clock.reservedDeadlines[0].duration(to: clock.reservedDeadlines[1]) == .milliseconds(200))
        #expect(clock.reservedDeadlines[1].duration(to: clock.reservedDeadlines[2]) == .milliseconds(200))
    }

    @Test
    func penalizePushesNextSlotOutByCooldown() async throws {
        let clock = ManualClock()
        let pacer = RequestPacer(minInterval: .milliseconds(200), now: clock.now, sleepUntil: clock.sleepUntil)

        try await pacer.acquire()           // slot 0 at base
        await pacer.penalize(.seconds(8))   // next slot must jump to now+8s
        try await pacer.acquire()           // slot 1

        let gap = clock.reservedDeadlines[0].duration(to: clock.reservedDeadlines[1])
        #expect(gap >= .seconds(8), "penalize should push the next slot out by the cooldown")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the Global-Constraints test command with `-only-testing:SpudDataKitTests/RequestPacerTests`.
Expected: FAIL to build ("cannot find 'RequestPacer' in scope").

- [ ] **Step 3: Create `RequestPacer.swift`**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Paces outbound requests for one offline-download run so all workers together
/// never issue requests closer than `minInterval` apart, and a server pushback
/// (429 / 503 / rate-limit) delays every subsequent request by a cool-down.
///
/// The clock (`now`) and the wait (`sleepUntil`) are injected so the pacer is
/// deterministic in tests (a manual clock advances only when asked to wait),
/// mirroring the "time is a parameter" style of `SchedulerBackoff` / `DiagnosticLog`.
///
/// Correctness: `reserve()` — the only actor-isolated step — synchronously bumps
/// `nextPermitAt`; the actual `sleepUntil(deadline)` runs after, NOT while holding
/// the actor, so the pacer never becomes a serial bottleneck for the content
/// phase's concurrent workers.
actor RequestPacer {
    private let minInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    private var nextPermitAt: ContinuousClock.Instant

    init(
        minInterval: Duration,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void
    ) {
        self.minInterval = minInterval
        self.now = now
        self.sleepUntil = sleepUntil
        nextPermitAt = now()
    }

    /// Reserve and wait for this request's slot. The first caller does not wait;
    /// each subsequent caller waits until at least `minInterval` after the prior
    /// slot (and past any active pushback cool-down).
    func acquire() async throws {
        let deadline = reserve()
        try await sleepUntil(deadline)
    }

    /// Push every subsequent permit out by `cooldown` from now — used when the
    /// server signals it wants us to slow down (429 / 503 / rate-limit).
    func penalize(_ cooldown: Duration) {
        let candidate = now().advanced(by: cooldown)
        if candidate > nextPermitAt { nextPermitAt = candidate }
    }

    /// Synchronous, actor-isolated slot reservation. Returns the instant this
    /// request may proceed; advances `nextPermitAt` by `minInterval`.
    private func reserve() -> ContinuousClock.Instant {
        let candidate = now()
        let slot = candidate > nextPermitAt ? candidate : nextPermitAt
        nextPermitAt = slot.advanced(by: minInterval)
        return slot
    }
}
```

- [ ] **Step 4: Regenerate project and run tests to verify they pass**

Run: `make project` then the Task-1 test command.
Expected: `✔ Test run with 2 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/Offline/RequestPacer.swift SpudDataKitTests/RequestPacerTests.swift
git add SpudDataKit/Services/Offline/RequestPacer.swift SpudDataKitTests/RequestPacerTests.swift
git commit -m "feat: add RequestPacer for offline-download request spacing"
```

---

### Task 2: `withRetry` back-off helper

Bounded jittered exponential back-off wrapping one network op, reusing `OutboxFailureClass` and penalizing the pacer on pushback.

**Files:**
- Create: `SpudDataKit/Services/Offline/RequestRetry.swift`
- Test: `SpudDataKitTests/RequestRetryTests.swift`

**Interfaces:**
- Consumes: `RequestPacer` (Task 1); `OutboxFailureClass` (existing); `LemmyServiceError` (SpudDataKit), `LemmyApiError` (LemmyKit).
- Produces:
  ```swift
  func withRetry<T: Sendable>(
      maxAttempts: Int,
      baseDelay: Duration,
      maxDelay: Duration,
      pushbackCooldown: Duration,
      pacer: RequestPacer,
      isOnline: Bool = true,
      sleep: @Sendable (Duration) async throws -> Void,
      jitter: @Sendable (ClosedRange<Double>) -> Double,
      onRetry: @Sendable (_ attempt: Int, _ delay: Duration, _ error: Error) async -> Void = { _, _, _ in },
      operation: () async throws -> T
  ) async throws -> T

  extension Duration { var asTimeInterval: TimeInterval { get } }
  ```

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/RequestRetryTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit
import Testing
@testable import SpudDataKit

@Suite(.serialized)
struct RequestRetryTests {
    // A pacer whose waits are instant (real clock, no-op sleep) so penalize can be
    // observed only via behavior; timing is asserted through the recorded sleeps.
    private func immediatePacer() -> RequestPacer {
        RequestPacer(minInterval: .zero, now: { ContinuousClock().now }, sleepUntil: { _ in })
    }

    private func transient503() -> Error {
        LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 503, error: nil))
    }

    private func permanent403() -> Error {
        LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 403, error: nil))
    }

    @Test
    func retriesTransientThenSucceeds() async throws {
        let recorded = Recorder()
        var calls = 0
        let result = try await withRetry(
            maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
            pushbackCooldown: .seconds(8), pacer: immediatePacer(),
            sleep: { await recorded.append($0) }, jitter: { _ in 1.0 }
        ) {
            calls += 1
            if calls < 3 { throw self.transient503() }
            return "ok"
        }
        #expect(result == "ok")
        #expect(calls == 3)
        // Two retries: full-jitter delays 500ms, 1000ms.
        let delays = await recorded.values
        #expect(delays == [.milliseconds(500), .milliseconds(1000)])
    }

    @Test
    func permanentErrorIsNotRetried() async throws {
        var calls = 0
        await #expect(throws: LemmyServiceError.self) {
            try await withRetry(
                maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: self.immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw self.permanent403()
            }
        }
        #expect(calls == 1, "a permanent error must not retry")
    }

    @Test
    func exhaustsAttemptsThenRethrows() async throws {
        var calls = 0
        await #expect(throws: LemmyServiceError.self) {
            try await withRetry(
                maxAttempts: 3, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: self.immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw self.transient503()
            }
        }
        #expect(calls == 3, "should try exactly maxAttempts times")
    }

    @Test
    func cancellationIsNotRetried() async throws {
        var calls = 0
        await #expect(throws: CancellationError.self) {
            try await withRetry(
                maxAttempts: 4, baseDelay: .milliseconds(500), maxDelay: .seconds(30),
                pushbackCooldown: .seconds(8), pacer: self.immediatePacer(),
                sleep: { _ in }, jitter: { _ in 1.0 }
            ) {
                calls += 1
                throw CancellationError()
            }
        }
        #expect(calls == 1, "cancellation must propagate immediately, no retry")
    }

    private actor Recorder {
        var values: [Duration] = []
        func append(_ d: Duration) { values.append(d) }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run with `-only-testing:SpudDataKitTests/RequestRetryTests`.
Expected: FAIL to build ("cannot find 'withRetry' in scope").

- [ ] **Step 3: Create `RequestRetry.swift`**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import LemmyKit

/// Run `operation`, retrying transient failures (per `OutboxFailureClass`) with
/// bounded jittered exponential back-off. On a server-pushback error
/// (429 / 503 / rate-limit) it also penalizes the shared `pacer` so every other
/// in-flight request observes the cool-down. A permanent error is rethrown
/// immediately; once `maxAttempts` is reached the last error is rethrown.
///
/// Only idempotent reads are wrapped here (feed pages, comment trees, image
/// GETs), so re-running on retry is side-effect-free — unlike the outbox, which
/// guards non-idempotent mutations from re-send.
///
/// - Parameters:
///   - maxAttempts: Total attempts including the first (e.g. 4 = 1 try + 3 retries).
///   - baseDelay: First-retry back-off; doubles each subsequent retry.
///   - maxDelay: Upper bound on the (pre-jitter) back-off.
///   - pushbackCooldown: Applied to `pacer.penalize` on a pushback error.
///   - isOnline: Passed to `OutboxFailureClass.classify`; offline makes everything transient.
///   - sleep: Back-off wait (injected for tests).
///   - jitter: Returns a fraction in the given range; full-jitter scales the delay by it.
///   - onRetry: Notified before each back-off sleep (used to record a diagnostic).
func withRetry<T: Sendable>(
    maxAttempts: Int,
    baseDelay: Duration,
    maxDelay: Duration,
    pushbackCooldown: Duration,
    pacer: RequestPacer,
    isOnline: Bool = true,
    sleep: @Sendable (Duration) async throws -> Void,
    jitter: @Sendable (ClosedRange<Double>) -> Double,
    onRetry: @Sendable (_ attempt: Int, _ delay: Duration, _ error: Error) async -> Void = { _, _, _ in },
    operation: () async throws -> T
) async throws -> T {
    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A cancellation that surfaced as a different error type still means stop.
            try Task.checkCancellation()

            let classification = OutboxFailureClass.classify(error, isOnline: isOnline)
            guard classification == .transient, attempt < maxAttempts else { throw error }

            // Exponential: baseDelay doubled (attempt-1) times, capped, then full-jittered.
            var delay = baseDelay
            for _ in 1 ..< attempt { delay = delay * 2 }
            if delay > maxDelay { delay = maxDelay }
            let jittered = Duration.seconds(delay.asTimeInterval * jitter(0 ... 1))

            await onRetry(attempt, jittered, error)
            if isServerPushback(error) { await pacer.penalize(pushbackCooldown) }
            try await sleep(jittered)
        }
    }
}

/// True for the "please slow down" server signals: HTTP 429 / 503, or a
/// structured `rate_limit*` Lemmy server error. The broader transient set
/// (other 5xx, timeouts, offline) still retries but does not add a global
/// cool-down.
func isServerPushback(_ error: Error) -> Bool {
    switch error {
    case let serviceError as LemmyServiceError:
        if case let .apiError(api) = serviceError { return isServerPushback(api) }
        return false
    case let api as LemmyApiError:
        return isServerPushback(api)
    default:
        return false
    }
}

private func isServerPushback(_ api: LemmyApiError) -> Bool {
    switch api {
    case let .unknownServerError(httpStatusCode, _):
        return httpStatusCode == 429 || httpStatusCode == 503
    case let .serverError(errorResponse):
        return errorResponse.error.hasPrefix("rate_limit")
    default:
        return false
    }
}

extension Duration {
    /// The duration as fractional seconds. Used to scale a delay by a jitter
    /// fraction (Duration has no built-in `* Double`).
    var asTimeInterval: TimeInterval {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1_000_000_000_000_000_000
    }
}
```

- [ ] **Step 4: Regenerate project and run tests to verify they pass**

Run: `make project` then the Task-2 test command.
Expected: `✔ Test run with 4 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/Offline/RequestRetry.swift SpudDataKitTests/RequestRetryTests.swift
git add SpudDataKit/Services/Offline/RequestRetry.swift SpudDataKitTests/RequestRetryTests.swift
git commit -m "feat: add withRetry back-off helper for offline downloads"
```

---

### Task 3: `DownloadPacingConfig` + `warningMessage`

Bundle the tunables (spec §4) and the injectable clock/sleep/jitter into one Sendable config; add the partial-success field to the progress value type.

**Files:**
- Create: `SpudDataKit/Services/Offline/DownloadPacingConfig.swift`
- Modify: `SpudDataKit/Services/Offline/OfflineDownloadProgress.swift` (add `warningMessage`)
- Create: `SpudDataKitTests/DownloadPacingConfigTests.swift`
- Create (test-only): `SpudDataKitTests/Fakes/DownloadPacingConfig+Immediate.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  ```swift
  public struct DownloadPacingConfig: Sendable {
      public var minRequestInterval: Duration
      public var maxRetryAttempts: Int
      public var maxImageRetryAttempts: Int
      public var retryBaseDelay: Duration
      public var retryMaxDelay: Duration
      public var serverPushbackCooldown: Duration
      public var now: @Sendable () -> ContinuousClock.Instant
      public var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
      public var sleep: @Sendable (Duration) async throws -> Void
      public var jitter: @Sendable (ClosedRange<Double>) -> Double
      public static let live: DownloadPacingConfig
  }
  // OfflineDownloadProgress gains: public var warningMessage: String?  (init defaulted nil)
  // Test-only: static func DownloadPacingConfig.immediate(jitter:) -> DownloadPacingConfig
  ```

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/DownloadPacingConfigTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

@Suite
struct DownloadPacingConfigTests {
    @Test
    func liveConfigHasSpecifiedTunables() {
        let c = DownloadPacingConfig.live
        #expect(c.minRequestInterval == .milliseconds(200))
        #expect(c.maxRetryAttempts == 4)
        #expect(c.maxImageRetryAttempts == 2)
        #expect(c.retryBaseDelay == .milliseconds(500))
        #expect(c.retryMaxDelay == .seconds(30))
        #expect(c.serverPushbackCooldown == .seconds(8))
    }

    @Test
    func finishedWithWarningStillCompletesFully() {
        let p = OfflineDownloadProgress(
            phase: .finished, postsFetched: 80, totalPosts: 80, itemsCompleted: 80,
            warningMessage: "Downloaded 80 posts — some of the feed couldn't be reached."
        )
        #expect(p.fractionCompleted == 1)
        #expect(p.warningMessage != nil)
    }

    @Test
    func warningMessageDefaultsNil() {
        let p = OfflineDownloadProgress(phase: .finished, postsFetched: 10, totalPosts: 10, itemsCompleted: 10)
        #expect(p.warningMessage == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run with `-only-testing:SpudDataKitTests/DownloadPacingConfigTests`.
Expected: FAIL to build ("cannot find 'DownloadPacingConfig'"; "extra argument 'warningMessage'").

- [ ] **Step 3a: Create `DownloadPacingConfig.swift`**

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Tunables and injectable time/randomness for one offline-download run's
/// request pacing + retry. `.live` carries the shipping defaults; tests swap in
/// no-wait sleeps and a fixed jitter (see the `immediate` test factory).
public struct DownloadPacingConfig: Sendable {
    /// Minimum spacing between request kickoffs across ALL workers (the proactive throttle).
    public var minRequestInterval: Duration
    /// Total attempts (incl. the first) for a feed-page or comment fetch.
    public var maxRetryAttempts: Int
    /// Total attempts for an image warm — lower, since an image failure carries no
    /// classifiable error (a non-`ready` stream is treated as one transient blip).
    public var maxImageRetryAttempts: Int
    /// First-retry back-off; doubles each retry, capped at `retryMaxDelay`.
    public var retryBaseDelay: Duration
    public var retryMaxDelay: Duration
    /// Global cool-down injected into the pacer on a 429 / 503 / rate-limit.
    public var serverPushbackCooldown: Duration

    public var now: @Sendable () -> ContinuousClock.Instant
    public var sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void
    public var sleep: @Sendable (Duration) async throws -> Void
    public var jitter: @Sendable (ClosedRange<Double>) -> Double

    public init(
        minRequestInterval: Duration,
        maxRetryAttempts: Int,
        maxImageRetryAttempts: Int,
        retryBaseDelay: Duration,
        retryMaxDelay: Duration,
        serverPushbackCooldown: Duration,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        sleepUntil: @escaping @Sendable (ContinuousClock.Instant) async throws -> Void,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        jitter: @escaping @Sendable (ClosedRange<Double>) -> Double
    ) {
        self.minRequestInterval = minRequestInterval
        self.maxRetryAttempts = maxRetryAttempts
        self.maxImageRetryAttempts = maxImageRetryAttempts
        self.retryBaseDelay = retryBaseDelay
        self.retryMaxDelay = retryMaxDelay
        self.serverPushbackCooldown = serverPushbackCooldown
        self.now = now
        self.sleepUntil = sleepUntil
        self.sleep = sleep
        self.jitter = jitter
    }

    /// Shipping defaults (spec §4).
    public static let live = DownloadPacingConfig(
        minRequestInterval: .milliseconds(200),
        maxRetryAttempts: 4,
        maxImageRetryAttempts: 2,
        retryBaseDelay: .milliseconds(500),
        retryMaxDelay: .seconds(30),
        serverPushbackCooldown: .seconds(8),
        now: { ContinuousClock().now },
        sleepUntil: { try await ContinuousClock().sleep(until: $0) },
        sleep: { try await Task.sleep(for: $0) },
        jitter: { Double.random(in: $0) }
    )
}
```

- [ ] **Step 3b: Add `warningMessage` to `OfflineDownloadProgress.swift`**

In `SpudDataKit/Services/Offline/OfflineDownloadProgress.swift`, after the `failureMessage` property (line ~58) add:

```swift
    /// A non-fatal notice about a completed run — e.g. not every feed page could
    /// be reached, so fewer posts were downloaded than requested. Set only on
    /// ``Phase/finished``; nil for a fully-complete run. Distinct from
    /// ``failureMessage`` (fatal): a run with a `warningMessage` still finished,
    /// so ``fractionCompleted`` is 1.
    public var warningMessage: String?
```

Update the initializer to add the parameter (defaulted, last) and assignment:

```swift
    public init(
        phase: Phase,
        postsFetched: Int = 0,
        totalPosts: Int = 0,
        itemsCompleted: Int = 0,
        failureMessage: String? = nil,
        warningMessage: String? = nil
    ) {
        self.phase = phase
        self.postsFetched = postsFetched
        self.totalPosts = totalPosts
        self.itemsCompleted = itemsCompleted
        self.failureMessage = failureMessage
        self.warningMessage = warningMessage
    }
```

(No change to `fractionCompleted`: `.finished` already returns 1.)

- [ ] **Step 3c: Create the test-only `immediate` factory**

Create `SpudDataKitTests/Fakes/DownloadPacingConfig+Immediate.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
@testable import SpudDataKit

extension DownloadPacingConfig {
    /// A pacing config whose waits are instant (no real time passes) and whose
    /// jitter is fixed, so download tests assert OUTCOMES without waiting. Keeps
    /// the same retry/attempt counts as `.live` so retry behavior is realistic.
    static func immediate(
        jitter: @escaping @Sendable (ClosedRange<Double>) -> Double = { _ in 1.0 }
    ) -> DownloadPacingConfig {
        DownloadPacingConfig(
            minRequestInterval: .zero,
            maxRetryAttempts: 4,
            maxImageRetryAttempts: 2,
            retryBaseDelay: .milliseconds(500),
            retryMaxDelay: .seconds(30),
            serverPushbackCooldown: .seconds(8),
            now: { ContinuousClock().now },
            sleepUntil: { _ in },
            sleep: { _ in },
            jitter: jitter
        )
    }
}
```

- [ ] **Step 4: Regenerate project and run tests to verify they pass**

Run: `make project` then the Task-3 test command.
Expected: `✔ Test run with 3 tests ... passed`.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/Offline/DownloadPacingConfig.swift SpudDataKit/Services/Offline/OfflineDownloadProgress.swift SpudDataKitTests/DownloadPacingConfigTests.swift SpudDataKitTests/Fakes/DownloadPacingConfig+Immediate.swift
git add SpudDataKit/Services/Offline/DownloadPacingConfig.swift SpudDataKit/Services/Offline/OfflineDownloadProgress.swift SpudDataKitTests/DownloadPacingConfigTests.swift SpudDataKitTests/Fakes/DownloadPacingConfig+Immediate.swift
git commit -m "feat: add DownloadPacingConfig + partial-success warningMessage"
```

---

### Task 4: Phase 1 — paced + retried page fetch with partial success

Wire the pacer + retry into `fetchPages`; keep already-persisted pages when a page permanently fails; carry the partial notice to the `.finished` terminal. Extend the test fake to script page failures.

**Files:**
- Modify: `SpudDataKit/Services/Offline/OfflineDownloadService.swift` (add `pacing` init param + stored prop; build the per-run pacer in `run`; wrap `fetchFeed`; change `fetchPages` return; partial/terminal handling; `download.retry` + `download.pageFetchIncomplete` diagnostics)
- Modify: `SpudDataKitTests/Fakes/RecordingLemmyService.swift` (per-page `transientFailures` / `permanentFailure`)
- Modify: `SpudDataKitTests/OfflineDownloadServiceTests.swift` (new tests + pass `pacing: .immediate()`)

**Interfaces:**
- Consumes: `RequestPacer` (Task 1), `withRetry` (Task 2), `DownloadPacingConfig` (Task 3), `OfflineDownloadProgress.warningMessage` (Task 3), `OutboxFailureClass`.
- Produces:
  ```swift
  // OfflineDownloadService.init gains a defaulted `pacing: DownloadPacingConfig = .live`
  // fetchPages now returns (count: Int, wasPartial: Bool)
  // RecordingLemmyService.Page gains: transientFailures: Int = 0, permanentFailure: Bool = false
  ```

- [ ] **Step 1: Extend the test fake `RecordingLemmyService`**

In `SpudDataKitTests/Fakes/RecordingLemmyService.swift`:

Add two fields to `struct Page` and update its `init`:

```swift
        /// Throw a transient (HTTP 503) error this many times for this page
        /// before it actually seeds — models a page that fails then recovers.
        let transientFailures: Int
        /// When true, every `fetchFeed` for this page throws a permanent (HTTP 403)
        /// error and never seeds — models a page that fails for good.
        let permanentFailure: Bool

        init(
            postCount: Int,
            nextCursor: String?,
            duplicatePostIds: [Int64] = [],
            transientFailures: Int = 0,
            permanentFailure: Bool = false
        ) {
            self.postCount = postCount
            self.nextCursor = nextCursor
            self.duplicatePostIds = duplicatePostIds
            self.transientFailures = transientFailures
            self.permanentFailure = permanentFailure
        }
```

Add a per-page transient counter as a stored actor property (near `pageIndex`):

```swift
    /// Remaining scripted transient failures for the CURRENT page, lazily seeded
    /// from `Page.transientFailures` the first time the page is reached.
    private var currentPageTransientRemaining: Int?
```

In `fetchFeed`, after `let page = pages[pageIndex]` (i.e. after the `guard pageIndex < pages.count` block, replacing the current `let page = pages[pageIndex]` / `pageIndex += 1` lines) insert the failure scripting BEFORE `pageIndex += 1`:

```swift
        let page = pages[pageIndex]

        // Scripted permanent failure: throw every time; never advance or seed.
        if page.permanentFailure {
            throw LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 403, error: nil))
        }

        // Scripted transient failures: throw N times (503), then fall through to
        // seed on the next call. Do NOT advance `pageIndex` until it seeds.
        if currentPageTransientRemaining == nil {
            currentPageTransientRemaining = page.transientFailures
        }
        if let remaining = currentPageTransientRemaining, remaining > 0 {
            currentPageTransientRemaining = remaining - 1
            throw LemmyServiceError.apiError(.unknownServerError(httpStatusCode: 503, error: nil))
        }
        currentPageTransientRemaining = nil

        pageIndex += 1
```

(Everything below `pageIndex += 1` — the seeding — is unchanged.)

- [ ] **Step 2: Write the failing tests**

In `SpudDataKitTests/OfflineDownloadServiceTests.swift`, first make the two shared helpers pass the immediate pacing config so ALL existing tests stop waiting in real time. Change every `OfflineDownloadService(appDatabase: ..., imageService: ..., diagnostics: DiagnosticLogSpy())` construction to append `, pacing: .immediate()`. (Do this with a find/replace of `diagnostics: DiagnosticLogSpy())` → `diagnostics: DiagnosticLogSpy(), pacing: .immediate())`, and the multi-arg `diagnostics: DiagnosticLogSpy(),` block constructions similarly.)

Then add these tests to the suite:

```swift
    /// A page that fails transiently (503) twice then succeeds must NOT abort the
    /// download — the retry absorbs the blip and the run finishes normally.
    @Test
    func transientPageFailureIsRetried() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            .init(postCount: 5, nextCursor: nil, transientFailures: 2),
        ])
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a retried transient failure must not fail the run")
        #expect(terminal.warningMessage == nil, "a fully-recovered run has no partial notice")
        #expect(terminal.totalPosts == 10)
        #expect(!diagnostics.events(matching: "download.retry").isEmpty)
    }

    /// A page that fails PERMANENTLY after an earlier page already landed must keep
    /// the persisted posts, run the content phase over them, and finish partial.
    @Test
    func permanentPageFailureAfterFirstPageFinishesPartial() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 5, nextCursor: "p2"),
            .init(postCount: 0, nextCursor: nil, permanentFailure: true),
        ])
        let diagnostics = DiagnosticLogSpy()
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: diagnostics, pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "partial success is a finished run, not a failure")
        #expect(terminal.warningMessage != nil, "a partial run carries a warning notice")
        #expect(terminal.totalPosts == 5, "content phase runs over the 5 kept posts")
        #expect(terminal.itemsCompleted == 5)
        #expect(!diagnostics.events(matching: "download.pageFetchIncomplete").isEmpty)
    }

    /// The VERY FIRST page failing permanently (zero posts persisted) is still a
    /// fatal `.failed` — there is nothing to keep.
    @Test
    func permanentFirstPageFailureFailsRun() async throws {
        let lemmy = makeLemmy(pages: [
            .init(postCount: 0, nextCursor: nil, permanentFailure: true),
        ])
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(), pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .failed)
        #expect(terminal.failureMessage != nil)
    }
```

`DiagnosticLogSpy` (`SpudDataKitTests/Helpers/DiagnosticLogSpy.swift`) is a synchronous `final class` exposing `func events(matching: String) -> [Recorded]` (and `var recordedEvents: [Recorded]`, element `.event: String`) — no `await`, so the assertions above use `diagnostics.events(matching:)` directly.

- [ ] **Step 3: Run tests to verify they fail**

Run with `-only-testing:SpudDataKitTests/OfflineDownloadServiceTests`.
Expected: FAIL to build (init has no `pacing:` parameter) or FAIL assertions.

- [ ] **Step 4: Implement Phase 1 integration**

In `SpudDataKit/Services/Offline/OfflineDownloadService.swift`:

**4a.** Add a stored property + init parameter. After `private let diagnostics: DiagnosticLogging` add:

```swift
    /// Request pacing + retry tunables and injectable clock/sleep for one run's
    /// downloads. Defaults to `.live`; tests inject `.immediate()` to run without
    /// waiting.
    private let pacing: DownloadPacingConfig
```

In `init`, add `pacing: DownloadPacingConfig = .live` as the last parameter and `self.pacing = pacing` at the end of the body.

**4b.** Build the pacer in `run`, right after `let startedAt = Date()`:

```swift
        // One pacer per run, shared by the page loop and every content worker, so
        // all requests to this instance are spaced globally and a server pushback
        // cools the whole run down.
        let pacer = RequestPacer(
            minInterval: pacing.minRequestInterval,
            now: pacing.now,
            sleepUntil: pacing.sleepUntil
        )
```

**4c.** Change the `fetchPages` call + catch in `run` (the `do/catch` at lines ~342-378). Replace the `let postsFetched: Int` / `do { postsFetched = try await fetchPages(...) }` with:

```swift
        let postsFetched: Int
        let wasPartial: Bool
        do {
            let result = try await fetchPages(
                feed: feed,
                lemmyService: lemmyService,
                showNsfw: showNsfw,
                maxPosts: maxPosts,
                pacer: pacer,
                instance: instance,
                emit: emit
            )
            postsFetched = result.count
            wasPartial = result.wasPartial
        } catch is CancellationError {
            // unchanged .cancelled emit (keep the existing body)
            ...
            return
        } catch {
            // unchanged .failed emit (keep the existing body)
            ...
            return
        }
```

(Keep the two existing catch bodies verbatim — only the `do` body and the added `wasPartial` change.)

**4d.** Change `fetchPages`'s signature + body. New signature:

```swift
    private func fetchPages(
        feed: FeedHandle,
        lemmyService: any LemmyServiceType,
        showNsfw: Bool,
        maxPosts: Int,
        pacer: RequestPacer,
        instance: String?,
        emit: @Sendable (OfflineDownloadProgress) -> Void
    ) async throws -> (count: Int, wasPartial: Bool) {
```

Inside the `repeat` loop, replace the direct `let nextCursor = try await lemmyService.fetchFeed(...)` with a paced, retried, partial-aware block:

```swift
            let nextCursor: String?
            do {
                let diagnostics = self.diagnostics
                nextCursor = try await withRetry(
                    maxAttempts: pacing.maxRetryAttempts,
                    baseDelay: pacing.retryBaseDelay,
                    maxDelay: pacing.retryMaxDelay,
                    pushbackCooldown: pacing.serverPushbackCooldown,
                    pacer: pacer,
                    sleep: pacing.sleep,
                    jitter: pacing.jitter,
                    onRetry: { attempt, delay, error in
                        await diagnostics.record(
                            category: .offlineDownload,
                            level: .notice,
                            event: "download.retry",
                            message: "Retrying feed page fetch",
                            instance: instance,
                            metadata: [
                                "attempt": String(attempt),
                                "delayMs": String(Int(delay.asTimeInterval * 1000)),
                                "error": String(describing: error),
                            ]
                        )
                    }
                ) {
                    try await pacer.acquire()
                    return try await lemmyService.fetchFeed(feed, pageCursor: cursor, showNsfw: showNsfw)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Transient retries exhausted, or a permanent error. Keep whatever
                // pages already landed and finish partial; only zero pages is fatal.
                if persistedCount > 0 {
                    await diagnostics.record(
                        category: .offlineDownload,
                        level: .notice,
                        event: "download.pageFetchIncomplete",
                        message: "Feed paging stopped early on a permanent error; keeping fetched posts",
                        instance: instance,
                        metadata: [
                            "postsKept": String(persistedCount),
                            "error": String(describing: error),
                        ]
                    )
                    return (count: persistedCount, wasPartial: true)
                }
                throw error
            }
```

(`return persistedCount` at the very end of the method becomes `return (count: persistedCount, wasPartial: false)`.)

**4e.** Set the partial notice on the terminal `.finished` emit (lines ~465-470):

```swift
        emit(OfflineDownloadProgress(
            phase: .finished,
            postsFetched: postsFetched,
            totalPosts: totalPosts,
            itemsCompleted: completed,
            warningMessage: wasPartial
                ? "Downloaded \(postsFetched) posts — some of the feed couldn't be reached."
                : nil
        ))
```

(Plain-string message, matching the existing plain `failureMessage` style in this file.)

Note: `run` also passes `pacer` into `downloadContent` in Task 5; for THIS task, `downloadContent`'s call is unchanged and Phase 2 stays un-paced/un-retried (still best-effort). Task 5 threads the pacer in.

- [ ] **Step 5: Regenerate project and run tests to verify they pass**

Run: `make project` then the Task-4 test command (whole `OfflineDownloadServiceTests` suite, so the pre-existing tests still pass with `.immediate()`).
Expected: all existing tests + the 3 new tests pass.

- [ ] **Step 6: Commit**

```bash
mint run swiftformat SpudDataKit/Services/Offline/OfflineDownloadService.swift SpudDataKitTests/Fakes/RecordingLemmyService.swift SpudDataKitTests/OfflineDownloadServiceTests.swift
git add SpudDataKit/Services/Offline/OfflineDownloadService.swift SpudDataKitTests/Fakes/RecordingLemmyService.swift SpudDataKitTests/OfflineDownloadServiceTests.swift
git commit -m "feat: retry + pace offline feed-page fetch, keep partial on permanent failure"
```

---

### Task 5: Phase 2 — paced + retried per-post content (best-effort)

Thread the pacer into the content phase; retry transient comment/image failures while keeping the per-item best-effort contract. Make image warming throw a sentinel on a non-`ready` stream so it flows through `withRetry`.

**Files:**
- Modify: `SpudDataKit/Services/Offline/OfflineDownloadService.swift` (`downloadContent` + `processTarget` gain `pacer`/`pacing`; `drainImageFetch` throws; new `warmImage` wrapper)
- Modify: `SpudDataKitTests/OfflineDownloadServiceTests.swift` (comment-retry test)

**Interfaces:**
- Consumes: `RequestPacer`, `withRetry`, `DownloadPacingConfig` (Tasks 1-3); `RecordingLemmyService.failingCommentPostIds` (existing) — note it throws a NON-classified error (`RecordingLemmyServiceError.commentFetchFailed`), which `OutboxFailureClass.classify` maps to `.transient` (default branch), so a permanently-failing comment id will retry `maxRetryAttempts` times then be swallowed. Tests assert call COUNT to prove retry.
- Produces: none consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Add to `OfflineDownloadServiceTests`:

```swift
    /// A comment fetch that fails is now retried before being swallowed: with a
    /// permanently-failing comment id, the fake sees `maxRetryAttempts` calls for
    /// that post (not one), and the run still finishes (best-effort per item).
    @Test
    func commentFetchIsRetriedThenSwallowed() async throws {
        let lemmy = makeLemmy(
            pages: [.init(postCount: 1, nextCursor: nil)],
            failingCommentPostIds: [1]
        )
        let service = OfflineDownloadService(
            appDatabase: appDatabase, imageService: RecordingImageService(),
            diagnostics: DiagnosticLogSpy(), pacing: .immediate()
        )

        let progress = await runDownload(service: service, lemmy: lemmy)

        let terminal = try #require(progress.last)
        #expect(terminal.phase == .finished, "a failing comment must not fail the run")
        #expect(terminal.itemsCompleted == 1, "the post still counts as completed (best-effort)")

        // Post id 1 was retried: attempts == maxRetryAttempts, all recorded.
        let commentCalls = await lemmy.recordedFetchCommentsPostIds().filter { $0 == 1 }
        #expect(commentCalls.count == DownloadPacingConfig.immediate().maxRetryAttempts)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:SpudDataKitTests/OfflineDownloadServiceTests`.
Expected: the new test FAILS — `commentCalls.count == 1` (no retry yet), not `maxRetryAttempts`.

- [ ] **Step 3: Implement Phase 2 integration**

In `OfflineDownloadService.swift`:

**3a.** `run` passes the pacer into `downloadContent`. In the `let (completed, failed) = await downloadContent(...)` call, add `pacer: pacer,` and `pacing: pacing,` arguments.

**3b.** `downloadContent` signature gains `pacer: RequestPacer` and `pacing: DownloadPacingConfig`; it forwards both into the `Self.processTarget(...)` call inside `addNextIfPossible()` (add `pacer: pacer, pacing: pacing,` to that call).

**3c.** `processTarget` signature gains `pacer: RequestPacer` and `pacing: DownloadPacingConfig` (add them to the parameter list). Wrap the comment fetch:

```swift
        var commentSucceeded = true
        do {
            try await withRetry(
                maxAttempts: pacing.maxRetryAttempts,
                baseDelay: pacing.retryBaseDelay,
                maxDelay: pacing.retryMaxDelay,
                pushbackCooldown: pacing.serverPushbackCooldown,
                pacer: pacer,
                sleep: pacing.sleep,
                jitter: pacing.jitter
            ) {
                try await pacer.acquire()
                try await lemmyService.fetchComments(
                    serverPostId: Components.Schemas.PostID(target.serverPostId),
                    sortType: commentSort
                )
            }
        } catch {
            commentSucceeded = false
        }
```

Replace the two `await drainImageFetch(imageService, url: ..., downsampleTo: ...)` calls with `warmImage`:

```swift
        if let thumbnailUrl = target.thumbnailUrl {
            await Self.warmImage(imageService, url: thumbnailUrl, downsampleTo: thumbnailDownsampleSize, pacer: pacer, pacing: pacing)
        }
        if Task.isCancelled { return true }
        if let imageUrl = target.imageUrl {
            await Self.warmImage(imageService, url: imageUrl, downsampleTo: fullImageDownsampleSize, pacer: pacer, pacing: pacing)
        }
```

**3d.** Make `drainImageFetch` throw on a non-`ready` stream and add the `warmImage` best-effort wrapper. Replace the existing `drainImageFetch` with:

```swift
    /// Thrown when an image stream completes without ever reaching `.ready`
    /// (a transient warm failure). Lets a warm flow through `withRetry`, which
    /// treats it as transient (`OutboxFailureClass.classify` default).
    private enum OfflineImageFetchError: Error { case notReady }

    /// Drive `imageService.fetch` to completion so the bytes land in the durable
    /// disk cache. Throws ``OfflineImageFetchError/notReady`` if the stream ends
    /// without a `.ready` state (image failed), so the caller can retry.
    private static func drainImageFetch(
        _ imageService: any ImageServiceType,
        url: URL,
        downsampleTo size: CGSize
    ) async throws {
        var sawReady = false
        for await state in imageService.fetch(url, downsampleTo: size) {
            try Task.checkCancellation()
            if case .ready = state { sawReady = true }
        }
        if !sawReady { throw OfflineImageFetchError.notReady }
    }

    /// Best-effort image warm: paced + retried (a lower attempt bound, since an
    /// image failure carries no classifiable error), swallowing the final failure
    /// so one bad image never affects the post's completion — matching the
    /// pre-existing best-effort contract.
    private static func warmImage(
        _ imageService: any ImageServiceType,
        url: URL,
        downsampleTo size: CGSize,
        pacer: RequestPacer,
        pacing: DownloadPacingConfig
    ) async {
        do {
            try await withRetry(
                maxAttempts: pacing.maxImageRetryAttempts,
                baseDelay: pacing.retryBaseDelay,
                maxDelay: pacing.retryMaxDelay,
                pushbackCooldown: pacing.serverPushbackCooldown,
                pacer: pacer,
                sleep: pacing.sleep,
                jitter: pacing.jitter
            ) {
                try await pacer.acquire()
                try await drainImageFetch(imageService, url: url, downsampleTo: size)
            }
        } catch {
            // Best-effort: swallow (incl. CancellationError — the content loop's
            // own `Task.isCancelled` checks drive the .cancelled terminal).
        }
    }
```

- [ ] **Step 4: Regenerate project and run tests to verify they pass**

Run: `make project` then the Task-5 test command (whole suite).
Expected: all pass, including `commentFetchIsRetriedThenSwallowed`.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat SpudDataKit/Services/Offline/OfflineDownloadService.swift SpudDataKitTests/OfflineDownloadServiceTests.swift
git add SpudDataKit/Services/Offline/OfflineDownloadService.swift SpudDataKitTests/OfflineDownloadServiceTests.swift
git commit -m "feat: retry + pace per-post comment and image warming (best-effort)"
```

---

### Task 6: Surface the partial-success notice in the UI

Show `warningMessage` on the completed progress sheet instead of "Done".

**Files:**
- Modify: `Spud/Scenes/PostList/OfflineDownload/OfflineDownloadProgressViewModel.swift`
- Test: add a suite to `SpudTests` (app-target unit tests) — `SpudTests/OfflineDownloadProgressViewModelTests.swift`

**Interfaces:**
- Consumes: `OfflineDownloadProgress.warningMessage` (Task 3).
- Produces: none.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/OfflineDownloadProgressViewModelTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

@MainActor
@Suite
struct OfflineDownloadProgressViewModelTests {
    @Test
    func finishedWithWarningShowsTheWarning() {
        let vm = OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(
                phase: .finished, postsFetched: 80, totalPosts: 80, itemsCompleted: 80,
                warningMessage: "Downloaded 80 posts — some of the feed couldn't be reached."
            ),
            onCancel: {}
        )
        #expect(vm.statusText == "Downloaded 80 posts — some of the feed couldn't be reached.")
    }

    @Test
    func finishedWithoutWarningShowsDone() {
        let vm = OfflineDownloadProgressViewModel(
            progress: OfflineDownloadProgress(phase: .finished, postsFetched: 10, totalPosts: 10, itemsCompleted: 10),
            onCancel: {}
        )
        #expect(vm.statusText == "Done")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/OfflineDownloadProgressViewModelTests -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `statusText` returns "Done" even with a warning.

- [ ] **Step 3: Implement**

In `OfflineDownloadProgressViewModel.swift`, replace the `.finished` case of `statusText`:

```swift
        case .finished:
            if let warning = progress.warningMessage {
                return warning
            }
            return NSLocalizedString(
                "Done",
                comment: "Offline download status line when finished"
            )
```

- [ ] **Step 4: Regenerate project and run test to verify it passes**

Run: `make project` then the Task-6 test command.
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
mint run swiftformat Spud/Scenes/PostList/OfflineDownload/OfflineDownloadProgressViewModel.swift SpudTests/OfflineDownloadProgressViewModelTests.swift
git add Spud/Scenes/PostList/OfflineDownload/OfflineDownloadProgressViewModel.swift SpudTests/OfflineDownloadProgressViewModelTests.swift
git commit -m "feat: show partial-download notice on the offline progress sheet"
```

---

### Task 7: Documentation

Update the feature doc + README index per docs discipline.

**Files:**
- Modify: `docs/features/offline-download.md`
- Modify: `docs/features/README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Update `docs/features/offline-download.md`**

In "Behavior and rules", replace the "Best-effort per post" and "Polite to the instance" bullets with:

```markdown
- **Best-effort per post.** A single post whose comments, image, or linked page fail to download doesn't abort the rest — the download continues and completes with what it could fetch. A transient failure (a timeout or a server "busy"/"slow down") is retried a few times with a growing back-off before the post is given up on.
- **Survives a bad patch, keeps what it got.** If a feed page keeps failing even after retries, the download stops paging but keeps every post it already saved, downloads their content, and finishes — telling you it couldn't reach the whole feed (e.g. "Downloaded 80 posts — some of the feed couldn't be reached.") rather than throwing everything away. Only a failure on the very first page (nothing saved yet) reports an outright failure.
- **Polite to the instance.** Requests are spaced out so a download never floods the server, comment/image fetches run with a small concurrency limit rather than all at once, and web-page snapshots are captured one at a time. When the server signals it's overloaded (HTTP 429/503), the download briefly backs the whole run off before continuing.
```

In "Scenarios", add:

```markdown
### A flaky connection during a download

- **Given** a download that has already saved some of the feed
- **When** a later page keeps failing even after automatic retries
- **Then** the download stops paging but keeps and finishes the posts it already saved
- **And** the progress sheet completes with a notice that not all of the feed could be reached (not an error that discards everything)
```

Keep `Status: shipped`. (No `.swift` links.)

- [ ] **Step 2: Update `docs/features/README.md`**

Replace the offline-download capability-table row (line ~66) with:

```markdown
| [Download a feed for offline browsing](offline-download.md) | `iphone`, `ipad` | shipped — choose 100/250/500 posts; predownload posts + comments + images (+ optional linked-page web archives read in an in-app offline reader) from the feed config popover, with progress + cancel; paced + retried requests (back-off on transient/pushback errors) and partial-success (keeps what it got when a page permanently fails) |
```

Replace the by-area map line (line ~130) tail to append the resilience note:

```markdown
- [x] Download a feed for offline browsing — "Download for offline" in the feed config popover opens a chooser (100/250/500 posts; optional "save linked web pages") then bulk-saves posts + comments + images into the local store + durable image cache (+ external-link web archives, read offline in an in-app WKWebView reader); progress sheet + cancel; requests are paced and retried with back-off (and back off further on a 429/503), and a page that permanently fails after some pages landed finishes partial rather than aborting; offline, the GRDB-first feed/detail browse from the saved copy (offline-download.md)
```

- [ ] **Step 3: Commit**

```bash
git add docs/features/offline-download.md docs/features/README.md
git commit -m "docs: offline-download retries, pacing, and partial-success behavior"
```

---

## Self-Review

**Spec coverage:**
- Proactive throttle → Task 1 (`RequestPacer`), wired in Task 4 (page) + Task 5 (content). ✓
- Reactive back-off + pushback cool-down → Task 2 (`withRetry` + `isServerPushback` → `pacer.penalize`). ✓
- Reuse `OutboxFailureClass` → Task 2 (no new classifier). ✓
- Partial success (keep pages, finish; zero-pages fails) → Task 4. ✓
- `warningMessage` terminal notice → Task 3 (field) + Task 4 (set) + Task 6 (UI). ✓
- Content-phase retries, best-effort → Task 5. ✓
- Web-archive stays out of the pacer → untouched in Task 5 (only comment + image calls wrapped). ✓
- Idempotent-reads rationale → documented in `RequestRetry.swift` doc comment (Task 2). ✓
- Tunables (spec §4) → Task 3 (`DownloadPacingConfig.live`). ✓
- Diagnostics `download.retry` / `download.pageFetchIncomplete` → Task 4. ✓
- Tests with injected clock/sleep/jitter → Tasks 1, 2, 4, 5. ✓
- Docs → Task 7. ✓
- Non-goal (no adaptive concurrency, no shared executor, no migration, `isOnline: true`) → honored (nothing builds them). ✓

**Type consistency:** `RequestPacer.acquire()`/`penalize(_:)`, `withRetry(...)` arg list, `DownloadPacingConfig` field names, `fetchPages -> (count:wasPartial:)`, `OfflineDownloadProgress.warningMessage`, `RecordingLemmyService.Page.transientFailures`/`permanentFailure` are used identically across tasks. ✓

**Placeholder scan:** every code step shows complete code; test commands + expected outcomes given. The two `run` catch bodies in Task 4c are marked "keep verbatim" (they are unchanged existing code, shown in the current file at lines 351-378) rather than re-pasted, to avoid the engineer copying a subtly-altered version. ✓

**Confirmed prerequisites (no guesswork left):** `DiagnosticLogSpy.events(matching:)` exists and is synchronous; `RecordingLemmyService`/`RecordingImageService`/`DiagnosticLogSpy` are the fakes in use; `OutboxFailureClass.classify` maps 503→transient / 403→permanent / unknown-error→transient (default); `ImageServiceType.fetch` yields `ImageLoadingState` (`.ready`/`.loading`/`.failure`), never throws.
