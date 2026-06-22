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
