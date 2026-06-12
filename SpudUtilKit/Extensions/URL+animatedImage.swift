//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension URL {
    /// True when the URL points at an animated image format (GIF) that should
    /// play in the full-screen viewer and show a badge inline. Mirrors the
    /// content detector's extension check.
    var isAnimatedImage: Bool {
        pathExtension.lowercased() == "gif"
    }
}
