//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

enum MediaKind: Equatable { case image, audio, video }

/// Classifies a media URL by file extension. Defaults to `.image` (a bare
/// image link with no extension is the common pict-rs case).
enum MediaDetector {
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "ogg", "oga", "opus", "flac"]
    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv"]

    static func kind(of url: URL) -> MediaKind {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) { return .audio }
        if videoExtensions.contains(ext) { return .video }
        return .image
    }
}
