# PeerTube Video Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PeerTube as the second concrete host in the video-host seam, so PeerTube video posts classify as video and play inline (mp4 or HLS) via the existing player, with browser fallback.

**Architecture:** Purely additive to the shipped streamable seam. A new `PeerTubeVideoHost` reuses `VideoLinkParser`'s (SpudUtilKit) existing PeerTube shape heuristic for recognition and resolves via the instance's `/api/v1/videos/<id>` REST API (progressive mp4 preferred, HLS `.m3u8` playlist as fallback). Appending it to `VideoHostRegistry`'s default hosts wires it into both feed classification (`PostContentDetectorService`) and tap playback (`playVideo`) at once — nothing else in the seam changes.

**Tech Stack:** Swift 6 (complete strict concurrency), Foundation/URLSession, AVKit (HLS via `AVPlayer`), Swift Testing, XcodeGen.

## Global Constraints

- **Strict concurrency:** Swift 6 language mode + `SWIFT_STRICT_CONCURRENCY = complete`. `PeerTubeVideoHost` is a `Sendable` value type holding a `@Sendable` fetch closure (mirrors `StreamableVideoHost`). No `@preconcurrency` / `@unchecked`.
- **Name collision (must handle):** SpudUtilKit exports a public enum also named `VideoHost` (used by `VideoLinkParser`). The new file imports SpudUtilKit, so the unqualified name `VideoHost` is ambiguous. Qualify the protocol conformance as `SpudDataKit.VideoHost`; the enum case `.peertube` on a `VideoLink.host` value resolves by context. Do NOT rename SpudUtilKit's enum (out of scope).
- **SpudDataKit may import SpudUtilKit** (dependency direction allows it); the new file needs `import SpudUtilKit` for `VideoLinkParser`.
- **No emojis** anywhere (code, comments, commit messages).
- **Conventional commit** subjects.
- **New source files require `make project`** (from the `Spud/` directory) before they compile — the `.xcodeproj` is XcodeGen-generated and gitignored.
- **`import Testing` does not re-export Foundation** — test files need `import Foundation`.
- **Confirm test success** by the `✔ Test run with N tests in M suites passed` line (Swift-Testing results do NOT appear in xcodebuild's "Executed N tests" summary). Benign noise (keychain OSStatus, deliberate error-path logs) is not failure.
- **Run `mint run swiftformat <paths>` BEFORE committing**, never after.
- **iOS 18+ SDK** — `URL.host()` (iOS 16+) is available.

Test command (single SpudDataKit suite):
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/<SuiteName> \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Sim contention ("Simulator ... Busy (Application failed preflight checks)") → target the booted sim by id: `xcrun simctl list devices | grep Booted`, then `-destination 'platform=iOS Simulator,id=<UUID>'`.

---

### Task 1: `PeerTubeVideoHost` (recognition + resolution)

Add the `.peertube` kind and the new host (recognize via `VideoLinkParser`, resolve via the PeerTube API), with unit tests. Not yet in the registry, so it compiles and is unit-tested in isolation.

**Files:**
- Modify: `SpudDataKit/Services/VideoHost/VideoHostTypes.swift` (add enum case)
- Create: `SpudDataKit/Services/VideoHost/PeerTubeVideoHost.swift`
- Test: `SpudDataKitTests/PeerTubeVideoHostTests.swift`

**Interfaces:**
- Consumes (existing): `VideoHost` protocol, `VideoHostKind`, `VideoHostMatch`, `ResolvedVideo`, `VideoHostResolutionError` (all in `SpudDataKit/Services/VideoHost/VideoHostTypes.swift`); `VideoLinkParser.parse(_ url: URL) -> VideoLink?` with `VideoLink.host: VideoHost` (SpudUtilKit enum, case `.peertube`) and `VideoLink.videoId: String` (SpudUtilKit).
- Produces (used by Task 2): `public struct PeerTubeVideoHost` with `init(fetch:)` and `kind == .peertube`; `VideoHostKind.peertube`.

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/PeerTubeVideoHostTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PeerTubeVideoHostRecognitionTests {
    private let host = PeerTubeVideoHost()

    private func match(_ string: String) -> VideoHostMatch? {
        host.recognize(URL(string: string)!)
    }

    @Test
    func recognizesShortWatchForm() {
        let m = match("https://tube.example/w/kR2p9qXy")
        #expect(m?.kind == .peertube)
        #expect(m?.identifier == "kR2p9qXy")
        #expect(m?.pageUrl.absoluteString == "https://tube.example/w/kR2p9qXy")
    }

    @Test
    func recognizesLongWatchUuidForm() {
        let uuid = "0e3c8d2a-1234-4abc-9def-0123456789ab"
        #expect(match("https://tube.example/videos/watch/\(uuid)")?.identifier == uuid)
    }

    @Test
    func doesNotClaimYouTube() {
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == nil)
    }

    @Test
    func rejectsNonVideoUrls() {
        #expect(match("https://example.com/some/article") == nil)
        // "abc" is < 6 chars, so VideoLinkParser's isPeerTubeId rejects it.
        #expect(match("https://tube.example/w/abc") == nil)
    }
}

