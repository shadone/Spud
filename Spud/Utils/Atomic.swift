//
// Copyright (c) 2020-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

@propertyWrapper struct Atomic<Value> {
    private let lock = NSLock()

    private var value: Value

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }

    init(wrappedValue: Value) {
        self.value = wrappedValue
    }
}
