//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import os.log

private let logger = Logger(.app)

// https://www.swiftbysundell.com/articles/property-wrappers-in-swift/

// Since our property wrapper's Value type isn't optional, but
// can still contain nil values, we'll have to introduce this
// protocol to enable us to cast any assigned value into a type
// that we can compare against nil:
private protocol AnyOptional {
    var isNil: Bool { get }
}

extension Optional: AnyOptional {
    var isNil: Bool { self == nil }
}

@propertyWrapper struct UserDefaultsBacked<Value: Codable> {
    private let key: String
    private let defaultValue: Value
    private let storage: UserDefaults
    private let valuePublisher: CurrentValueSubject<Value, Never>
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var wrappedValue: Value {
        get {
            valuePublisher.value
        }
        set {
            set(newValue)
        }
    }

    var projectedValue: AnyPublisher<Value, Never> {
        valuePublisher.eraseToAnyPublisher()
    }

    init(
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

        valuePublisher = CurrentValueSubject(maybeValue ?? defaultValue)
    }

    private func set(_ newValue: Value) {
        if let optional = newValue as? AnyOptional, optional.isNil {
            storage.removeObject(forKey: key)
        } else {
            do {
                let data = try encoder.encode(newValue)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    assertionFailure()
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
        valuePublisher.send(newValue)
    }
}

extension UserDefaultsBacked where Value: ExpressibleByNilLiteral {
    init(key: String, storage: UserDefaults = .standard) {
        self.init(wrappedValue: nil, key: key, storage: storage)
    }
}
