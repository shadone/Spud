//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SwiftUI

/// The single NSFW pill used across Discover, community headers, and post
/// surfaces. One definition so the badge reads identically everywhere.
struct NsfwBadge: View {
    var body: some View {
        Text("NSFW")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color(.systemRed), in: RoundedRectangle(cornerRadius: 4))
    }
}
