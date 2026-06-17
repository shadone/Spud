//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
// Generates the "Open in Spud" Safari content-script allowlist from the bundled
// Lemmy Explorer instance seed. Every known instance host becomes a
// `*://<host>/*` match pattern, so the content script (and its banner) only runs
// on recognized Lemmy instances. The script then verifies the page path before
// showing the banner, so matching all paths of a known host is fine.
//
// The list is static and goes stale between seed updates; brand-new instances
// get no banner (the share-sheet action extension still covers them). Re-run
// after regenerating the Explorer seed.
//
// Run from the repo root:  make safari-matches   (or: swift scripts/generate-safari-matches.swift)

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let seedURL = repoRoot
    .appendingPathComponent("SpudDataKit/Resources/explorer-instance.seed.json.lzfse")
let manifestURL = repoRoot
    .appendingPathComponent("OpenInAppExtension/Resources/manifest.json")

enum GenError: Error { case shape(String) }

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

/// Reduces a seed `baseurl` to a bare lowercase host (defensive against an
/// occasional scheme or trailing path sneaking into the dataset).
func normalizeHost(_ raw: String) -> String? {
    var host = raw.lowercased()
    if let schemeRange = host.range(of: "://") {
        host = String(host[schemeRange.upperBound...])
    }
    if let slash = host.firstIndex(of: "/") {
        host = String(host[..<slash])
    }
    host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    guard !host.isEmpty, host.contains(".") else { return nil }
    return host
}

let compressed = try Data(contentsOf: seedURL)
let json = try (compressed as NSData).decompressed(using: .lzfse) as Data

guard
    let payload = try JSONSerialization.jsonObject(with: json) as? [String: Any],
    let records = payload["records"] as? [[String: Any]]
else {
    throw GenError.shape("instance seed is not { records: [...] }")
}

var hosts = Set<String>()
for record in records {
    guard let baseurl = record["baseurl"] as? String, let host = normalizeHost(baseurl) else { continue }
    hosts.insert(host)
}

let matches = hosts.sorted().map { "*://\($0)/*" }
log("collected \(matches.count) instance hosts")

guard
    var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any],
    var contentScripts = manifest["content_scripts"] as? [[String: Any]],
    !contentScripts.isEmpty
else {
    throw GenError.shape("manifest.json has no content_scripts[0]")
}

contentScripts[0]["matches"] = matches
manifest["content_scripts"] = contentScripts

let data = try JSONSerialization.data(
    withJSONObject: manifest,
    options: [.prettyPrinted, .sortedKeys]
)
// JSONSerialization escapes "/" as "\/"; unescape for readable URL patterns.
guard var text = String(data: data, encoding: .utf8) else {
    throw GenError.shape("could not stringify manifest")
}

text = text.replacingOccurrences(of: "\\/", with: "/")
if !text.hasSuffix("\n") { text += "\n" }

try text.write(to: manifestURL, atomically: true, encoding: .utf8)
log("wrote \(matches.count) match patterns to \(manifestURL.path)")
