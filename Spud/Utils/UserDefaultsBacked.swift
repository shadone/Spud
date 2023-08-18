//
// Copyright (c) 2021-2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Combine
import Foundation
import os.log
import SpudUtilKit
import SwiftUI

private let logger = Logger(.app)

@propertyWrapper
struct UserDefaultsBacked<Value: Codable> {
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
        if let optional = newValue as? (any AnyOptional), optional.isNil {
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
