//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The testable core of the "Share as Image" editor (``ShareAsImageViewController``):
/// it owns the mutable ``ShareCardOptions`` and the per-card alt-text override,
/// exposes the direct-manipulation toggles the editor's tap overlay drives, and
/// writes the options back to `PreferencesService` on each output action.
///
/// The view controller is intentionally thin over this type so the option
/// mutations, depth clamping, alt-text lifecycle, and persistence are all
/// unit-testable without a live UIKit hierarchy (``ShareAsImageViewModelTests``).
///
/// Two guardrails are encoded here rather than in the UI:
/// - ``options`` `.chainDepth` is clamped to ``maxChainDepth`` (the ancestors
///   actually present in ``content``) at init and on every step, so a saved
///   "depth 8" never renders 8 non-existent ancestors on a 2-ancestor thread.
/// - ``persist()`` round-trips ``options`` through `PreferencesService`, whose
///   `Codable` implementation strips the runtime-only `nsfwRevealed` flag — so a
///   revealed NSFW card never becomes the default the next time the editor opens.
@MainActor
@Observable
final class ShareAsImageViewModel {
    /// The immutable content the card renders. Bound at init; a different post
    /// or comment means a fresh view model (and a fresh alt-text override), which
    /// is why the override lives here rather than in `PreferencesService`.
    let content: ShareCardContent

    private let preferencesService: PreferencesServiceType

    /// The live, user-configurable options. Mutated by the toggles below and
    /// read by the editor to reconfigure the preview card.
    private(set) var options: ShareCardOptions

    /// The user's hand-typed alt text for THIS card, or `nil` to use the
    /// auto-generated text (``ShareCardAltText``). Never persisted — it applies
    /// only to the card currently being edited.
    private(set) var altTextOverride: String?

    /// `true` while a Share/Save/Copy export (``ShareAsImageViewController+Output``)
    /// is in flight. Drives the output bar's disabled + spinner state and, via
    /// ``beginExport()``, guards the actions against re-entrancy: without this a
    /// rapid double-tap could render + write the image twice (double Photos save,
    /// doubled "Copied" toast).
    private(set) var isExporting = false

    init(content: ShareCardContent, preferencesService: PreferencesServiceType) {
        self.content = content
        self.preferencesService = preferencesService
        var options = preferencesService.shareAsImageOptions
        options.chainDepth = Self.clampedDepth(options.chainDepth, max: Self.maxDepth(for: content))
        self.options = options
    }

    // MARK: - Content-derived facts

    /// Whether this is a comment-chain card (`true`) or a post card (`false`).
    /// Drives whether the tray shows the chain-depth stepper.
    var isComment: Bool {
        content.kind == .comment
    }

    /// The largest selectable chain depth: the number of ancestors above the
    /// shared comment (`chain.count - 1`), or `0` for a post card. Also capped
    /// at the options model's own `0...8` ceiling.
    var maxChainDepth: Int {
        Self.maxDepth(for: content)
    }

    /// Whether the tray shows the chain-depth stepper. Gated on there being at
    /// least one ancestor to step through (``maxChainDepth`` > 0) — not merely
    /// on ``isComment``: a post card AND a root comment (a shared comment with
    /// no ancestors) both have `maxChainDepth == 0`, and showing a dead
    /// "Depth 0" stepper with both buttons disabled for the latter was a bug.
    var showsDepthStepper: Bool {
        maxChainDepth > 0
    }

    /// The alt text that will travel with the exported PNG and label the preview
    /// for VoiceOver: the user's override when set, else the auto-generated text
    /// derived from the current options (so it stays in sync as toggles change).
    var currentAltText: String {
        altTextOverride ?? ShareCardAltText.make(content: content, options: options)
    }

    /// `true` when no override is set — the alt text is auto-generated.
    var isAltTextAuto: Bool {
        altTextOverride == nil
    }

    // MARK: - Toggles (direct-manipulation tap targets)

    func toggleRedactIdentities() {
        options.redactIdentities.toggle()
    }

    func toggleCommunityAndCreator() {
        options.showCommunityAndCreator.toggle()
    }

    func toggleStats() {
        options.showStats.toggle()
    }

    func toggleMedia() {
        options.showMedia.toggle()
    }

    func toggleViaSpudMark() {
        options.showViaSpudMark.toggle()
    }

    func toggleIncludePostInChain() {
        options.includePostInChain.toggle()
    }

    /// Toggles the per-card NSFW reveal. Runtime-only — see ``persist()`` and
    /// ``ShareCardOptions/nsfwRevealed``.
    func toggleNsfwRevealed() {
        options.nsfwRevealed.toggle()
    }

