//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing

/// Default budget for ``waitUntil(_:timeout:pollInterval:isolation:sourceLocation:_:)``.
///
/// Deliberately generous. Swift Testing runs the whole target's tests in
/// parallel, so the wall-clock latency of an in-memory write, a detached
/// `Task`, or an observation hop back to the main actor scales with how loaded
/// the machine is — it is not a property of the code under test. Per-suite
/// budgets of two seconds comfortably fit an isolated run and then expired
/// routinely under the full-target run, where they surfaced as unrelated-looking
/// expectation failures rather than as timeouts.
///
/// A generous budget costs nothing on the happy path: the poll returns as soon
/// as the predicate holds. It only lengthens a run that was going to fail
/// anyway, and the per-test execution allowance (60s, set by the make targets)
/// still bounds a genuine hang.
let defaultWaitTimeout: Duration = .seconds(30)

/// Polls `predicate` until it holds, or records a test issue once `timeout`
/// elapses.
///
/// Always prefer this over a bare `Task.sleep` followed by an assertion: a
/// fixed sleep either wastes time or is too short under load, and it asserts
/// nothing about what it waited for.
///
/// The timeout records an issue rather than returning silently. A silent
/// give-up (the pattern this helper replaces) reports "the async work had not
/// landed yet" as whatever assertion happens to come next, which reads like a
/// logic bug in the code under test.
///
/// - Parameters:
///   - description: What is being waited for, named in the timeout message.
///   - timeout: How long to wait before recording an issue.
///   - pollInterval: How long to sleep between evaluations of `predicate`.
///   - predicate: The condition to wait for. Evaluated on the caller's actor,
///     so it may touch main-actor state from a `@MainActor` suite.
func waitUntil(
    _ description: @autoclosure () -> String = "condition",
    timeout: Duration = defaultWaitTimeout,
    pollInterval: Duration = .milliseconds(5),
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ predicate: () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await predicate() { return }
        try? await Task.sleep(for: pollInterval)
    }
    // One last evaluation: the final sleep may have overshot the deadline just
    // as the condition became true.
    if await predicate() { return }
    Issue.record(
        "Timed out after \(timeout) waiting for \(description())",
        sourceLocation: sourceLocation
    )
}
