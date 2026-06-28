//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// The curated list of third-party dependencies Spud ships, with their
/// licenses. A static list (rather than a build-time scrape) is intentional:
/// it is small, stable, and lets us show readable summaries and the canonical
/// license text without a plugin in the build graph.
enum Acknowledgements {
    static let all: [Acknowledgement] = [
        Acknowledgement(
            name: "LemmyKit",
            summary: "Swift client for the Lemmy HTTP API, generated from an OpenAPI spec.",
            licenseName: "BSD-2-Clause",
            licenseText: License.bsd2Clause(holder: "Denis Dzyubenko"),
            url: "https://github.com/ddenis-info/LemmyKit"
        ),
        Acknowledgement(
            name: "GRDB.swift",
            summary: "SQLite toolkit backing Spud's local database.",
            licenseName: "MIT",
            licenseText: License.mit(holder: "Gwendal Roué"),
            url: "https://github.com/groue/GRDB.swift"
        ),
        Acknowledgement(
            name: "KeychainAccess",
            summary: "Wrapper around the iOS Keychain used for account credentials.",
            licenseName: "MIT",
            licenseText: License.mit(holder: "kishikawa katsumi"),
            url: "https://github.com/kishikawakatsumi/KeychainAccess"
        ),
        Acknowledgement(
            name: "SemVer",
            summary: "Semantic version parsing and comparison.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/sersoft-gmbh/semver"
        ),
        Acknowledgement(
            name: "swift-markdown",
            summary: "Markdown parsing (cmark-gfm) powering SpudMarkdownKit for post and comment bodies.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-markdown"
        ),
        Acknowledgement(
            name: "Nuke",
            summary: "Image loading and caching for thumbnails and the media viewer.",
            licenseName: "MIT",
            licenseText: License.mit(holder: "Alexander Grebenyuk"),
            url: "https://github.com/kean/Nuke"
        ),
        Acknowledgement(
            name: "swift-openapi-generator",
            summary: "Generates the LemmyKit API client from the OpenAPI document.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-openapi-generator"
        ),
        Acknowledgement(
            name: "swift-openapi-runtime",
            summary: "Runtime support for the generated OpenAPI client.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-openapi-runtime"
        ),
        Acknowledgement(
            name: "swift-openapi-urlsession",
            summary: "URLSession transport for the OpenAPI runtime.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-openapi-urlsession"
        ),
        Acknowledgement(
            name: "swift-collections",
            summary: "Additional data structures used by the OpenAPI stack.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-collections"
        ),
        Acknowledgement(
            name: "swift-algorithms",
            summary: "Sequence and collection algorithms.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-algorithms"
        ),
        Acknowledgement(
            name: "swift-http-types",
            summary: "Shared HTTP request/response value types.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/apple/swift-http-types"
        ),
        Acknowledgement(
            name: "Yams",
            summary: "YAML parsing for the OpenAPI document.",
            licenseName: "MIT",
            licenseText: License.mit(holder: "JP Simard"),
            url: "https://github.com/jpsim/Yams"
        ),
        Acknowledgement(
            name: "SBTUITestTunnel",
            summary: "In-app network stubbing for the UI test suite.",
            licenseName: "Apache-2.0",
            licenseText: License.apache2,
            url: "https://github.com/Subito-it/SBTUITestTunnel",
            isTestOnly: true
        ),
        Acknowledgement(
            name: "swift-snapshot-testing",
            summary: "Snapshot assertions for the snapshot test suite.",
            licenseName: "MIT",
            licenseText: License.mit(holder: "Point-Free, Inc."),
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            isTestOnly: true
        ),
    ]

    /// Dependencies shipped in the app binary.
    static var shipping: [Acknowledgement] {
        all.filter { !$0.isTestOnly }
    }

    /// Dependencies linked only into test targets.
    static var testOnly: [Acknowledgement] {
        all.filter(\.isTestOnly)
    }
}