    /// Cycles the body treatment `full` → `truncate` → `titleOnly` → `full`.
    func cycleBodyTreatment() {
        options.bodyTreatment = switch options.bodyTreatment {
        case .full: .truncate
        case .truncate: .titleOnly
        case .titleOnly: .full
        }
    }

    // MARK: - Tray controls

    func setAppearance(_ appearance: ShareCardOptions.Appearance) {
        options.appearance = appearance
    }

    func setCanvas(_ canvas: ShareCardOptions.Canvas) {
        options.canvas = canvas
    }

    func incrementChainDepth() {
        options.chainDepth = Self.clampedDepth(options.chainDepth + 1, max: maxChainDepth)
    }

    func decrementChainDepth() {
        options.chainDepth = Self.clampedDepth(options.chainDepth - 1, max: maxChainDepth)
    }

    // MARK: - Alt text

    /// Sets (or clears) the per-card alt-text override. A `nil` or
    /// whitespace-only value falls back to the auto-generated text.
    func setAltTextOverride(_ text: String?) {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            altTextOverride = nil
            return
        }
        altTextOverride = text
    }

    /// Restores the auto-generated alt text (clears any override).
    func resetAltTextToAuto() {
        altTextOverride = nil
    }

    // MARK: - Export in-flight guard

    /// Marks an export in flight. Returns `false` (and leaves the existing
    /// export untouched) if one is already running, so the caller — an output
    /// bar action — can treat a second tap while busy as a no-op rather than
    /// starting a second render/write in parallel with the first.
    @discardableResult
    func beginExport() -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        return true
    }

    /// Clears the in-flight flag once an export completes or fails. Callers
    /// must call this on every exit path (success, thrown error, or an early
    /// `return`) — typically via `defer`.
    func endExport() {
        isExporting = false
    }

    // MARK: - Export configuration

    /// The options to render the EXPORT card with, given a caller-supplied
    /// options snapshot and whether the media image actually resolved
    /// (`resolvedMedia`).
    ///
    /// Takes `options` explicitly (rather than reading ``options`` live) so the
    /// export renders from the snapshot captured when the output action fired —
    /// a tray/preview toggle during the media await can't retro-change what gets
    /// exported.
    ///
    /// Offline-first guardrail: when the card would show media (`options`
    /// `.showMedia` on, and the post carries a media URL) but the fetch never
    /// resolved an image, this drops the media section (`showMedia = false`) for
    /// the export — otherwise the fresh export card renders the "Loading media…"
    /// placeholder + shimmer band and bakes it permanently into the PNG (Spud is
    /// offline-first, so a failed/absent media fetch is a real path). Returns
    /// `options` unchanged when there is no media URL, or when the image did
    /// resolve. Pure and side-effect-free.
    func exportOptions(_ options: ShareCardOptions, resolvedMedia: Bool) -> ShareCardOptions {
        guard options.showMedia,
              !resolvedMedia,
              content.post?.mediaUrl != nil
        else { return options }
        var exported = options
        exported.showMedia = false
        return exported
    }

    // MARK: - Persistence

    /// Writes the current options back as the last-used configuration. Called on
    /// each output action (Share / Save / Copy / Done).
    ///
    /// The runtime-only NSFW reveal is stripped BEFORE writing, not left to
    /// ``ShareCardOptions``'s `Codable` implementation alone: that strips
    /// `nsfwRevealed` on the *storage round-trip* (a fresh launch / a fresh
    /// `PreferencesService` reading the key back from disk), but
    /// `@UserDefaultsBacked` caches the last-written value in memory verbatim, so
    /// reopening the editor in the SAME session would otherwise read back the
    /// reveal and auto-unblur the spoiler. Stripping here holds the "never
    /// auto-revealed" guardrail regardless of the cache. `options` itself keeps
    /// its runtime reveal so the live preview is unaffected.
    func persist() {
        var toSave = options
        toSave.nsfwRevealed = false
        preferencesService.shareAsImageOptions = toSave
    }

    // MARK: - Clamping

    private static func maxDepth(for content: ShareCardContent) -> Int {
        guard content.kind == .comment else { return 0 }
        // chain = ancestors + [destination]; ancestors above the shared comment
        // are everything but the destination.
        return min(max(content.chain.count - 1, 0), 8)
    }

    private static func clampedDepth(_ value: Int, max maxValue: Int) -> Int {
        min(max(value, 0), maxValue)
    }
}
