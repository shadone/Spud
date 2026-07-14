//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import SpudUtilKit
import SwiftUI

/// The single "meta" pill marking a community that is about its own instance
/// (e.g. an announcements / site community). One definition so it reads
/// identically across Discover, the Communities tab, and search.
struct MetaCommunityBadge: View {
    var body: some View {
        Image(systemName: "building.2.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(.secondaryLabel))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel(Text("Instance community", comment: "Accessibility label for the meta-community badge"))
    }
}

extension CommunityListRow {
    /// Whether this directory row is a meta community. Directory rows carry no
    /// site name, so name-match degrades to the domain label; keyword match
    /// still applies.
    var isMetaCommunity: Bool {
        MetaCommunityClassifier.classify(
            name: name, title: title, instanceHost: instanceHost, siteName: nil
        ).isMeta
    }
}