struct PeerTubeVideoHostResolutionTests {
    private func host(returning json: String?) -> PeerTubeVideoHost {
        PeerTubeVideoHost(fetch: { _ in json.map { Data($0.utf8) } })
    }

    private let match = VideoHostMatch(
        kind: .peertube,
        identifier: "kR2p9qXy",
        pageUrl: URL(string: "https://tube.example/w/kR2p9qXy")!
    )

    @Test
    func picksHighestResolutionProgressiveFile() async throws {
        let json = """
        {"name":"Clip","previewPath":"/static/previews/x.jpg",\
        "files":[{"fileUrl":"https://tube.example/static/720.mp4","resolution":{"id":720}},\
        {"fileUrl":"https://tube.example/static/1080.mp4","resolution":{"id":1080}}]}
        """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/static/1080.mp4")
        #expect(resolved.posterUrl?.absoluteString == "https://tube.example/static/previews/x.jpg")
        #expect(resolved.title == "Clip")
    }

    @Test
    func fallsBackToHlsPlaylistWhenNoProgressiveFiles() async throws {
        let json = """
        {"name":"HLS","files":[],\
        "streamingPlaylists":[{"playlistUrl":"https://tube.example/static/hls/master.m3u8","files":[]}]}
        """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/static/hls/master.m3u8")
    }

    @Test
    func prefersNestedProgressiveFileOverPlaylist() async throws {
        let json = """
        {"files":[],"streamingPlaylists":[{"playlistUrl":"https://tube.example/hls/master.m3u8",\
        "files":[{"fileUrl":"https://tube.example/hls/1080.mp4","resolution":{"id":1080}}]}]}
        """
        let resolved = try await host(returning: json).resolve(match)
        #expect(resolved.streamUrl.absoluteString == "https://tube.example/hls/1080.mp4")
    }

