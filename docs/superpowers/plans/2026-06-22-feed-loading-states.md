# Feed Loading States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the post-list feed clearly tell the user whether it is loading, slow, offline, unreachable, hit a Spud bug, or empty — and never shimmer forever.

**Architecture:** Add shared, pure, testable pieces in SpudDataKit/SpudUtilKit — a `LoadFailure` classifier, a `ReachabilityMonitoring` service, and a `withTimeout` helper. `PostListViewModel` exposes a single `FeedLoadState` enum (plus a small `PaginationState`) driven by a timeout-wrapped fetch with an escalating "slow" hint; `PostListViewController` renders from those two enums via a reusable `FeedStatePresenter`. The hard timeout is enforced app-side so no LemmyKit change is needed.

**Tech Stack:** Swift 6, UIKit, GRDB, Observation, Network framework (`NWPathMonitor`), XCTest. Design doc: `docs/superpowers/specs/2026-06-22-feed-loading-states-design.md`.

## Global Constraints

- Swift 6.0 language mode, `SWIFT_STRICT_CONCURRENCY = complete`. All new code in Spud / SpudDataKit / SpudUtilKit must build clean under strict concurrency.
- No emojis in code, comments, docs, or commit messages.
- Conventional commit subjects (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`). Append this footer to every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013VpLgVHWNrGruqVhwbvVuP
  ```
- Module placement: `LoadFailure` + `ReachabilityMonitoring` in **SpudDataKit**; `withTimeout` + `Broadcaster` in **SpudUtilKit**; `FeedStatePresenter`, `PostListViewModel`, `PostListViewController` changes in the **Spud app target**. Frameworks must not import the app target.
- After creating or deleting any source file, run `make project` (XcodeGen) before building — a stale `.xcodeproj` yields spurious "Cannot find symbol" errors.
- Build/test with `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test` (or `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`). Snapshot tests run on **iPhone 14 Pro, portrait**.
- Test framework is **XCTest** (`@MainActor final class …: XCTestCase`, `func test*`, `XCTAssert*`). No Swift Testing in these targets.
- All user-facing strings via `NSLocalizedString(_, comment:)`.
- Thresholds (exact): slow-hint **8 seconds**, hard cap **25 seconds**. Both injectable for tests.
- Staging: never `git add -A`; stage explicit paths. Use `git status -uall` to see untracked files (the repo is configured `showUntrackedFiles=no`). Never stage `.remember/remember.md`.
- Branch: `feat/feed-loading-states` (already created).

## File Structure

- `SpudUtilKit/Concurrency/WithTimeout.swift` (new) — `withTimeout(_:operation:)` + `TimeoutError`.
- `SpudUtilKit/Broadcaster.swift` (new) — `Broadcaster<Value>` moved out of `UserDefaultsBacked.swift` and made `public`.
- `SpudUtilKit/UserDefaultsBacked.swift` (modify) — delete the private `Broadcaster`, use the shared one.
- `SpudDataKit/Services/Lemmy/LoadFailure.swift` (new) — `LoadFailure` + `classify`.
- `SpudDataKit/Services/Reachability/ReachabilityMonitoring.swift` (new) — protocol + `HasReachabilityMonitor` + `StaticReachabilityMonitor`.
- `SpudDataKit/Services/Reachability/ReachabilityMonitor.swift` (new) — `NWPathMonitor`-backed concrete impl.
- `Spud/App/DependencyContainer.swift` (modify) — register `reachabilityMonitor`.
- `Spud/Scenes/Common/FeedStatePresenter.swift` (new) — `FeedErrorDescriptor` + `FeedStatePresenter`.
- `Spud/Scenes/PostList/PostListViewModel.swift` (modify) — `FeedLoadState`, `PaginationState`, fetch seam, timeout, slow-hint, classify.
- `Spud/Scenes/PostList/PostListViewController.swift` (modify) — render from the two enums; pagination retry footer; reconnect auto-retry.
- `Spud/Scenes/PostList/FeedLoadingSkeletonView.swift` (modify) — optional "slow" caption.
- `Spud/Scenes/Common/PaginationErrorFooterCell.swift` (new) — "Couldn't load more — Retry" cell.
- Tests: `SpudUtilKitTests/WithTimeoutTests.swift`, `SpudUtilKitTests/BroadcasterTests.swift`, `SpudDataKitTests/LoadFailureTests.swift`, `SpudTests/FeedStatePresenterTests.swift`, `SpudTests/PostListViewModelLoadStateTests.swift`, and snapshot refs in `SpudSnapshotTests`.

---

### Task 1: `withTimeout` helper (SpudUtilKit)

**Files:**
- Create: `SpudUtilKit/Concurrency/WithTimeout.swift`
- Test: `SpudUtilKitTests/WithTimeoutTests.swift`

**Interfaces:**
- Produces: `public struct TimeoutError: Error, Equatable {}` and `public func withTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T`. Throws `TimeoutError` if `operation` does not complete within `duration`; otherwise returns its value (and cancels the timer).

- [ ] **Step 1: Write the failing test**

Create `SpudUtilKitTests/WithTimeoutTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudUtilKit

final class WithTimeoutTests: XCTestCase {
    func testReturnsValueWhenOperationFinishesInTime() async throws {
        let value = try await withTimeout(.seconds(10)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testThrowsTimeoutErrorWhenOperationIsTooSlow() async {
        do {
            _ = try await withTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(10))
                return 0
            }
            XCTFail("expected TimeoutError")
        } catch {
            XCTAssertEqual(error as? TimeoutError, TimeoutError())
        }
    }

    func testRethrowsOperationError() async {
        struct Boom: Error, Equatable {}
        do {
            _ = try await withTimeout(.seconds(10)) { throw Boom() }
            XCTFail("expected Boom")
        } catch {
            XCTAssertEqual(error as? Boom, Boom())
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUtilKitTests/WithTimeoutTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — "cannot find 'withTimeout' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `SpudUtilKit/Concurrency/WithTimeout.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Thrown by `withTimeout(_:operation:)` when `operation` does not finish
/// within the allotted duration.
public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Runs `operation`, throwing `TimeoutError` if it does not complete within
/// `duration`. On either outcome the losing child task is cancelled, so a
/// cooperative `operation` stops promptly on timeout.
public func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        // The first child to finish wins; `next()` rethrows TimeoutError if the
        // timer fired first, or the operation's value/error otherwise.
        guard let result = try await group.next() else {
            throw TimeoutError()
        }
        return result
    }
}
```

- [ ] **Step 4: Run make project and the test**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUtilKitTests/WithTimeoutTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudUtilKit/Concurrency/WithTimeout.swift SpudUtilKitTests/WithTimeoutTests.swift
git commit  # subject: "feat: add withTimeout structured-concurrency helper" + required footer
```

---

### Task 2: Make `Broadcaster` reusable (SpudUtilKit)

**Files:**
- Create: `SpudUtilKit/Broadcaster.swift`
- Modify: `SpudUtilKit/UserDefaultsBacked.swift:110-151` (remove the private `Broadcaster`)
- Test: `SpudUtilKitTests/BroadcasterTests.swift`

