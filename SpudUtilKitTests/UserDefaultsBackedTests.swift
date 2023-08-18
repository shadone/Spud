//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

private let defaultsForTesting = UserDefaults(suiteName: "UserDefaultsBackedTests")!

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

class UserDefaultsBackedTests: XCTestCase {
    override func setUp() async throws {
        resetDefaults()
    }

    private func resetDefaults() {
        let allKeys = defaultsForTesting.dictionaryRepresentation().keys
        allKeys.forEach { key in
            defaultsForTesting.removeObject(forKey: key)
        }
    }

    func testWriting() throws {
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-integer-value"))
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-float-value"))
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-bool-value"))
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-string-value"))
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-compound-value"))
        XCTAssertNil(defaultsForTesting.value(forKey: "i-am-optional-string-value"))

        var testData = TestData()
        testData.integerValue = 99
        testData.floatValue = 42.42
        testData.boolValue = true
        testData.stringValue = "Hello World"
        testData.compoundValue = .init(stringValue: "foo", intValue: 88, boolValue: true)
        testData.optionalStringValue = "Duh"

        let secondData = TestData()

        XCTAssertEqual(testData.integerValue, 99)
        XCTAssertEqual(testData.integerValue, secondData.integerValue)

        XCTAssertEqual(testData.floatValue, 42.42)
        XCTAssertEqual(testData.floatValue, secondData.floatValue)

        XCTAssertEqual(testData.boolValue, true)
        XCTAssertEqual(testData.boolValue, secondData.boolValue)

        XCTAssertEqual(testData.stringValue, "Hello World")
        XCTAssertEqual(testData.stringValue, secondData.stringValue)

        XCTAssertEqual(testData.compoundValue.stringValue, "foo")
        XCTAssertEqual(testData.compoundValue.intValue, 88)
        XCTAssertEqual(testData.compoundValue.boolValue, true)
        XCTAssertEqual(testData.compoundValue, secondData.compoundValue)

        XCTAssertEqual(testData.optionalStringValue, "Duh")
        XCTAssertEqual(testData.optionalStringValue, secondData.optionalStringValue)

        XCTAssertEqual(
            defaultsForTesting.integer(forKey: "i-am-integer-value"),
            99
        )

        XCTAssertEqual(
            defaultsForTesting.string(forKey: "i-am-string-value"),
            "\"Hello World\""
        )
    }
}
