//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit
import Testing
@testable import Spud

struct DiagnosticEventTextTests {
    /// 2001-09-09T01:46:40Z — a fixed instant so the ISO8601 rendering is stable.
    private func event(instance: String? = nil, metadata: String? = nil) -> DiagnosticEventRecord {
        DiagnosticEventRecord(
            timestamp: 1_000_000_000.0,
            category: DiagnosticCategory.outbox.rawValue,
            level: DiagnosticLevel.error.rawValue,
            event: "op.permanentRollback",
            message: "Vote rolled back",
            instance: instance,
            metadata: metadata
        )
    }

    @Test
    func line_formatsTimestampLevelCategoryEventMessage() {
        #expect(
            DiagnosticEventText.line(event()) ==
                "2001-09-09T01:46:40.000Z [ERROR] outbox op.permanentRollback — Vote rolled back"
        )
    }

    @Test
    func line_appendsInstanceSuffixWhenPresent() {
        #expect(DiagnosticEventText.line(event(instance: "lemmy.world")).hasSuffix(" [lemmy.world]"))
        #expect(!DiagnosticEventText.line(event(instance: nil)).hasSuffix("]"))
    }

    @Test
    func line_unknownLevelRendersUnknown() {
        var e = event()
        e.level = 99 // not a known DiagnosticLevel
        #expect(DiagnosticEventText.line(e).contains("[UNKNOWN]"))
    }

    @Test
    func detail_appendsSortedMetadataBlock() throws {
        let text = DiagnosticEventText.detail(event(instance: "lemmy.world", metadata: #"{"status":"403","kind":"vote"}"#))
        #expect(text.hasPrefix(DiagnosticEventText.line(event(instance: "lemmy.world"))))
        #expect(text.contains("Metadata:"))
        #expect(text.contains("  kind: vote"))
        #expect(text.contains("  status: 403"))
        // Keys are sorted, so "kind" precedes "status".
        let kind = try #require(text.range(of: "kind"))
        let status = try #require(text.range(of: "status"))
        #expect(kind.lowerBound < status.lowerBound)
    }

    @Test
    func detail_withoutMetadata_equalsLine() {
        #expect(DiagnosticEventText.detail(event()) == DiagnosticEventText.line(event()))
    }
}