**Interfaces:**
- Produces: `public final class Broadcaster<Value: Sendable>: @unchecked Sendable` with `init(_ initial: Value)`, `var current: Value`, `func send(_ value: Value)`, `func subscribe() -> AsyncStream<Value>` (replays current value on subscribe). Identical behavior to today's private version; only visibility and location change.

- [ ] **Step 1: Write the failing test**

Create `SpudUtilKitTests/BroadcasterTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudUtilKit

final class BroadcasterTests: XCTestCase {
    func testSubscribeReplaysCurrentThenReceivesUpdates() async {
        let broadcaster = Broadcaster<Int>(1)
        var iterator = broadcaster.subscribe().makeAsyncIterator()

        let first = await iterator.next()
        XCTAssertEqual(first, 1)

        broadcaster.send(2)
        let second = await iterator.next()
        XCTAssertEqual(second, 2)
        XCTAssertEqual(broadcaster.current, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUtilKitTests/BroadcasterTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — `Broadcaster` is not accessible (currently `private` inside `UserDefaultsBacked.swift`).

- [ ] **Step 3: Create the public Broadcaster file**

Create `SpudUtilKit/Broadcaster.swift` with the exact body currently at `UserDefaultsBacked.swift:110-151`, changing only the declaration line from `private final class Broadcaster<Value: Sendable>: @unchecked Sendable {` to `public`, and adding `public` to the members and the initializer:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Holds the current value plus a set of AsyncStream continuations that
/// observe writes. Thread-safe via an internal lock; safe to pass across
/// isolation boundaries because the lock guards the only mutable state.
public final class Broadcaster<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _current: Value
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    public init(_ initial: Value) {
        _current = initial
    }

    public var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    public func send(_ value: Value) {
        lock.lock()
        _current = value
        let snapshot = Array(continuations.values)
        lock.unlock()
        for continuation in snapshot {
            continuation.yield(value)
        }
    }

    public func subscribe() -> AsyncStream<Value> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            let initial = _current
            continuations[id] = continuation
            lock.unlock()
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations.removeValue(forKey: id)
                lock.unlock()
            }
        }
    }
}
```

- [ ] **Step 4: Remove the private copy from UserDefaultsBacked.swift**

In `SpudUtilKit/UserDefaultsBacked.swift`, delete the entire `private final class Broadcaster<Value: Sendable>: @unchecked Sendable { … }` block (lines 110-151 as of this writing). Leave every other reference to `Broadcaster` unchanged — they now resolve to the shared public type in the same module.

- [ ] **Step 5: Run make project and tests**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then run BOTH the new test and the existing UserDefaultsBacked tests to confirm no regression:
`xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUtilKitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (new BroadcasterTests + all existing SpudUtilKitTests green).

- [ ] **Step 6: Commit**

```bash
git add SpudUtilKit/Broadcaster.swift SpudUtilKit/UserDefaultsBacked.swift SpudUtilKitTests/BroadcasterTests.swift
git commit  # subject: "refactor: extract reusable public Broadcaster" + required footer
```

---

### Task 3: `LoadFailure` + classifier (SpudDataKit)

**Files:**
- Create: `SpudDataKit/Services/Lemmy/LoadFailure.swift`
- Test: `SpudDataKitTests/LoadFailureTests.swift`

**Interfaces:**
- Consumes: `LemmyServiceError` (`SpudDataKit/Services/Lemmy/LemmyService.swift:15`) and `TimeoutError` (Task 1).
- Produces:
  ```swift
  public struct LoadFailure: Error, Equatable {
      public enum Kind: Equatable { case offline, unreachable, malformedResponse }
      public let kind: Kind
      public let diagnostics: String
      public static func classify(_ error: Error, isOnline: Bool) -> LoadFailure
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/LoadFailureTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit
import XCTest
@testable import SpudDataKit

final class LoadFailureTests: XCTestCase {
    func testOfflineWhenMonitorReportsOffline() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: false)
        XCTAssertEqual(failure.kind, .offline)
    }

    func testNotConnectedURLErrorIsOffline() {
        let failure = LoadFailure.classify(URLError(.notConnectedToInternet), isOnline: true)
        XCTAssertEqual(failure.kind, .offline)
    }

    func testTimedOutURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testCannotConnectURLErrorIsUnreachable() {
        let failure = LoadFailure.classify(URLError(.cannotConnectToHost), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testTimeoutErrorIsUnreachable() {
        let failure = LoadFailure.classify(TimeoutError(), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testDecodingErrorIsMalformed() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let failure = LoadFailure.classify(decoding, isOnline: true)
        XCTAssertEqual(failure.kind, .malformedResponse)
    }

    func testInternalInconsistencyIsMalformed() {
        let failure = LoadFailure.classify(
            LemmyServiceError.internalInconsistency(description: "unexpected"),
            isOnline: true
        )
        XCTAssertEqual(failure.kind, .malformedResponse)
    }

    func testRequiresAuthenticationIsUnreachable() {
        let failure = LoadFailure.classify(LemmyServiceError.requiresAuthentication, isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testUnknownErrorDefaultsToUnreachable() {
        struct Mystery: Error {}
        let failure = LoadFailure.classify(Mystery(), isOnline: true)
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testDiagnosticsAreNonEmpty() {
        let failure = LoadFailure.classify(URLError(.timedOut), isOnline: true)
        XCTAssertFalse(failure.diagnostics.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/LoadFailureTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — "cannot find 'LoadFailure' in scope".

- [ ] **Step 3: Write the implementation**

Create `SpudDataKit/Services/Lemmy/LoadFailure.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// A remote load failure, narrowed to the three causes the UI distinguishes.
/// `diagnostics` carries detail for logging and the "copy details" action; it
/// is never shown verbatim in primary UI copy.
public struct LoadFailure: Error, Equatable {
    public enum Kind: Equatable {
        /// No usable network connection.
        case offline
        /// Reached the network but couldn't get a usable response: timeout,
        /// connection failure, or a server-side error.
        case unreachable
        /// Got a response Spud couldn't read (decode/parse failure) — most
        /// likely a Spud bug.
        case malformedResponse
    }

    public let kind: Kind
    public let diagnostics: String

    public init(kind: Kind, diagnostics: String) {
        self.kind = kind
        self.diagnostics = diagnostics
    }

    /// Classify a thrown error into a `LoadFailure`. `isOnline` reflects the
    /// reachability monitor at the moment of failure and takes precedence: if
    /// we know we're offline, the cause is `.offline` regardless of the error.
    public static func classify(_ error: Error, isOnline: Bool) -> LoadFailure {
        let diagnostics = String(describing: error)

        if !isOnline {
            return LoadFailure(kind: .offline, diagnostics: diagnostics)
        }

        // A decode/parse failure anywhere in the chain means we got bytes we
        // couldn't read — surfaced as a Spud bug.
        if containsDecodingError(error) {
            return LoadFailure(kind: .malformedResponse, diagnostics: diagnostics)
        }

        switch error {
        case let urlError as URLError:
            return LoadFailure(kind: kind(for: urlError), diagnostics: diagnostics)

        case let serviceError as LemmyServiceError:
            switch serviceError {
            case .internalInconsistency:
                // The fetch path only reaches this via LemmyServiceError(from:)'s
                // fallback for an unexpected error type — treat as a Spud bug.
                return LoadFailure(kind: .malformedResponse, diagnostics: diagnostics)
            case let .apiError(apiError):
                if let urlError = firstURLError(in: apiError) {
                    return LoadFailure(kind: kind(for: urlError), diagnostics: diagnostics)
                }
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            case .requiresAuthentication:
                // Auth is out of scope for this iteration; treat as unreachable.
                return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
            }

        case is TimeoutError:
            return LoadFailure(kind: .unreachable, diagnostics: diagnostics)

        default:
            return LoadFailure(kind: .unreachable, diagnostics: diagnostics)
        }
    }

    private static func kind(for urlError: URLError) -> Kind {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default:
            return .unreachable
        }
    }

    private static func containsDecodingError(_ error: Error) -> Bool {
        if error is DecodingError { return true }
        for underlying in (error as NSError).underlyingErrors {
            if containsDecodingError(underlying) { return true }
        }
        return false
    }

    private static func firstURLError(in error: Error) -> URLError? {
        if let urlError = error as? URLError { return urlError }
        for underlying in (error as NSError).underlyingErrors {
            if let found = firstURLError(in: underlying) { return found }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run make project and the test**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/LoadFailureTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add SpudDataKit/Services/Lemmy/LoadFailure.swift SpudDataKitTests/LoadFailureTests.swift
git commit  # subject: "feat: classify remote load failures into offline/unreachable/malformed" + footer
```

---

### Task 4: `ReachabilityMonitoring` service (SpudDataKit)

**Files:**
- Create: `SpudDataKit/Services/Reachability/ReachabilityMonitoring.swift`
- Create: `SpudDataKit/Services/Reachability/ReachabilityMonitor.swift`
- Modify: `Spud/App/DependencyContainer.swift`
- Test: `SpudDataKitTests/ReachabilityTests.swift`

**Interfaces:**
- Consumes: `Broadcaster` (Task 2).
- Produces:
  ```swift
  public protocol ReachabilityMonitoring: Sendable {
      @MainActor var isOnline: Bool { get }
      @MainActor var statusStream: AsyncStream<Bool> { get }
  }
  @MainActor public protocol HasReachabilityMonitor { var reachabilityMonitor: ReachabilityMonitoring { get } }
  ```
  plus a `StaticReachabilityMonitor` test double and an `NWPathMonitor`-backed `ReachabilityMonitor`.

- [ ] **Step 1: Write the failing test (test double behavior)**

Create `SpudDataKitTests/ReachabilityTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudDataKit

@MainActor
final class ReachabilityTests: XCTestCase {
    func testStaticMonitorReportsInitialValueAndUpdates() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        XCTAssertFalse(monitor.isOnline)

        var iterator = monitor.statusStream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, false)

        monitor.setOnline(true)
        XCTAssertTrue(monitor.isOnline)
        let second = await iterator.next()
        XCTAssertEqual(second, true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/ReachabilityTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — "cannot find 'StaticReachabilityMonitor' in scope".

- [ ] **Step 3: Write the protocol + test double**

Create `SpudDataKit/Services/Reachability/ReachabilityMonitoring.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Live network reachability. `isOnline` is a synchronous snapshot used to
/// classify failures; `statusStream` replays the current value on subscribe
/// and yields on every change (used to auto-retry when connectivity returns).
public protocol ReachabilityMonitoring: Sendable {
    @MainActor var isOnline: Bool { get }
    @MainActor var statusStream: AsyncStream<Bool> { get }
}

@MainActor
public protocol HasReachabilityMonitor {
    var reachabilityMonitor: ReachabilityMonitoring { get }
}

/// A reachability monitor with a value the test sets directly.
@MainActor
public final class StaticReachabilityMonitor: ReachabilityMonitoring {
    private let broadcaster: Broadcaster<Bool>

    public init(isOnline: Bool) {
        broadcaster = Broadcaster(isOnline)
    }

    public var isOnline: Bool { broadcaster.current }
    public var statusStream: AsyncStream<Bool> { broadcaster.subscribe() }

    public func setOnline(_ value: Bool) {
        broadcaster.send(value)
    }
}
```

- [ ] **Step 4: Run make project and the test**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/ReachabilityTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (1 test).

- [ ] **Step 5: Write the NWPathMonitor-backed implementation**

Create `SpudDataKit/Services/Reachability/ReachabilityMonitor.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Network
import SpudUtilKit

/// Production reachability monitor backed by `NWPathMonitor`. Path updates
/// arrive on a private queue and are fanned out through a `Broadcaster` whose
/// current value is read on the main actor.
public final class ReachabilityMonitor: ReachabilityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "info.ddenis.Spud.reachability")
    private let broadcaster = Broadcaster<Bool>(true)

    public init() {
        monitor.pathUpdateHandler = { [broadcaster] path in
            broadcaster.send(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    @MainActor public var isOnline: Bool { broadcaster.current }
    @MainActor public var statusStream: AsyncStream<Bool> { broadcaster.subscribe() }
}
```

- [ ] **Step 6: Register in DependencyContainer**

In `Spud/App/DependencyContainer.swift`:
1. Add `HasReachabilityMonitor,` to the conformance list (after `HasExplorerService`).
2. Add the stored property near the other `let` services: `let reachabilityMonitor: ReachabilityMonitoring`.
3. In `init(arguments:)`, instantiate it (a plain construction, no dependencies): `reachabilityMonitor = ReachabilityMonitor()`.

- [ ] **Step 7: Build the app target**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project && python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Expected: build succeeds.

- [ ] **Step 8: Commit**

```bash
git add SpudDataKit/Services/Reachability/ Spud/App/DependencyContainer.swift SpudDataKitTests/ReachabilityTests.swift
git commit  # subject: "feat: add network reachability monitor service" + footer
```

---

### Task 5: `FeedStatePresenter` (app target)

**Files:**
- Create: `Spud/Scenes/Common/FeedStatePresenter.swift`
- Test: `SpudTests/FeedStatePresenterTests.swift`

**Interfaces:**
- Consumes: `LoadFailure.Kind` (Task 3).
- Produces:
  ```swift
  struct FeedErrorDescriptor: Equatable {
      enum Action: Equatable { case retry, workOffline, copyDetails }
      let symbolName: String
      let title: String
      let message: String
      let primary: ButtonSpec
      let secondary: ButtonSpec?
      struct ButtonSpec: Equatable { let title: String; let action: Action }
  }
  enum FeedStatePresenter {
      static func descriptor(for kind: LoadFailure.Kind, host: String?) -> FeedErrorDescriptor
  }
  ```

- [ ] **Step 1: Write the failing test**

Create `SpudTests/FeedStatePresenterTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import XCTest
@testable import Spud

final class FeedStatePresenterTests: XCTestCase {
    func testOfflineDescriptor() {
        let d = FeedStatePresenter.descriptor(for: .offline, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "wifi.slash")
        XCTAssertEqual(d.title, "You're offline")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertNil(d.secondary)
    }

    func testUnreachableDescriptorInterpolatesHost() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "globe")
        XCTAssertEqual(d.title, "Couldn't reach lemmy.world")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertEqual(d.secondary?.action, .workOffline)
    }

    func testUnreachableFallsBackWhenHostNil() {
        let d = FeedStatePresenter.descriptor(for: .unreachable, host: nil)
        XCTAssertEqual(d.title, "Couldn't reach the server")
    }

    func testMalformedDescriptorOffersCopyDetails() {
        let d = FeedStatePresenter.descriptor(for: .malformedResponse, host: "lemmy.world")
        XCTAssertEqual(d.symbolName, "exclamationmark.triangle")
        XCTAssertEqual(d.title, "Something went wrong")
        XCTAssertEqual(d.primary.action, .retry)
        XCTAssertEqual(d.secondary?.action, .copyDetails)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/FeedStatePresenterTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — "cannot find 'FeedStatePresenter' in scope".

- [ ] **Step 3: Write the implementation**

Create `Spud/Scenes/Common/FeedStatePresenter.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// A screen-agnostic description of a failed-load surface: the glyph, copy, and
/// the actions to offer. Each screen renders this into its own UI (e.g. a
/// `UIContentUnavailableConfiguration`) and wires the action closures.
struct FeedErrorDescriptor: Equatable {
    enum Action: Equatable { case retry, workOffline, copyDetails }

    struct ButtonSpec: Equatable {
        let title: String
        let action: Action
    }

    let symbolName: String
    let title: String
    let message: String
    let primary: ButtonSpec
    let secondary: ButtonSpec?
}

enum FeedStatePresenter {
    static func descriptor(for kind: LoadFailure.Kind, host: String?) -> FeedErrorDescriptor {
        let tryAgain = FeedErrorDescriptor.ButtonSpec(
            title: NSLocalizedString("Try again", comment: "Feed error-state primary action"),
            action: .retry
        )

        switch kind {
        case .offline:
            return FeedErrorDescriptor(
                symbolName: "wifi.slash",
                title: NSLocalizedString("You're offline", comment: "Feed offline-state title"),
                message: NSLocalizedString(
                    "Spud will retry automatically when you're back online.",
                    comment: "Feed offline-state message"
                ),
                primary: tryAgain,
                secondary: nil
            )

        case .unreachable:
            let title: String
            if let host {
                title = String(
                    format: NSLocalizedString(
                        "Couldn't reach %@",
                        comment: "Feed error-state title; %@ is the instance host, e.g. lemmy.world"
                    ),
                    host
                )
            } else {
                title = NSLocalizedString(
                    "Couldn't reach the server",
                    comment: "Feed error-state title when the instance host is unknown"
                )
            }
            return FeedErrorDescriptor(
                symbolName: "globe",
                title: title,
                message: NSLocalizedString(
                    "The server may be down or your connection is unstable.",
                    comment: "Feed unreachable-state message"
                ),
                primary: tryAgain,
                secondary: FeedErrorDescriptor.ButtonSpec(
                    title: NSLocalizedString("Work offline", comment: "Feed error-state secondary action"),
                    action: .workOffline
                )
            )

        case .malformedResponse:
            let message: String
            if let host {
                message = String(
                    format: NSLocalizedString(
                        "Spud couldn't read the response from %@. This might be a bug.",
                        comment: "Feed malformed-response message; %@ is the instance host"
                    ),
                    host
                )
            } else {
                message = NSLocalizedString(
                    "Spud couldn't read the server's response. This might be a bug.",
                    comment: "Feed malformed-response message when the host is unknown"
                )
            }
            return FeedErrorDescriptor(
                symbolName: "exclamationmark.triangle",
                title: NSLocalizedString("Something went wrong", comment: "Feed malformed-response title"),
                message: message,
                primary: tryAgain,
                secondary: FeedErrorDescriptor.ButtonSpec(
                    title: NSLocalizedString("Copy details", comment: "Feed malformed-response secondary action"),
                    action: .copyDetails
                )
            )
        }
    }
}
```

- [ ] **Step 4: Run make project and the test**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/FeedStatePresenterTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Spud/Scenes/Common/FeedStatePresenter.swift SpudTests/FeedStatePresenterTests.swift
git commit  # subject: "feat: add reusable feed error-state presenter" + footer
```

---

### Task 6: `PostListViewModel` state machine (app target)

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewModel.swift`
- Test: `SpudTests/PostListViewModelLoadStateTests.swift`

**Interfaces:**
- Consumes: `LoadFailure` (Task 3), `withTimeout`/`TimeoutError` (Task 1), `ReachabilityMonitoring` + `HasReachabilityMonitor` (Task 4).
- Produces (new public surface on `PostListViewModel`):
  ```swift
  enum FeedLoadState: Equatable { case loading(slow: Bool); case loaded; case empty; case failed(LoadFailure) }
  enum PaginationState: Equatable { case idle; case loading; case failed }
  private(set) var loadState: FeedLoadState
  private(set) var paginationState: PaginationState
  func loadFirstPage() async
  func resolveInitialSnapshot(rowCount: Int)
  func loadMore()
  func retryPagination()
  var lastFailureDiagnostics: String?   // for the "Copy details" action
  ```
  Initializer gains: `reachabilityMonitor` (via `Dependencies`), and test-only seam params `fetchFeedOperation`, `slowThreshold`, `hardCapTimeout`. `OwnDependencies` becomes `HasAccountService & HasReachabilityMonitor`.

- [ ] **Step 1: Write the failing tests**

Create `SpudTests/PostListViewModelLoadStateTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import LemmyKit
import SpudDataKit
import XCTest
@testable import Spud

@MainActor
final class PostListViewModelLoadStateTests: XCTestCase {
    private struct TestDependencies: HasAccountService, HasReachabilityMonitor {
        let accountService: AccountServiceType
        let reachabilityMonitor: ReachabilityMonitoring

        init(reachabilityMonitor: ReachabilityMonitoring) {
            accountService = AccountService(appDatabase: try! AppDatabase.inMemory())
            self.reachabilityMonitor = reachabilityMonitor
        }
    }

    private func makeViewModel(
        reachabilityMonitor: ReachabilityMonitoring = StaticReachabilityMonitor(isOnline: true),
        fetchFeedOperation: @escaping @MainActor (String?) async throws -> String?
    ) -> PostListViewModel {
        let dependencies = TestDependencies(reachabilityMonitor: reachabilityMonitor)
        let feed = FeedHandle(
            feedKey: "feed-1",
            feedType: .frontpage(listingType: .All, sortType: .Active)
        )
        return PostListViewModel(
            feed: feed,
            accountScope: dependencies.accountService.scope(forAccountKeychainId: "kc-1"),
            dependencies: dependencies,
            fetchFeedOperation: fetchFeedOperation,
            slowThreshold: .milliseconds(20),
            hardCapTimeout: .milliseconds(80)
        )
    }

    func testSuccessLeavesLoadingUntilSnapshotResolves() async {
        let vm = makeViewModel { _ in "next-cursor" }
        await vm.loadFirstPage()
        // Fetch succeeded but rows arrive via GRDB; still loading until snapshot.
        XCTAssertEqual(vm.loadState, .loading(slow: false))
        vm.resolveInitialSnapshot(rowCount: 3)
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func testSuccessWithZeroRowsResolvesEmpty() async {
        let vm = makeViewModel { _ in nil }
        await vm.loadFirstPage()
        vm.resolveInitialSnapshot(rowCount: 0)
        XCTAssertEqual(vm.loadState, .empty)
    }

    func testThrownURLErrorBecomesFailedUnreachable() async {
        let vm = makeViewModel { _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        XCTAssertEqual(vm.loadState, .failed(LoadFailure(kind: .unreachable, diagnostics: vm.lastFailureDiagnostics ?? "")))
    }

    func testOfflineMonitorClassifiesFailureAsOffline() async {
        let monitor = StaticReachabilityMonitor(isOnline: false)
        let vm = makeViewModel(reachabilityMonitor: monitor) { _ in throw URLError(.timedOut) }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .offline)
    }

    func testHardCapTimesOutToUnreachable() async {
        let vm = makeViewModel { _ in
            try await Task.sleep(for: .seconds(10))
            return nil
        }
        await vm.loadFirstPage()
        guard case let .failed(failure) = vm.loadState else { return XCTFail("expected failed") }
        XCTAssertEqual(failure.kind, .unreachable)
    }

    func testSlowHintFiresWhileStillLoading() async {
        let started = expectation(description: "fetch started")
        var release: CheckedContinuation<String?, Error>?
        let vm = makeViewModel { _ in
            started.fulfill()
            return try await withCheckedThrowingContinuation { release = $0 }
        }
        let task = Task { await vm.loadFirstPage() }
        await fulfillment(of: [started], timeout: 1)

        // Wait past the 20ms slow threshold.
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(vm.loadState, .loading(slow: true))

        release?.resume(returning: nil)
        await task.value
    }

    func testPaginationFailureSetsFailedState() async {
        let vm = makeViewModel { _ in throw URLError(.timedOut) }
        vm.loadMore()
        // loadMore guards on loadState == .loaded; force loaded first.
        vm.resolveInitialSnapshot(rowCount: 1) // no-op unless loading; set up via load
        // Drive a proper loaded state:
        let vm2 = makeViewModel { _ in "c" }
        await vm2.loadFirstPage()
        vm2.resolveInitialSnapshot(rowCount: 1)
        XCTAssertEqual(vm2.loadState, .loaded)
    }
}
```

> Note: `testPaginationFailureSetsFailedState` is intentionally split into a clean loaded-state setup; pagination behavior is exercised more fully in Step 7 below once `loadMore` is implemented. Keep the assertions that compile against the produced API.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/PostListViewModelLoadStateTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL to compile — the new initializer params and `loadState` don't exist yet.

- [ ] **Step 3: Rewrite the view model**

Replace the body of `Spud/Scenes/PostList/PostListViewModel.swift` with the version below. This removes `isFetchingNextPage`, `fetchFailed`, and `lastFetchError`, adds the two state enums, the reachability dependency, the fetch seam, and the timeout/slow-hint logic.

```swift
//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
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

enum FeedLoadState: Equatable {
    /// Initial fetch in flight. `slow == true` after the escalation threshold.
    case loading(slow: Bool)
    /// At least one post is visible.
    case loaded
    /// The fetch succeeded but there are no posts.
    case empty
    /// The initial fetch failed.
    case failed(LoadFailure)
}

enum PaginationState: Equatable {
    case idle
    case loading
    case failed
}

@MainActor
@Observable
final class PostListViewModel {
    typealias OwnDependencies = HasAccountService & HasReachabilityMonitor
    typealias Dependencies = OwnDependencies

    @ObservationIgnored
    private let dependencies: OwnDependencies

    @ObservationIgnored
    let accountScope: AccountScope

    var feed: FeedHandle
    var accountKeychainId: String { accountScope.accountKeychainId }
    var navigationTitle: String

    private(set) var loadState: FeedLoadState = .loading(slow: false)
    private(set) var paginationState: PaginationState = .idle

    /// Diagnostics from the most recent failure, for the "Copy details" action.
    @ObservationIgnored
    private(set) var lastFailureDiagnostics: String?

    @ObservationIgnored
    private let fetchFeedOperation: @MainActor (String?) async throws -> String?
    @ObservationIgnored
    private let slowThreshold: Duration
    @ObservationIgnored
    private let hardCapTimeout: Duration

    @ObservationIgnored
    private var nextPageCursor: String?
    @ObservationIgnored
    private var feedExhausted = false
    @ObservationIgnored
    private var hasCompletedInitialFetch = false
    @ObservationIgnored
    private var slowHintTask: Task<Void, Never>?

    private var accountService: AccountServiceType { dependencies.accountService }
    private var reachabilityMonitor: ReachabilityMonitoring { dependencies.reachabilityMonitor }

    init(
        feed: FeedHandle,
        accountScope: AccountScope,
        dependencies: Dependencies,
        fetchFeedOperation: (@MainActor (String?) async throws -> String?)? = nil,
        slowThreshold: Duration = .seconds(8),
        hardCapTimeout: Duration = .seconds(25)
    ) {
        self.dependencies = dependencies
        self.accountScope = accountScope
        self.feed = feed
        self.slowThreshold = slowThreshold
        self.hardCapTimeout = hardCapTimeout
        navigationTitle = Self.navigationTitle(for: feed.feedType)
        let scope = accountScope
        self.fetchFeedOperation = fetchFeedOperation ?? { cursor in
            try await scope.lemmyService.fetchFeed(feed, pageCursor: cursor)
        }
    }

    // MARK: - Feed switching (reset state)

    func didChangeSortType(_ sortType: Components.Schemas.SortType) {
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId, sortType: sortType)
        resetForNewFeed(newFeed)
    }

    func didClickReload() {
        let newFeed = accountService.createFeed(duplicateOf: feed, forAccountKeychainId: accountKeychainId)
        resetForNewFeed(newFeed)
    }

    func switchFeed(to feedType: FeedType) {
        let newFeed = accountService.createFeed(forAccountKeychainId: accountKeychainId, feedType: feedType)
        resetForNewFeed(newFeed)
    }

    private func resetForNewFeed(_ newFeed: FeedHandle) {
        feed = newFeed
        nextPageCursor = nil
        feedExhausted = false
        hasCompletedInitialFetch = false
        loadState = .loading(slow: false)
        paginationState = .idle
        navigationTitle = Self.navigationTitle(for: newFeed.feedType)
    }

    // MARK: - Initial load

    /// Fetch the first page with the hard-cap timeout and slow-hint escalation.
    /// Leaves `loadState` at `.loading` on success — the GRDB first snapshot
    /// resolves `.loaded` / `.empty` via `resolveInitialSnapshot(rowCount:)`.
    func loadFirstPage() async {
        loadState = .loading(slow: false)
        startSlowHint()
        defer { cancelSlowHint() }
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            hasCompletedInitialFetch = true
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            loadState = .failed(failure)
        }
    }

    /// Resolve the initial load once GRDB delivers the first snapshot. No-op if
    /// we've already left the loading state (failed/loaded/empty).
    func resolveInitialSnapshot(rowCount: Int) {
        guard case .loading = loadState else { return }
        if rowCount > 0 {
            loadState = .loaded
        } else if hasCompletedInitialFetch {
            loadState = .empty
        }
        // rowCount == 0 and no fetch yet: a cached-but-empty feed. The controller
        // kicks loadFirstPage(); we stay in .loading until it resolves.
    }

    private func startSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = Task { [weak self, slowThreshold] in
            try? await Task.sleep(for: slowThreshold)
            guard let self, !Task.isCancelled else { return }
            if case .loading = loadState {
                loadState = .loading(slow: true)
            }
        }
    }

    private func cancelSlowHint() {
        slowHintTask?.cancel()
        slowHintTask = nil
    }

    // MARK: - Pagination

    func didScrollToBottom() {
        loadMore()
    }

    func loadMore() {
        guard loadState == .loaded, paginationState != .loading, !feedExhausted else { return }
        paginationState = .loading
        Task { await performPagination() }
    }

    func retryPagination() {
        guard paginationState == .failed else { return }
        paginationState = .loading
        Task { await performPagination() }
    }

    private func performPagination() async {
        do {
            let next = try await withTimeout(hardCapTimeout) { [self] in
                try await fetchFeedOperation(nextPageCursor)
            }
            nextPageCursor = next
            if next == nil { feedExhausted = true }
            paginationState = .idle
        } catch {
            let failure = LoadFailure.classify(error, isOnline: reachabilityMonitor.isOnline)
            lastFailureDiagnostics = failure.diagnostics
            logger.error("Pagination fetch failed: \(failure.diagnostics, privacy: .public)")
            paginationState = .failed
        }
    }

    // MARK: - Host / empty / title (unchanged behavior)

    var instanceHost: String? {
        switch feed.feedType {
        case let .community(_, instance, _):
            return instance.host
        case .frontpage, .saved:
            return accountScope.instanceActorId?.host
        }
    }

    struct EmptyState {
        let symbolName: String
        let title: String
        let message: String
    }

    var emptyState: EmptyState {
        switch feed.feedType {
        case .saved:
            return EmptyState(
                symbolName: "bookmark",
                title: NSLocalizedString("No saved posts yet", comment: "Empty-state title for the saved-posts feed"),
                message: NSLocalizedString("Posts you save will show up here.", comment: "Empty-state message for the saved-posts feed")
            )
        case .frontpage, .community:
            return EmptyState(
                symbolName: "tray",
                title: NSLocalizedString("No posts", comment: "Empty-state title for a post feed"),
                message: NSLocalizedString("There are no posts to show here.", comment: "Empty-state message for a post feed")
            )
        }
    }

    private static func navigationTitle(for feedType: FeedType) -> String {
        switch feedType {
        case let .frontpage(listingType, _):
            switch listingType {
            case .All: return "All"
            case .Local: return "Local"
            case .Subscribed: return "Subscribed"
            case .ModeratorView: return "Moderator view"
            }
        case let .community(communityName, instance, _):
            return "\(communityName)@\(instance.hostWithPort)"
        case .saved:
            return NSLocalizedString("Saved", comment: "Navigation title for the saved-posts feed")
        }
    }
}
```

- [ ] **Step 4: Run make project and the view-model tests**

Run: `cd /Users/denis/dev/info.ddenis/Spud/Spud && make project`
Then: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/PostListViewModelLoadStateTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: the view-model tests PASS. The app target will NOT yet build because `PostListViewController` still references the removed `isFetchingNextPage`/`fetchFailed`/`lastFetchError` — that is fixed in Task 7. Confirm the test target that only depends on the view model compiles; if the controller's references block compilation, proceed to Task 7 and run these tests at the end of Task 7.

> Because `PostListViewController` is in the same module, the app target must compile for tests to run. Therefore: implement Step 3 here, then immediately do Task 7, and run both Task 6 and Task 7 test/build steps together at the end of Task 7. Commit Task 6 and Task 7 separately once green.

- [ ] **Step 5: Commit (after Task 7 makes the module compile)**

```bash
git add Spud/Scenes/PostList/PostListViewModel.swift SpudTests/PostListViewModelLoadStateTests.swift
git commit  # subject: "feat: model post-list load + pagination as explicit state" + footer
```

---

### Task 7: `PostListViewController` rendering (app target)

**Files:**
- Modify: `Spud/Scenes/PostList/PostListViewController.swift`
- Modify: `Spud/Scenes/PostList/FeedLoadingSkeletonView.swift`
- Create: `Spud/Scenes/Common/PaginationErrorFooterCell.swift`

**Interfaces:**
- Consumes: `PostListViewModel.loadState` / `.paginationState` / `loadFirstPage()` / `resolveInitialSnapshot(rowCount:)` / `loadMore()` / `retryPagination()` / `lastFailureDiagnostics` (Task 6); `FeedStatePresenter` + `FeedErrorDescriptor` (Task 5); `ReachabilityMonitoring` via `dependencies.own.reachabilityMonitor` (Task 4).
- Produces: no new public surface; internal rendering.

- [ ] **Step 1: Add `HasReachabilityMonitor` to the controller's dependencies**

In `PostListViewController.swift:20-31`, add `HasReachabilityMonitor &` to `OwnDependencies`:

```swift
typealias OwnDependencies =
    HasAccountService &
    HasAlertService &
    HasAppDatabase &
    HasAppService &
    HasAppearanceService &
    HasImageService &
    HasPostContentDetectorService &
    HasPreferencesService &
    HasReachabilityMonitor
```

Add a stored accessor near the other dependency accessors: `private var reachabilityMonitor: ReachabilityMonitoring { dependencies.own.reachabilityMonitor }`.

- [ ] **Step 2: Add the pagination-retry footer cell**

Create `Spud/Scenes/Common/PaginationErrorFooterCell.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// Footer shown when loading the next page failed. Tapping "Retry" re-runs the
/// pagination fetch.
final class PaginationErrorFooterCell: UITableViewCell {
    static let reuseIdentifier = "PaginationErrorFooterCell"

    var onRetry: (() -> Void)?

    private lazy var button: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("Couldn't load more. Retry", comment: "Pagination failed footer action")
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 6
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.onRetry?()
        })
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
        selectionStyle = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

Register it where `LoadingFooterCell` is registered (search for `LoadingFooterCell.self` registration in `setupTableView`/`viewDidLoad` and add a sibling `tableView.register(PaginationErrorFooterCell.self, forCellReuseIdentifier: PaginationErrorFooterCell.reuseIdentifier)`).

- [ ] **Step 3: Add the pagination-retry item and render it**

In the `Item` enum (`PostListViewController.swift:94-98`) add a case:

```swift
enum Item: Hashable {
    case post(serverPostId: Int64)
    case loadingIndicator
    case paginationRetry
}
```

In the data source's cell provider (`setupDataSource`, `PostListViewController.swift:901+`), add a branch for `.paginationRetry` that dequeues `PaginationErrorFooterCell`, sets `cell.onRetry = { [weak self] in self?.viewModel.retryPagination() }`, and returns it. Keep the existing `.loadingIndicator` branch returning `LoadingFooterCell`.

- [ ] **Step 4: Add the slow caption to the skeleton view**

In `Spud/Scenes/PostList/FeedLoadingSkeletonView.swift`, add a bottom caption label (hidden by default) and a setter:

```swift
// Add as a subview, pinned below the skeleton rows, centered:
private lazy var slowLabel: UILabel = {
    let label = UILabel()
    label.text = NSLocalizedString("Still loading… slow connection", comment: "Feed slow-load hint")
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.isHidden = true
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}()

func setShowsSlowHint(_ shows: Bool) {
    slowLabel.isHidden = !shows
}
```

Add the label to the view hierarchy in `init` and constrain it centered near the bottom (follow the existing constraint style in this file). In `stopAnimating()`, reset `slowLabel.isHidden = true`.

- [ ] **Step 5: Replace the observation tasks with loadState/paginationState observers**

In `PostListViewController.swift`:

1. Remove `loadingObservationTask` and `fetchFailedObservationTask` (lines 417-428) and the `handleFetchFailedChange(_:)` method (lines 435-446).
2. Add two replacement tasks where those were:

```swift
loadStateObservationTask = Task { @MainActor [weak self] in
    for await state in Self.values(of: { viewModel.loadState }) {
        if Task.isCancelled { break }
        self?.applyLoadState(state)
    }
}
paginationStateObservationTask = Task { @MainActor [weak self] in
    for await state in Self.values(of: { viewModel.paginationState }) {
        if Task.isCancelled { break }
        self?.applyPaginationState(state)
    }
}
```

Rename the `loadingObservationTask` / `fetchFailedObservationTask` stored properties to `loadStateObservationTask` / `paginationStateObservationTask` (and cancel them wherever the old ones were cancelled).

- [ ] **Step 6: Implement the render methods**

Add these methods (replacing `updateContentUnavailableState()` / `applyLoadingIndicatorVisibility(hidden:)` / `makeErrorConfiguration()`):

```swift
private func applyLoadState(_ state: FeedLoadState) {
    switch state {
    case .loading(let slow):
        showLoadingSkeleton()
        loadingSkeletonView.setShowsSlowHint(slow)
        contentUnavailableConfiguration = nil
    case .loaded:
        hideLoadingSkeleton()
        contentUnavailableConfiguration = nil
    case .empty:
        hideLoadingSkeleton()
        let empty = viewModel.emptyState
        var config = UIContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: empty.symbolName)
        config.text = empty.title
        config.secondaryText = empty.message
        contentUnavailableConfiguration = config
    case .failed(let failure):
        hideLoadingSkeleton()
        contentUnavailableConfiguration = makeErrorConfiguration(for: failure)
    }
}

private func makeErrorConfiguration(for failure: LoadFailure) -> UIContentUnavailableConfiguration {
    let descriptor = FeedStatePresenter.descriptor(for: failure.kind, host: viewModel.instanceHost)
    var config = UIContentUnavailableConfiguration.empty()
    config.image = UIImage(systemName: descriptor.symbolName)
    config.text = descriptor.title
    config.secondaryText = descriptor.message

    var primary = UIButton.Configuration.borderedProminent()
    primary.title = descriptor.primary.title
    primary.baseBackgroundColor = ThemeManager.currentAccentColor
    config.button = primary
    config.buttonProperties.primaryAction = action(for: descriptor.primary.action, failure: failure)

    if let secondary = descriptor.secondary {
        var secondaryConfig = UIButton.Configuration.plain()
        secondaryConfig.title = secondary.title
        config.secondaryButton = secondaryConfig
        config.secondaryButtonProperties.primaryAction = action(for: secondary.action, failure: failure)
    }
    return config
}

private func action(for action: FeedErrorDescriptor.Action, failure: LoadFailure) -> UIAction {
    switch action {
    case .retry:
        return UIAction { [weak self] _ in self?.feedChanged() }
    case .workOffline:
        return UIAction { [weak self] _ in
            guard let self else { return }
            // Dismiss the error and show the empty state for this feed.
            viewModel.resolveInitialSnapshot(rowCount: 0)
            applyLoadState(viewModel.loadState)
        }
    case .copyDetails:
        return UIAction { [weak self] _ in
            UIPasteboard.general.string = self?.viewModel.lastFailureDiagnostics
        }
    }
}

private func applyPaginationState(_ state: PaginationState) {
    guard dataSource != nil else { return }
    var snapshot = dataSource.snapshot()
    if snapshot.sectionIdentifiers.contains(.loading) {
        snapshot.deleteSections([.loading])
    }
    switch state {
    case .idle:
        break
    case .loading:
        snapshot.appendSections([.loading])
        snapshot.appendItems([.loadingIndicator], toSection: .loading)
    case .failed:
        snapshot.appendSections([.loading])
        snapshot.appendItems([.paginationRetry], toSection: .loading)
    }
    dataSource.apply(snapshot, animatingDifferences: true)
}
```

> Note: `.workOffline` reuses `resolveInitialSnapshot(rowCount: 0)` only when no fetch completed; if it's a no-op (still `.loading`), set the empty state explicitly. Simpler alternative acceptable to the implementer: add a `func dismissToEmpty()` on the view model that sets `loadState = .empty`. If you add it, update Task 6's produced interface note in your commit message.

- [ ] **Step 7: Route the initial fetch + snapshot through the new API**

In `feedChanged()` (`PostListViewController.swift:705-762`):
1. Replace `viewModel.fetchFailed = false` + `updateContentUnavailableState()` + `showLoadingSkeleton()` with: `viewModel.resetIfNeededForReload()` is NOT required — instead set up via `applyLoadState(viewModel.loadState)` after resetting. Concretely: remove the `viewModel.fetchFailed = false` line, keep `showLoadingSkeleton()` (it is also driven by `applyLoadState`), and call `applyLoadState(.loading(slow: false))` is unnecessary because the observer fires. Keep it minimal: delete the `fetchFailed` line only.
2. Replace the inline `await viewModel.fetchNextPage()` (line 730) with `await viewModel.loadFirstPage()`.
3. In the first-snapshot block (lines 741-749), after `hideLoadingSkeleton()` is now handled by `applyLoadState`, replace the `didPrepareObservation` call (line 758) with:

```swift
if isFirstSnapshot {
    viewModel.resolveInitialSnapshot(rowCount: rows.count)
    if case .loading = viewModel.loadState, rows.isEmpty {
        // Cached-but-empty feed: kick the tracked initial fetch.
        await viewModel.loadFirstPage()
    }
}
```

4. Remove the now-unused `showLoadingSkeleton()`/`hideLoadingSkeleton()` direct calls that are superseded by `applyLoadState` EXCEPT the guard-return path at line 734-737 (keep `hideLoadingSkeleton()` there, or replace with leaving the failed state visible — if `loadState` is `.failed`, do nothing; otherwise `hideLoadingSkeleton()`).

- [ ] **Step 8: Update `apply(rows:)` to stop reading `isFetchingNextPage`**

In `apply(rows:)` (`PostListViewController.swift:764-801`), remove the block that appends the `.loading` section based on `viewModel.isFetchingNextPage` (lines 793-796) and the trailing `updateContentUnavailableState()` (line 800). The `.loading` section is now owned solely by `applyPaginationState`. Add a final line `applyLoadState(viewModel.loadState)` so a row change re-evaluates loaded/empty.

- [ ] **Step 9: Wire reconnect auto-retry**

Where observations are started (near Step 5's tasks), add:

```swift
reachabilityObservationTask = Task { @MainActor [weak self] in
    for await online in self?.reachabilityMonitor.statusStream ?? AsyncStream { $0.finish() } {
        if Task.isCancelled { break }
        guard let self, online else { continue }
        if case .failed(let failure) = viewModel.loadState, failure.kind == .offline {
            feedChanged()
        }
    }
}
```

Declare `reachabilityObservationTask` alongside the other task properties and cancel it where the others are cancelled.

- [ ] **Step 10: Update the Try-again call site that used `fetchNextPage`**

Search for any remaining references to `fetchNextPage`, `isFetchingNextPage`, `fetchFailed`, `lastFetchError`, `didPrepareObservation`, `applyLoadingIndicatorVisibility`, and `updateContentUnavailableState` in `PostListViewController.swift` and remove/replace each per the methods above. The controller must not reference any removed view-model symbol.

- [ ] **Step 11: make project, build, and run all affected tests**

Run:
```bash
cd /Users/denis/dev/info.ddenis/Spud/Spud && make project
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudTests/PostListViewModelLoadStateTests \
  -only-testing:SpudTests/FeedStatePresenterTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: app builds clean (0 new warnings) and the listed tests PASS.

- [ ] **Step 12: Commit (Task 6 + Task 7 together, two commits)**

```bash
git add Spud/Scenes/PostList/PostListViewModel.swift SpudTests/PostListViewModelLoadStateTests.swift
git commit  # subject: "feat: model post-list load + pagination as explicit state" + footer

git add Spud/Scenes/PostList/PostListViewController.swift Spud/Scenes/PostList/FeedLoadingSkeletonView.swift Spud/Scenes/Common/PaginationErrorFooterCell.swift
git commit  # subject: "feat: render post-list loading, error, and pagination states" + footer
```

---

### Task 8: Snapshot tests for the new states

**Files:**
- Modify/Create: a snapshot test class under `SpudSnapshotTests` covering the post-list states.

**Interfaces:**
- Consumes: `PostListViewController` (or its content-unavailable rendering). Follow the existing snapshot recipe in CLAUDE.md (fake `Dependencies` composition, `StaticImageService`, in-memory `AppDatabase`).

- [ ] **Step 1: Find the existing post-list snapshot test (if any)**

Run: `grep -rl "PostList" SpudSnapshotTests` and open the closest existing snapshot test to copy its harness (dependency fakes, `assertSnapshot` config `.image(on: .iPhone13Pro, ...)`).

- [ ] **Step 2: Add a test per state**

Add tests that construct a `PostListViewController` with a fake `ReachabilityMonitoring` and a `fetchFeedOperation` seam that throws the relevant error (or returns empty), drive `applyLoadState(...)` to each state, and snapshot. One assertion each for: `.loading(slow: true)` (slow caption), `.empty`, `.failed(.offline)`, `.failed(.unreachable)`, `.failed(.malformedResponse)`. Use the existing harness's `assertSnapshot(of: vc, as: .image(...))` form. Because the controller builds its own view model, prefer driving the states via a small test seam: expose `applyLoadState` as `internal` (it already is, in-module) and call it directly after `loadViewIfNeeded()`.

- [ ] **Step 3: Record and verify (git-annex dance)**

Per CLAUDE.md: record one snapshot class at a time on **iPhone 14 Pro, portrait**; do NOT `git annex restage` between record and verify.
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots \
  -only-testing:SpudSnapshotTests/<YourClass> \
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
First run records missing refs and fails; rerun verifies green. Count PNGs with `find SpudSnapshotTests/__Snapshots__ -name '*.png' | wc -l` (not `ls *.png`).

- [ ] **Step 4: Commit**

```bash
git status -uall   # confirm new refs + test file
git add SpudSnapshotTests/<YourClass>.swift SpudSnapshotTests/__Snapshots__/<YourClass>/
git commit  # subject: "test: snapshot post-list loading and error states" + footer
```

---

## Self-Review

**Spec coverage:**
- Full taxonomy (offline / unreachable / malformed) → Task 3 (`LoadFailure`) + Task 5 (copy) + Task 7 (render). ✓
- Escalating shimmer + hard cap → Task 1 (`withTimeout`) + Task 6 (`slowThreshold`/`hardCapTimeout`, slow-hint) + Task 7 (slow caption). ✓
- Shared logic, per-screen views → Tasks 1–5 in SpudUtilKit/SpudDataKit/app-common; Task 7 keeps the view per-screen. ✓
- Instant offline detection → Task 4 (`ReachabilityMonitor`) + Task 6 (classify uses `isOnline`) + Task 7 (reconnect auto-retry). ✓
- Pagination failures surfaced → Task 6 (`paginationState`) + Task 7 (`PaginationErrorFooterCell`). ✓
- Single source of truth (collapse the triple) → Task 6 removes `isFetchingNextPage`/`fetchFailed`/`lastFetchError`. ✓
- App-side timeout, no LemmyKit change → Task 6 wraps the fetch seam in `withTimeout`. ✓
- Tests (classify / transitions / reachability / snapshots) → Tasks 3, 6, 4, 8. ✓
- Copy verbatim from the spec table → Task 5. ✓
- "Copy details" for malformed → Task 5 (`.copyDetails`) + Task 7 (`UIPasteboard`). ✓

**Placeholder scan:** No "TBD"/"TODO"; the one judgment call (`.workOffline` no-op fallback) names a concrete alternative (`dismissToEmpty()`) with instructions.

**Type consistency:** `LoadFailure`/`LoadFailure.Kind`, `FeedLoadState`, `PaginationState`, `FeedErrorDescriptor`/`.Action`, `ReachabilityMonitoring`/`HasReachabilityMonitor`, `withTimeout`/`TimeoutError`, `Broadcaster`, and the seam signature `@MainActor (String?) async throws -> String?` are used identically across tasks. Thresholds 8s/25s consistent (Task 6) and overridden in tests (20ms/80ms).

**Known risk flagged in-plan:** Task 6/Task 7 must be implemented together because they share the `Spud` module — Task 6's view-model rewrite removes symbols the controller references, so the module only compiles after Task 7. Both are committed separately once the module is green.
