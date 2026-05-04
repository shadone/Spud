//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import OSLog

private let logger = Logger.utils

@propertyWrapper
public struct UserDefaultsBacked<Value: Codable & Sendable> {
    private let key: String
    private let defaultValue: Value
    private let storage: UserDefaults
    private let broadcaster: Broadcaster<Value>
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public var wrappedValue: Value {
        get {
            broadcaster.current
        }
        nonmutating set {
            set(newValue)
        }
    }

    /// AsyncStream of values. The first element is the current value;
    /// subsequent elements are emitted on every write through this
    /// instance's `wrappedValue`. The stream is unbounded — each consumer
    /// gets its own subscription, and dropping the iterator unregisters
    /// it. Writes from a different `UserDefaultsBacked` instance backed
    /// by the same key are not observed; consumers should subscribe to
    /// the instance that owns the writes.
    public var projectedValue: AsyncStream<Value> {
        broadcaster.subscribe()
    }

    public init(
        wrappedValue defaultValue: Value,
        key: String,
        storage: UserDefaults = .standard
    ) {
        self.defaultValue = defaultValue
        self.key = key
        self.storage = storage

        var maybeValue: Value?
        let rawValue = storage.value(forKey: key)
        if Value.self == Bool.self, let stringValue = rawValue as? String {
            // if we found a string stored where bool should be try check it for YES / NO
            if stringValue == "YES" {
                maybeValue = true as? Value
            } else if stringValue == "NO" {
                maybeValue = false as? Value
            }
        }

        if maybeValue == nil {
            if let stringValue = storage.string(forKey: key),
               let data = stringValue.data(using: .utf8)
            {
                do {
                    maybeValue = try decoder.decode(Value.self, from: data)
                } catch {
                    logger.error("""
                        Failed to decode '\(key, privacy: .public)' value from user defaults: \
                        \(error.localizedDescription, privacy: .public)
                        """)
                }
            }
        }

        broadcaster = Broadcaster(maybeValue ?? defaultValue)
    }

    private func set(_ newValue: Value) {
        if let optional = newValue as? (any AnyOptional), optional.isNil {
            storage.removeObject(forKey: key)
        } else {
            do {
                let data = try encoder.encode(newValue)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    logger.assertionFailure()
                    return
                }
                storage.setValue(jsonString, forKey: key)
            } catch {
                logger.error("""
                    Failed to encode '\(key, privacy: .public)' value for user defaults: \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        broadcaster.send(newValue)
    }
}

public extension UserDefaultsBacked where Value: ExpressibleByNilLiteral {
    init(key: String, storage: UserDefaults = .standard) {
        self.init(wrappedValue: nil, key: key, storage: storage)
    }
}

/// Holds the current value plus a set of AsyncStream continuations that
/// observe writes. Thread-safe via an internal lock; safe to pass across
/// isolation boundaries because the lock guards the only mutable state.
private final class Broadcaster<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _current: Value
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    init(_ initial: Value) {
        _current = initial
    }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return _current
    }

    func send(_ value: Value) {
        lock.lock()
        _current = value
        let snapshot = Array(continuations.values)
        lock.unlock()
        for continuation in snapshot {
            continuation.yield(value)
        }
    }

    func subscribe() -> AsyncStream<Value> {
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
