//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A single third-party dependency shown on the Acknowledgements screen.
struct Acknowledgement: Identifiable, Hashable {
    var id: String {
        name
    }

    /// Display name of the dependency.
    let name: String
    /// One-line description of what it does / why Spud uses it.
    let summary: String
    /// SPDX short license identifier, e.g. "MIT", "Apache-2.0", "BSD-2-Clause".
    let licenseName: String
    /// The full license text, shown on the detail screen.
    let licenseText: String
    /// Project home page.
    let url: URL
    /// Whether the dependency is only linked into test targets.
    let isTestOnly: Bool

    init(
        name: String,
        summary: String,
        licenseName: String,
        licenseText: String,
        url: String,
        isTestOnly: Bool = false
    ) {
        self.name = name
        self.summary = summary
        self.licenseName = licenseName
        self.licenseText = licenseText
        // The URLs are compile-time constants from the curated list below.
        self.url = URL(string: url) ?? URL(string: "https://spud.ddenis.info")!
        self.isTestOnly = isTestOnly
    }
}
