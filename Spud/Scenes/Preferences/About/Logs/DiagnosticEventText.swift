//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudDataKit

/// Plain-text renderings of a ``DiagnosticEventRecord``, shared by the event-log
/// export (`shareText`), the per-row "Copy" action, and the Event Detail "Copy
/// Event" action so the three stay in lockstep.
enum DiagnosticEventText {
    /// A one-line summary of a single event:
    /// `<ISO8601 timestamp> [<LEVEL>] <category> <event> — <message> [instance]`
    ///
    /// The instance suffix is omitted when nil. This is the unit `shareText`
    /// joins with newlines and the "Copy" row action copies.
    static func line(_ event: DiagnosticEventRecord) -> String {
        // A local formatter (ISO8601DateFormatter is non-Sendable, so it can't be a
        // shared static here); this matches the detail view and the former inline
        // shareText. The export is user-initiated and infrequent, so the per-call
        // allocation is immaterial.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date(timeIntervalSince1970: event.timestamp))
        let levelLabel = event.levelEnum.map(label(for:)) ?? "UNKNOWN"
        var line = "\(timestamp) [\(levelLabel)] \(event.category) \(event.event) — \(event.message)"
        if let instance = event.instance {
            line += " [\(instance)]"
        }
        return line
    }

    /// The full event as copyable text: the ``line(_:)`` summary followed by a
    /// sorted `Metadata:` block when the event carries metadata. Backs the Event
    /// Detail "Copy Event" action.
    static func detail(_ event: DiagnosticEventRecord) -> String {
        var text = line(event)
        if let dict = event.metadataDictionary, !dict.isEmpty {
            let rows = dict.keys.sorted().map { "  \($0): \(dict[$0] ?? "")" }
            text += "\nMetadata:\n" + rows.joined(separator: "\n")
        }
        return text
    }

    /// Short uppercase level label used in the plain-text renderings.
    private static func label(for level: DiagnosticLevel) -> String {
        switch level {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .notice: "NOTICE"
        case .error: "ERROR"
        }
    }
}
