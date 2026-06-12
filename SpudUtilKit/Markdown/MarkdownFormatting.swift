//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Pure, UI-independent markdown editing transforms.
///
/// These operate on a plain `String` plus a selected `Range<String.Index>`
/// (the caret/selection in a text view) and return a `MarkdownEdit`
/// describing the new text and the new selection. They contain no UIKit and
/// are fully unit-testable.
///
/// Two families of transform:
///   - inline wrappers (`bold`, `italic`, etc.) wrap the selection in a pair
///     of markers, toggling them off when the selection is already wrapped;
///   - line-prefix transforms (`quote`, lists) add (or strip) a prefix on
///     every line that the selection touches.
public enum MarkdownFormatting {
    /// The set of formatting actions a toolbar can invoke.
    public enum Action: String, Sendable, CaseIterable {
        case bold
        case italic
        case strikethrough
        case code
        case link
        case quote
        case unorderedList
        case orderedList
        case codeBlock
        case spoiler
    }

    /// The result of applying a transform: the replacement text for the whole
    /// document and the selection to install afterwards.
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let selectedRange: Range<String.Index>

        public init(text: String, selectedRange: Range<String.Index>) {
            self.text = text
            self.selectedRange = selectedRange
        }
    }

    /// Applies `action` to `text` at the given `selection`.
    public static func apply(
        _ action: Action,
        to text: String,
        selection: Range<String.Index>
    ) -> Edit {
        switch action {
        case .bold:
            inlineWrap(text, selection: selection, marker: "**", placeholder: "bold text")
        case .italic:
            inlineWrap(text, selection: selection, marker: "*", placeholder: "italic text")
        case .strikethrough:
            inlineWrap(text, selection: selection, marker: "~~", placeholder: "strikethrough")
        case .code:
            inlineWrap(text, selection: selection, marker: "`", placeholder: "code")
        case .link:
            linkWrap(text, selection: selection)
        case .quote:
            linePrefix(text, selection: selection, prefix: "> ")
        case .unorderedList:
            linePrefix(text, selection: selection, prefix: "- ")
        case .orderedList:
            orderedListPrefix(text, selection: selection)
        case .codeBlock:
            fence(text, selection: selection, fence: "```", placeholder: "code")
        case .spoiler:
            spoiler(text, selection: selection)
        }
    }

    // MARK: - Inline wrappers

    /// Wraps the selection in `marker` on each side. Toggles off when the
    /// selection (or the text immediately surrounding it) is already wrapped.
    /// When the selection is empty, inserts `marker placeholder marker` and
    /// selects the placeholder so the user can type over it.
    static func inlineWrap(
        _ text: String,
        selection: Range<String.Index>,
        marker: String,
        placeholder: String
    ) -> Edit {
        let selected = String(text[selection])

        // Already-wrapped inside the selection: e.g. selection == "**foo**".
        if selected.count >= marker.count * 2,
           selected.hasPrefix(marker),
           selected.hasSuffix(marker)
        {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return replace(text, selection, with: inner, selectInserted: true)
        }

        // Already-wrapped just outside the selection: markers sit immediately
        // before and after the selected range.
        if let outer = surroundingMarkerRange(text, selection: selection, marker: marker) {
            let unwrapped = String(text[selection])
            return replace(text, outer, with: unwrapped, selectInserted: true)
        }

        if selection.isEmpty {
            let inserted = marker + placeholder + marker
            return replace(
                text,
                selection,
                with: inserted,
                innerOffset: marker.count,
                innerLength: placeholder.count
            )
        }

        let inserted = marker + selected + marker
        return replace(
            text,
            selection,
            with: inserted,
            innerOffset: marker.count,
            innerLength: selected.count
        )
    }

    /// If `marker` sits immediately before `selection.lowerBound` and
    /// immediately after `selection.upperBound`, returns the range covering
    /// both markers plus the selection.
    private static func surroundingMarkerRange(
        _ text: String,
        selection: Range<String.Index>,
        marker: String
    ) -> Range<String.Index>? {
        guard
            let before = text.index(selection.lowerBound, offsetBy: -marker.count, limitedBy: text.startIndex),
            let after = text.index(selection.upperBound, offsetBy: marker.count, limitedBy: text.endIndex)
        else { return nil }
        guard
            String(text[before..<selection.lowerBound]) == marker,
            String(text[selection.upperBound..<after]) == marker
        else { return nil }
        return before..<after
    }

    // MARK: - Link

    /// Wraps the selection as `[selection](url)` and places the caret inside
    /// the empty `url` parens. With an empty selection, inserts
    /// `[text](url)` and selects the `text` placeholder.
    static func linkWrap(_ text: String, selection: Range<String.Index>) -> Edit {
        let selected = String(text[selection])
        if selected.isEmpty {
            let placeholder = "text"
            let inserted = "[\(placeholder)](url)"
            // Select the "text" placeholder.
            return replace(
                text,
                selection,
                with: inserted,
                innerOffset: 1,
                innerLength: placeholder.count
            )
        }
        let inserted = "[\(selected)](url)"
        // Place the caret on the "url" placeholder, selecting it so the user
        // can paste/type the destination.
        let urlOffset = 1 + selected.count + 2 // "[" + selection + "]("
        return replace(
            text,
            selection,
            with: inserted,
            innerOffset: urlOffset,
            innerLength: 3 // "url"
        )
    }

    // MARK: - Line prefixes

    /// Adds `prefix` to the start of every line the selection touches, or
    /// strips it from every such line when all of them already have it
    /// (toggle). Empty selection operates on the caret's line.
    static func linePrefix(
        _ text: String,
        selection: Range<String.Index>,
        prefix: String
    ) -> Edit {
        let block = lineBlockRange(text, selection: selection)
        let blockText = String(text[block])
        let lines = blockText.components(separatedBy: "\n")

        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) }
        let transformed: [String]
        if allPrefixed {
            transformed = lines.map { String($0.dropFirst(prefix.count)) }
        } else {
            transformed = lines.map { prefix + $0 }
        }
        let replacement = transformed.joined(separator: "\n")
        return replace(text, block, with: replacement, selectInserted: true)
    }

    /// Adds `1. `, `2. `, ... to each line the selection touches, or strips a
    /// leading `N. ` from every line when all are already numbered (toggle).
    static func orderedListPrefix(
        _ text: String,
        selection: Range<String.Index>
    ) -> Edit {
        let block = lineBlockRange(text, selection: selection)
        let blockText = String(text[block])
        let lines = blockText.components(separatedBy: "\n")

        let allNumbered = lines.allSatisfy { hasOrderedPrefix($0) }
        let transformed: [String]
        if allNumbered {
            transformed = lines.map { stripOrderedPrefix($0) }
        } else {
            transformed = lines.enumerated().map { index, line in "\(index + 1). " + line }
        }
        let replacement = transformed.joined(separator: "\n")
        return replace(text, block, with: replacement, selectInserted: true)
    }

    private static func hasOrderedPrefix(_ line: String) -> Bool {
        // Matches a leading "<digits>. ".
        var sawDigit = false
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            sawDigit = true
            index = line.index(after: index)
        }
        guard sawDigit else { return false }
        let remainder = line[index...]
        return remainder.hasPrefix(". ")
    }

    private static func stripOrderedPrefix(_ line: String) -> String {
        guard hasOrderedPrefix(line) else { return line }
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        // Drop the ". " too.
        index = line.index(index, offsetBy: 2)
        return String(line[index...])
    }

    // MARK: - Fenced blocks

    /// Wraps the selection in a fenced block on its own lines:
    /// ```\n<selection>\n```. Empty selection inserts the fence with a
    /// `placeholder` body, selected.
    static func fence(
        _ text: String,
        selection: Range<String.Index>,
        fence: String,
        placeholder: String
    ) -> Edit {
        let selected = String(text[selection])
        let leadingNewline = needsLeadingNewline(text, at: selection.lowerBound) ? "\n" : ""
        let body = selected.isEmpty ? placeholder : selected
        let inserted = "\(leadingNewline)\(fence)\n\(body)\n\(fence)\n"

        let innerOffset = leadingNewline.count + fence.count + 1 // fence + "\n"
        return replace(
            text,
            selection,
            with: inserted,
            innerOffset: innerOffset,
            innerLength: body.count
        )
    }

    // MARK: - Spoiler

    /// Wraps the selection in Lemmy's spoiler block:
    /// `::: spoiler title\n<selection>\n:::`. The caret selects the `title`
    /// placeholder so the user can name the spoiler.
    static func spoiler(_ text: String, selection: Range<String.Index>) -> Edit {
        let selected = String(text[selection])
        let leadingNewline = needsLeadingNewline(text, at: selection.lowerBound) ? "\n" : ""
        let title = "title"
        let body = selected.isEmpty ? "spoiler content" : selected
        let inserted = "\(leadingNewline)::: spoiler \(title)\n\(body)\n:::\n"

        let innerOffset = leadingNewline.count + "::: spoiler ".count
        return replace(
            text,
            selection,
            with: inserted,
            innerOffset: innerOffset,
            innerLength: title.count
        )
    }

    // MARK: - Helpers

    /// Whether inserting at `index` should be preceded by a newline so a block
    /// construct starts on its own line. True unless we are at the very start
    /// of the document or already immediately after a newline.
    private static func needsLeadingNewline(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return false }
        let prior = text.index(before: index)
        return text[prior] != "\n"
    }

    /// Expands `selection` to cover the full lines it touches: from the start
    /// of the line containing `lowerBound` to the end of the line containing
    /// `upperBound`.
    static func lineBlockRange(
        _ text: String,
        selection: Range<String.Index>
    ) -> Range<String.Index> {
        let lower = lineStart(text, before: selection.lowerBound)
        let upper = lineEnd(text, after: selection.upperBound)
        return lower..<upper
    }

    private static func lineStart(_ text: String, before index: String.Index) -> String.Index {
        var current = index
        while current > text.startIndex {
            let prior = text.index(before: current)
            if text[prior] == "\n" { break }
            current = prior
        }
        return current
    }

    private static func lineEnd(_ text: String, after index: String.Index) -> String.Index {
        var current = index
        while current < text.endIndex, text[current] != "\n" {
            current = text.index(after: current)
        }
        return current
    }

    /// Replaces `range` in `text` with `replacement` and selects the entire
    /// `replacement` (when `selectInserted`) or just the slice described by
    /// `innerOffset`/`innerLength` (a placeholder inside the replacement).
    private static func replace(
        _ text: String,
        _ range: Range<String.Index>,
        with replacement: String,
        selectInserted: Bool
    ) -> Edit {
        replace(
            text,
            range,
            with: replacement,
            innerOffset: 0,
            innerLength: selectInserted ? replacement.count : 0
        )
    }

    /// Core replacement. Computes the new string and a new selection by
    /// offsetting `innerOffset` characters into the inserted `replacement` and
    /// spanning `innerLength` characters. Index math is done via integer
    /// offsets from the replacement start so it survives the string rebuild.
    private static func replace(
        _ text: String,
        _ range: Range<String.Index>,
        with replacement: String,
        innerOffset: Int,
        innerLength: Int
    ) -> Edit {
        let prefixCount = text.distance(from: text.startIndex, to: range.lowerBound)

        var newText = text
        newText.replaceSubrange(range, with: replacement)

        let selectionStartOffset = prefixCount + innerOffset
        let start = newText.index(newText.startIndex, offsetBy: selectionStartOffset)
        let end = newText.index(start, offsetBy: innerLength)
        return Edit(text: newText, selectedRange: start..<end)
    }
}
