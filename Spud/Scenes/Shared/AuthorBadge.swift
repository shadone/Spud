//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A small pill marking an author's role or status
/// (OP / MOD / ADMIN / BOT / BANNED / SUSPENDED). Pure value; a view renders it
/// via `makeAuthorBadgeView(_:accent:)`. Shared by the comment header line and
/// the post author line so both surfaces render identical pills.
struct AuthorBadge: Equatable {
    let text: String
    /// Optional leading SF Symbol (e.g. a bot/banned glyph).
    let symbolName: String?
    /// OP follows the app accent (resolved at render time); everything else uses
    /// `color` directly.
    let usesAccent: Bool
    let color: UIColor
    /// Solid fill (a distinguished moderator/admin statement) vs a tinted pill.
    let solid: Bool
}
