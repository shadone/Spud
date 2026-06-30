//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct DiagnosticEventRecordTests {
    // MARK: - DiagnosticLevel ordering

    @Test
    func level_ordering_debugLessThanError() {
        #expect(DiagnosticLevel.debug < DiagnosticLevel.error)
    }

    @Test
    func level_ordering_allCasesAscending() {
        #expect(DiagnosticLevel.debug < DiagnosticLevel.info)
        #expect(DiagnosticLevel.info < DiagnosticLevel.notice)
        #expect(DiagnosticLevel.notice < DiagnosticLevel.error)
    }

    // MARK: - databaseTableName

    @Test
    func databaseTableName_isCorrect() {
        #expect(DiagnosticEventRecord.databaseTableName == "diagnosticEvent")
    }

    // MARK: - metadataDictionary

    @Test
    func metadataDictionary_roundTripsJsonString() throws {
        let json = try JSONEncoder().encode(["httpStatus": "403"])
        let jsonString = String(bytes: json, encoding: .utf8)

        var record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.scheduler.rawValue,
            level: DiagnosticLevel.error.rawValue,
            event: "fetchFailed",
            message: "HTTP 403"
        )
        record.metadata = jsonString

        let dict = record.metadataDictionary
        #expect(dict == ["httpStatus": "403"])
    }

    @Test
    func metadataDictionary_nilWhenMetadataIsNil() {
        let record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.info.rawValue,
            event: "enqueued",
            message: "Item enqueued"
        )
        #expect(record.metadataDictionary == nil)
    }

    @Test
    func metadataDictionary_nilOnInvalidJson() {
        var record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.info.rawValue,
            event: "enqueued",
            message: "Item enqueued"
        )
        record.metadata = "not-valid-json"
        #expect(record.metadataDictionary == nil)
    }

    // MARK: - levelEnum / categoryEnum

    @Test
    func levelEnum_decodesKnownRawValue() {
        let record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.notice.rawValue,
            event: "test",
            message: "msg"
        )
        #expect(record.levelEnum == .notice)
    }

    @Test
    func categoryEnum_decodesKnownRawValue() {
        let record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.scheduler.rawValue,
            level: DiagnosticLevel.debug.rawValue,
            event: "test",
            message: "msg"
        )
        #expect(record.categoryEnum == .scheduler)
    }

    @Test
    func levelEnum_nilForUnknownRawValue() {
        let record = DiagnosticEventRecord(
            timestamp: 0,
            category: DiagnosticCategory.outbox.rawValue,
            level: 999,
            event: "test",
            message: "msg"
        )
        #expect(record.levelEnum == nil)
    }

    @Test
    func categoryEnum_nilForUnknownRawValue() {
        let record = DiagnosticEventRecord(
            timestamp: 0,
            category: "unknownCategory",
            level: DiagnosticLevel.info.rawValue,
            event: "test",
            message: "msg"
        )
        #expect(record.categoryEnum == nil)
    }
}
