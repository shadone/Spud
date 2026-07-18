//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// One direct-manipulation tap target laid over the editor's preview card: a
/// rect (in the overlay's coordinate space), the accessibility description of
/// what it represents and does, and the action a tap performs.
struct ShareAsImageTapRegion {
    /// The tappable rect, in the overlay's coordinate space (the card's native,
    /// un-scaled coordinates — the overlay is a sibling of the card inside the
    /// same scaled container).
    let rect: CGRect
    /// VoiceOver label — the element's name (e.g. "Community and author").
    let accessibilityLabel: String
    /// VoiceOver value — the element's current state (e.g. "Shown" / "Hidden").
    let accessibilityValue: String
    /// VoiceOver hint — what a tap does (e.g. "Double tap to hide").
    let accessibilityHint: String
    /// Runs on a tap inside ``rect`` (or a VoiceOver activation).
    let action: () -> Void
}

/// A transparent layer of direct-manipulation tap targets tracked to the
/// preview card's section frames. Tapping a region toggles the corresponding
/// card option; each region is also a first-class `UIAccessibilityElement` so a
/// VoiceOver user can reach and activate every toggle (the card sections
/// themselves are drawn, not real controls).
///
/// Regions are hit-tested last-first, so a smaller region added after a larger
/// one (e.g. the creator lockup inside the header) wins where they overlap.
final class ShareAsImageTapOverlayView: UIView {
    private var regions: [ShareAsImageTapRegion] = []
    private var elements: [UIAccessibilityElement] = []

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the tracked regions and rebuilds the accessibility elements.
    func setRegions(_ regions: [ShareAsImageTapRegion]) {
        self.regions = regions
        rebuildAccessibilityElements()
    }

    @objc
    private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        // Last region wins: overlapping smaller targets are added after larger
        // ones, so they take precedence where they intersect.
        guard let region = regions.last(where: { $0.rect.contains(point) }) else { return }
        region.action()
    }

    // MARK: - Accessibility

    private func rebuildAccessibilityElements() {
        elements = regions.map { region in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = region.accessibilityLabel
            element.accessibilityValue = region.accessibilityValue
            element.accessibilityHint = region.accessibilityHint
            element.accessibilityTraits = .button
            // Set the frame eagerly in the overlay's own (unscaled) container
            // space; `accessibilityFrameInContainerSpace` provides the geometry
            // tracking, converting it to the overlay's current on-screen (scaled)
            // frame — so it stays correct as the editor scales the preview.
            element.accessibilityFrameInContainerSpace = region.rect
            return element
        }
    }

    override var accessibilityElements: [Any]? {
        get { elements }
        set { }
    }
}
