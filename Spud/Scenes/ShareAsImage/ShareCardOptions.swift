//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The user-configurable knobs for a share-as-image card, direct-manipulated
/// in the ``ShareAsImageViewController`` editor. Persisted as the last-used
/// configuration via `PreferencesService.shareAsImageOptions`, so reopening
/// the editor (even on a different post) restores the previous choices.
///
/// Two fields are deliberately NOT toggleable, encoding the card's "never
/// editorializes" guardrail: the footer permalink and the absolute timestamp
/// always render, in every configuration. There is no option to hide either
/// — see ``ShareCardContent`` and the card views (Task 2/3) for where that
/// guarantee is enforced in the rendering itself.
struct ShareCardOptions: Codable, Equatable {
    /// Card color scheme. Independent of the device's system appearance —
    /// the user picks explicitly, because a shared image should look
    /// intentional rather than following whatever mode the phone happened to
    /// be in when it was captured.
    enum Appearance: String, Codable {
        case light
        case dark
    }

    /// How much of the post body renders on the card.
    enum BodyTreatment: String, Codable {
        /// The full body, unclamped.
        case full
        /// Clamped to a fixed max height with a bottom fade + "Read the full
        /// post on Lemmy" link.
        case truncate
        /// No body at all — title only.
        case titleOnly
    }

    /// The exported image's aspect/backdrop.
    enum Canvas: String, Codable {
        /// The image hugs the card exactly (no backdrop).
        case native
        /// 1080x1080, card centered on a decorative backdrop.
        case square
        /// 1080x1920, card centered on a decorative backdrop.
        case story
    }

    var appearance: Appearance
    /// Whether the community lockup and the creator byline render together.
    /// The community and creator toggle as one unit (there is no way to show
    /// one without the other) — the community is the card's context, the
    /// creator is attribution; splitting them apart would either credit a
    /// community with no attribution or attribute a post with no context.
    var showCommunityAndCreator: Bool
    /// Whether the score/comment-count/vote-triangle stats row renders. When
    /// off, the absolute timestamp still renders alone, right-aligned — see
    /// the type-level guardrail note.
    var showStats: Bool
    /// Whether the post's image (when it has one) renders.
    var showMedia: Bool
    var bodyTreatment: BodyTreatment
    /// Whether every person (post creator + chain authors) is replaced with a
    /// striped/blurred placeholder circle and a redacted "u/•••••••" handle.
    /// The community is never redacted — it's the card's public context, not
    /// a private identity.
    var redactIdentities: Bool
    /// How many ancestors above the shared comment render in a chain card.
    /// Clamped to `0...8`; further clamped at content-population time to
    /// however many ancestors actually exist. Meaningless for a post card
    /// (``ShareCardContent/kind`` `.post`).
    var chainDepth: Int
    /// Whether a chain card's optional post header (community + title)
    /// renders above the ancestor chain.
    var includePostInChain: Bool
    var canvas: Canvas
    /// Whether the footer's "via Spud" wordmark renders. The permalink next
    /// to it is NOT toggleable — see the type-level guardrail note.
    var showViaSpudMark: Bool

    /// Whether a spoilered NSFW image is shown unblurred on THIS card.
    /// Deliberately NOT part of ``CodingKeys`` / never round-trips through
    /// `Codable` — see ``init(from:)`` / ``encode(to:)``. Runtime-only: a
    /// reveal must never survive to the next time the editor opens (even for
    /// the exact same post), so NSFW content is never auto-revealed just
    /// because it was revealed once before. Always decodes to `false`.
    var nsfwRevealed: Bool

    init(
        appearance: Appearance = .light,
        showCommunityAndCreator: Bool = true,
        showStats: Bool = true,
        showMedia: Bool = true,
        bodyTreatment: BodyTreatment = .truncate,
        redactIdentities: Bool = false,
        chainDepth: Int = 2,
        includePostInChain: Bool = true,
        canvas: Canvas = .native,
        showViaSpudMark: Bool = true,
        nsfwRevealed: Bool = false
    ) {
        self.appearance = appearance
        self.showCommunityAndCreator = showCommunityAndCreator
        self.showStats = showStats
        self.showMedia = showMedia
        self.bodyTreatment = bodyTreatment
        self.redactIdentities = redactIdentities
        self.chainDepth = Self.clampedChainDepth(chainDepth)
        self.includePostInChain = includePostInChain
        self.canvas = canvas
        self.showViaSpudMark = showViaSpudMark
        self.nsfwRevealed = nsfwRevealed
    }

    private static func clampedChainDepth(_ value: Int) -> Int {
        min(max(value, 0), 8)
    }

    // MARK: Codable

    /// Deliberately omits `nsfwRevealed` — see that property's doc comment.
    private enum CodingKeys: String, CodingKey {
        case appearance
        case showCommunityAndCreator
        case showStats
        case showMedia
        case bodyTreatment
        case redactIdentities
        case chainDepth
        case includePostInChain
        case canvas
        case showViaSpudMark
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decode(Appearance.self, forKey: .appearance)
        showCommunityAndCreator = try container.decode(Bool.self, forKey: .showCommunityAndCreator)
        showStats = try container.decode(Bool.self, forKey: .showStats)
        showMedia = try container.decode(Bool.self, forKey: .showMedia)
        bodyTreatment = try container.decode(BodyTreatment.self, forKey: .bodyTreatment)
        redactIdentities = try container.decode(Bool.self, forKey: .redactIdentities)
        chainDepth = try Self.clampedChainDepth(container.decode(Int.self, forKey: .chainDepth))
        includePostInChain = try container.decode(Bool.self, forKey: .includePostInChain)
        canvas = try container.decode(Canvas.self, forKey: .canvas)
        showViaSpudMark = try container.decode(Bool.self, forKey: .showViaSpudMark)
        // Never persisted: every decode starts unrevealed.
        nsfwRevealed = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(showCommunityAndCreator, forKey: .showCommunityAndCreator)
        try container.encode(showStats, forKey: .showStats)
        try container.encode(showMedia, forKey: .showMedia)
        try container.encode(bodyTreatment, forKey: .bodyTreatment)
        try container.encode(redactIdentities, forKey: .redactIdentities)
        try container.encode(chainDepth, forKey: .chainDepth)
        try container.encode(includePostInChain, forKey: .includePostInChain)
        try container.encode(canvas, forKey: .canvas)
        try container.encode(showViaSpudMark, forKey: .showViaSpudMark)
        // nsfwRevealed intentionally omitted - see its doc comment.
    }
}
