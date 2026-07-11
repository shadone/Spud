//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Decodes a loops.video public "hashid" shortcode into its numeric video id.
///
/// loops.video (the Pixelfed team's short-video platform) embeds an unsalted,
/// positional base-64 hashid in its share URLs (`/v/<shortcode>`); the public
/// video API is keyed by the decoded numeric id. The encoding is NOT RFC-4648
/// base64 — it is a plain positional base-64 over the 64-symbol alphabet below,
/// most-significant character first: `value = value * 64 + alphabetIndex(char)`.
///
/// Golden vector: `decode("gLbKEGRkoA") == "301511283332957732"`.
enum LoopsHashid {
    /// The 64-symbol alphabet loops-server uses, in positional order (index 0...63):
    /// digits, then lowercase, then uppercase, then `-` and `_`.
    private static let alphabet = Array(
        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
    )

    /// Decodes `shortcode` to its numeric id as a decimal string, or `nil` when the
    /// input is empty, longer than 10 characters, or contains any character outside
    /// the alphabet.
    ///
    /// The 10-character cap bounds the result to `64^10 - 1` (< `UInt64.max`), so the
    /// accumulator can never overflow; a longer value is rejected rather than
    /// silently wrapping.
    static func decode(_ shortcode: String) -> String? {
        guard !shortcode.isEmpty, shortcode.count <= 10 else {
            return nil
        }
        var value: UInt64 = 0
        for character in shortcode {
            guard let index = alphabet.firstIndex(of: character) else {
                return nil
            }
            value = value * 64 + UInt64(index)
        }
        return String(value)
    }
}