    @Test
    func throwsNetworkWhenFetchReturnsNil() async {
        await #expect(throws: VideoHostResolutionError.network) {
            try await host(returning: nil).resolve(match)
        }
    }

    @Test
    func throwsDecodingOnGarbage() async {
        await #expect(throws: VideoHostResolutionError.decoding) {
            try await host(returning: "not json").resolve(match)
        }
    }

    @Test
    func throwsNoPlayableFileWhenEmpty() async {
        let json = #"{"name":"empty","files":[],"streamingPlaylists":[]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json).resolve(match)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail (do not compile)**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PeerTubeVideoHostRecognitionTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build FAILS — `cannot find 'PeerTubeVideoHost' in scope`.

- [ ] **Step 3: Add the `.peertube` kind**

In `SpudDataKit/Services/VideoHost/VideoHostTypes.swift`, change:
```swift
public enum VideoHostKind: Equatable, Sendable {
    case streamable
}
```
to:
```swift
public enum VideoHostKind: Equatable, Sendable {
    case streamable
    case peertube
}
```
(No exhaustive switch over `VideoHostKind` exists — `VideoHostRegistry` dispatches by `==` — so adding a case compiles cleanly.)

- [ ] **Step 4: Create the PeerTube host**

Create `SpudDataKit/Services/VideoHost/PeerTubeVideoHost.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Recognizes PeerTube video URLs (reusing ``VideoLinkParser``'s shape heuristic)
/// and resolves them to a playable stream via the instance's REST API
/// (`https://<instance>/api/v1/videos/<id>`).
///
/// PeerTube is federated, so recognition is a URL-shape heuristic with no host
/// allowlist: a false positive resolves against a non-PeerTube API, fails to
/// decode, and falls back to opening the page in the browser. The instance API is
/// the video's own source host, consistent with Spud's posture of talking to the
/// content source rather than a third-party aggregator.
///
/// `VideoHost` is qualified as `SpudDataKit.VideoHost` because `import SpudUtilKit`
/// also brings a same-named enum (`VideoLinkParser`'s host kind) into scope.
public struct PeerTubeVideoHost: SpudDataKit.VideoHost {
    public let kind: VideoHostKind = .peertube

    private let fetch: @Sendable (URL) async -> Data?

    /// - Parameter fetch: injected so tests can stub the API response.
    public init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let link = VideoLinkParser.parse(url), link.host == .peertube else {
            return nil
        }
        return VideoHostMatch(kind: .peertube, identifier: link.videoId, pageUrl: url)
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .peertube,
              let host = match.pageUrl.host(),
              let apiUrl = URL(string: "https://\(host)/api/v1/videos/\(match.identifier)")
        else {
            throw VideoHostResolutionError.unresolvable
        }

        guard let data = await fetch(apiUrl) else {
            throw VideoHostResolutionError.network
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw VideoHostResolutionError.decoding
        }

        let streamUrl = try Self.playableStreamUrl(from: response)
        let posterPath = response.previewPath ?? response.thumbnailPath
        let posterUrl = posterPath.flatMap { URL(string: "https://\(host)\($0)") }

        return ResolvedVideo(streamUrl: streamUrl, posterUrl: posterUrl, title: response.name)
    }

    /// Prefer the highest-resolution progressive mp4 (from `files` or the HLS
    /// playlists' own files); fall back to an HLS `.m3u8` playlist that AVPlayer
    /// streams natively. Throw `.noPlayableFile` if neither exists.
    private static func playableStreamUrl(from response: Response) throws -> URL {
        let progressive = (response.files ?? [])
            + (response.streamingPlaylists ?? []).flatMap { $0.files ?? [] }
        let best = progressive
            .compactMap { file -> (url: String, res: Int)? in
                guard let url = file.fileUrl else { return nil }
                return (url, file.resolution?.id ?? 0)
            }
            .max { $0.res < $1.res }

        if let best, let url = URL(string: best.url) {
            return url
        }
        if let playlist = (response.streamingPlaylists ?? []).compactMap({ $0.playlistUrl }).first,
           let url = URL(string: playlist) {
            return url
        }
        throw VideoHostResolutionError.noPlayableFile
    }

    private struct Response: Decodable {
        struct Resolution: Decodable {
            let id: Int?
        }

        struct File: Decodable {
            let fileUrl: String?
            let resolution: Resolution?
        }

        struct StreamingPlaylist: Decodable {
            let playlistUrl: String?
            let files: [File]?
        }

        let name: String?
        let thumbnailPath: String?
        let previewPath: String?
        let files: [File]?
        let streamingPlaylists: [StreamingPlaylist]?
    }
}
```

- [ ] **Step 5: Regenerate the project**

Run: `make project`
Expected: `Created project at .../Spud.xcodeproj`.

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PeerTubeVideoHostRecognitionTests \
  -only-testing:SpudDataKitTests/PeerTubeVideoHostResolutionTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 10 tests in 2 suites passed`.

