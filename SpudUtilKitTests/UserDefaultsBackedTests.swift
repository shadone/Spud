//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

/// UserDefaults is documented as thread-safe; `nonisolated(unsafe)` is the
/// idiomatic way to expose it as a global under Swift 6 strict concurrency.
private nonisolated(unsafe) let defaultsForTesting = UserDefaults(suiteName: "UserDefaultsBackedTests")!

private struct TestData {
    @UserDefaultsBacked(key: "i-am-integer-value", storage: defaultsForTesting)
    var integerValue: Int = 5

    @UserDefaultsBacked(key: "i-am-float-value", storage: defaultsForTesting)
    var floatValue: Float = 1.2

    @UserDefaultsBacked(key: "i-am-bool-value", storage: defaultsForTesting)
    var boolValue: Bool = false

    @UserDefaultsBacked(key: "i-am-string-value", storage: defaultsForTesting)
    var stringValue: String = "default value"

    struct Compound: Codable, Equatable {
        let stringValue: String
        let intValue: Int
        let boolValue: Bool
    }

    @UserDefaultsBacked(key: "i-am-compound-value", storage: defaultsForTesting)
    var compoundValue: Compound = .init(stringValue: "", intValue: 0, boolValue: false)

    @UserDefaultsBacked(key: "i-am-optional-string-value", storage: defaultsForTesting)
    var optionalStringValue: String?
}

struct UserDefaultsBackedTests {
    init() {
        resetDefaults()
    }

    private func resetDefaults() {
        let allKeys = defaultsForTesting.dictionaryRepresentation().keys
        for key in allKeys {
            defaultsForTesting.removeObject(forKey: key)
        }
    }

    @Test
    func writing() {
        #expect(defaultsForTesting.value(forKey: "i-am-integer-value") == nil)
        #expect(defaultsForTesting.value(forKey: "i-am-float-value") == nil)
        #expect(defaultsForTesting.value(forKey: "i-am-bool-value") == nil)
        #expect(defaultsForTesting.value(forKey: "i-am-string-value") == nil)
        #expect(defaultsForTesting.value(forKey: "i-am-compound-value") == nil)
        #expect(defaultsForTesting.value(forKey: "i-am-optional-string-value") == nil)

        var testData = TestData()
        testData.integerValue = 99
        testData.floatValue = 42.42
        testData.boolValue = true
        testData.stringValue = "Hello World"
        testData.compoundValue = .init(stringValue: "foo", intValue: 88, boolValue: true)
        testData.optionalStringValue = "Duh"

        let secondData = TestData()

        #expect(testData.integerValue == 99)
        #expect(testData.integerValue == secondData.integerValue)

        #expect(testData.floatValue == 42.42)
        #expect(testData.floatValue == secondData.floatValue)

        #expect(testData.boolValue == true)
        #expect(testData.boolValue == secondData.boolValue)

        #expect(testData.stringValue == "Hello World")
        #expect(testData.stringValue == secondData.stringValue)

        #expect(testData.compoundValue.stringValue == "foo")
        #expect(testData.compoundValue.intValue == 88)
        #expect(testData.compoundValue.boolValue == true)
        #expect(testData.compoundValue == secondData.compoundValue)

        #expect(testData.optionalStringValue == "Duh")
        #expect(testData.optionalStringValue == secondData.optionalStringValue)

        #expect(
            defaultsForTesting.integer(forKey: "i-am-integer-value") ==
                99
        )

        #expect(
            defaultsForTesting.string(forKey: "i-am-string-value") ==
                "\"Hello World\""
        )
    }
}
