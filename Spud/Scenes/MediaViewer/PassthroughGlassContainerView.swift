//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import UIKit

/// A `UIVisualEffectView` that can span a large area — up to an entire
/// screen — without becoming an opaque hit-test blocker for whatever sits
/// underneath it.
///
/// `UIGlassContainerEffect` needs its host view sized to cover every nested
/// `UIGlassEffect` element so it has room to compute the merge/morph
/// geometry between them (see the media viewer's `chromeGlassContainerView`,
/// which spans the whole screen to host a top bar and a bottom caption pill
/// far apart from each other). A plain `UIVisualEffectView` used that way is
/// dangerous: its default `hitTest` behaves like any ordinary view, and a
/// point inside its bounds that no nested subview claims still resolves to
/// the view itself — in practice to its own `contentView`, which is itself
/// a plain, fully-interactive `UIView` spanning those same bounds. For a
/// view sized to exactly one small bar that default is harmless (nothing
/// else is under a floating bar), but for a container deliberately sized to
/// the whole screen it would silently swallow every touch meant for the
/// content behind it — pinch-to-zoom, pan, tap-to-toggle-chrome, and paging
/// between images all live in a sibling view subtree, not inside this
/// container, so once it claims a point nothing beneath it ever sees that
/// touch.
///
/// This override keeps the normal recursive hit-test — so a nested
/// `UIGlassEffect` bar's own buttons/gestures are found exactly as they
/// would be without this class — but only reports a hit when a REAL nested
/// subview claimed the point. A hit that resolves to this view or its own
/// `contentView` means "nothing nested here claimed it," and is treated as
/// a miss so the touch falls through to whatever is behind the container.
final class PassthroughGlassContainerView: UIVisualEffectView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return (hit === self || hit === contentView) ? nil : hit
    }
}