- [ ] **Step 7: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/PeerTubeVideoHost.swift SpudDataKit/Services/VideoHost/VideoHostTypes.swift SpudDataKitTests/PeerTubeVideoHostTests.swift
git add SpudDataKit/Services/VideoHost/PeerTubeVideoHost.swift SpudDataKit/Services/VideoHost/VideoHostTypes.swift SpudDataKitTests/PeerTubeVideoHostTests.swift
git commit -m "feat: add PeerTube video-host recognition and resolution"
```

---

### Task 2: Wire PeerTube into the registry (classification + playback)

Append `PeerTubeVideoHost()` to `VideoHostRegistry`'s default hosts, which turns PeerTube posts into `.video` in the detector and makes them resolve-and-play at tap. Add a detector test proving classification.

**Files:**
- Modify: `SpudDataKit/Services/VideoHost/VideoHostRegistry.swift`
- Test: `SpudDataKitTests/PostContentDetectorTests.swift` (add one test)

**Interfaces:**
- Consumes (from Task 1): `PeerTubeVideoHost()`.
- Produces: `VideoHostRegistry()` now recognizes/resolves PeerTube; a PeerTube post URL classifies as `.video`.

- [ ] **Step 1: Write the failing test**

In `SpudDataKitTests/PostContentDetectorTests.swift`, add (near the other host tests, inside `struct PostContentDetectorTests`):

```swift
    @Test
    func peerTubeUrl_isDetectedAsVideo() {
        let url = "https://tube.example/videos/watch/0e3c8d2a-1234-4abc-9def-0123456789ab"
        let type = contentType(url: url)
        guard case let .video(video) = type else {
            Issue.record("PeerTube URL should be a video, got \(type)")
            return
        }
        #expect(video.videoUrl.absoluteString == url)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PostContentDetectorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: FAIL — `peerTubeUrl_isDetectedAsVideo` records "PeerTube URL should be a video, got externalLink" (the default registry doesn't include PeerTube yet).

- [ ] **Step 3: Wire the host into the registry**

In `SpudDataKit/Services/VideoHost/VideoHostRegistry.swift`, change:
```swift
    public init(hosts: [any VideoHost] = [StreamableVideoHost()]) {
        self.hosts = hosts
    }
```
to:
```swift
    public init(hosts: [any VideoHost] = [StreamableVideoHost(), PeerTubeVideoHost()]) {
        self.hosts = hosts
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PostContentDetectorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with N tests in 1 suites passed` (N = previous count + 1).

- [ ] **Step 5: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/VideoHostRegistry.swift SpudDataKitTests/PostContentDetectorTests.swift
git add SpudDataKit/Services/VideoHost/VideoHostRegistry.swift SpudDataKitTests/PostContentDetectorTests.swift
git commit -m "feat: recognize and play PeerTube video posts inline"
```

---

### Task 3: Documentation

Update the feature docs to include PeerTube. No `.swift` links; keep `Status:` accurate.

**Files (all Modify):**
- `docs/features/media-viewer.md`
- `docs/features/post-thumbnails.md`
- `docs/features/README.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: media-viewer.md**

Read `docs/features/media-viewer.md`. Make these edits (locate by the quoted anchors; if an anchor doesn't match, STOP and report NEEDS_CONTEXT):

1. In the "Recognized video hosts play inline" behavior bullet, the phrase naming the host — currently along the lines of "a recognized video-host page (currently streamable.com)" — update to name **both**: "a recognized video-host page (streamable.com, or a PeerTube instance)". Add a sentence: "PeerTube is recognized by URL shape (it is federated, with no host list), so a rare non-PeerTube link may be treated as a video and, on tap, fall back to the browser when the instance API does not confirm it."

2. In the "Not supported / out of scope" list, the bullet currently reading approximately "Video hosts other than streamable (e.g. YouTube) are not played inline; only streamable is resolved to a stream today." — change "other than streamable" to "other than streamable and PeerTube" and "only streamable is resolved" to "only streamable and PeerTube are resolved".

- [ ] **Step 2: post-thumbnails.md**

Read `docs/features/post-thumbnails.md`. In the "Content type drives the thumbnail" bullet, the phrase describing recognized-host video — currently along the lines of "or by being a recognized video host (currently streamable.com)" — update to "or by being a recognized video host (streamable.com or a PeerTube instance)". If the anchor doesn't match, STOP and report NEEDS_CONTEXT.

- [ ] **Step 3: README index**

Read `docs/features/README.md`. In the media-viewer/inline-video capability-table row and the matching "Feature coverage by area" entry, extend the existing wording to mention PeerTube alongside streamable (e.g. "streamable + PeerTube play inline"). Make the smallest edit; do NOT restructure the table or add new rows.

- [ ] **Step 4: Commit**

```sh
git add docs/features/media-viewer.md docs/features/post-thumbnails.md docs/features/README.md
git commit -m "docs: document inline PeerTube video playback"
```

---

## Final verification

- [ ] **Run the full SpudDataKit suite:**

```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with N tests ... passed`.

- [ ] **Build the app** to confirm it links (the registry change is consumed by the app):

```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: SUCCESS, 0 errors (pre-existing warnings only).

- [ ] **Manual on-device check** (not automatable here — idb tap is dead): open a PeerTube post, confirm the feed row shows the video treatment and tapping plays inline (mp4 or HLS); confirm a private/removed PeerTube link falls back to the browser.

## Notes for the reviewer

- The whole feature rides the existing seam: `PostContentType.Video`, `videoPlaybackAction`,
  `playVideo`, `VideoResolvingOverlay`, and the five tap sites are untouched — PeerTube reaches
  them because the detector and `playVideo` both build `VideoHostRegistry()`.
- Recognition deliberately reuses `VideoLinkParser` (single source of the PeerTube heuristic);
  false positives degrade to the browser via the existing fallback, matching how body-link
  preview cards already behave.
- No new snapshot test: a PeerTube video renders through the identical `.video` path already
  covered by existing `test_video` snapshots; classification is guarded by the detector test.
