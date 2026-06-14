//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//
// Generates the bundled Lemmy Explorer seed used for first-launch / offline
// availability. Downloads the multipart datasets from data.lemmyverse.net,
// wraps each as { generatedAt, records: [...] }, and LZFSE-compresses them into
// SpudDataKit/Resources so the app ships with the full directory.
//
// Run from the repo root:  make explorer-seed   (or: swift scripts/generate-explorer-seed.swift)
// Re-run per release; runtime refresh keeps users current between releases.

import Foundation

let base = "https://data.lemmyverse.net/data"
let datasets = ["instance", "community"]

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDir = repoRoot.appendingPathComponent("SpudDataKit/Resources", isDirectory: true)

enum SeedError: Error { case badURL(String), badJSON(String) }

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

func fetch(_ urlString: String) throws -> Data {
    guard let url = URL(string: urlString) else { throw SeedError.badURL(urlString) }
    return try Data(contentsOf: url)
}

func downloadDataset(_ set: String) throws -> [Any] {
    let metaData = try fetch("\(base)/\(set).json")
    guard
        let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any],
        let count = meta["count"] as? Int
    else {
        throw SeedError.badJSON("\(set).json")
    }
    var all: [Any] = []
    for index in 0..<count {
        let partData = try fetch("\(base)/\(set)/\(index).json")
        guard let array = try JSONSerialization.jsonObject(with: partData) as? [Any] else {
            throw SeedError.badJSON("\(set)/\(index).json")
        }
        all.append(contentsOf: array)
        log("  \(set) part \(index + 1)/\(count) — \(all.count) records")
    }
    return all
}

func writeSeed(_ set: String, records: [Any]) throws {
    let payload: [String: Any] = [
        "generatedAt": Date().timeIntervalSince1970,
        "records": records,
    ]
    let json = try JSONSerialization.data(withJSONObject: payload, options: [])
    let compressed = try (json as NSData).compressed(using: .lzfse) as Data
    let outURL = resourcesDir.appendingPathComponent("explorer-\(set).seed.json.lzfse")
    try compressed.write(to: outURL)
    let rawMB = Double(json.count) / 1_048_576
    let lzfseMB = Double(compressed.count) / 1_048_576
    log(String(
        format: "Wrote %@ — %d records, %.1f MB raw -> %.2f MB lzfse",
        outURL.lastPathComponent, records.count, rawMB, lzfseMB
    ))
}

try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
for set in datasets {
    log("Downloading \(set)...")
    let records = try downloadDataset(set)
    try writeSeed(set, records: records)
}

log("Done.")
