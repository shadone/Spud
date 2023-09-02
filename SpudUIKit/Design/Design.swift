//
// Copyright (c) 2023, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Namespace.
public enum Design { }

public extension Design {
    enum Post {
        public static let upvoteButton = SymbolImageResource(systemName: "arrow.up")

        public static let downvoteButton = SymbolImageResource(systemName: "arrow.down")
    }
}
