# YouTube-via-Piped Video Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play YouTube videos inline via the user's Piped front-end — resolving to an HLS master playlist or a `proxyUrl`-rewritten progressive stream — while never handing AVPlayer a googlevideo URL (browser fallback otherwise).

**Architecture:** A third host in the video-host seam. `PipedVideoHost` recognizes `youtube.com`/`youtu.be`/`piped.video` (preference-free, so all YouTube posts classify as `.video`) and resolves preference-aware: `PipedInstanceResolver` picks the Piped apiHost from the user's front-end config, `resolve` fetches `/streams/<id>` and returns the HLS playlist or a `PipedProxy`-rewritten progressive stream, refusing (browser fallback) rather than emit a googlevideo URL. Wiring: the registry default gains the host; `playVideo` injects the live config snapshot; `AppService` exposes it.

**Tech Stack:** Swift 6 (complete strict concurrency), Foundation/URLSession, AVKit (HLS via `AVPlayer`), SpudUtilKit (`YouTubeReference`, `YouTubeFrontEndCatalog`, `URLSanitizerConfig`), Swift Testing, XcodeGen.

## Global Constraints

- **Privacy invariant:** never return a `googlevideo.com` URL from resolution. Only Piped-proxied streams (HLS master, or a `PipedProxy`-rewritten progressive). If neither is possible, throw `.noPlayableFile` → browser fallback.
- **Strict concurrency:** Swift 6 + complete. New value types `Sendable`; the injected `fetch` is `@Sendable`; the config is passed as a `Sendable` `URLSanitizerConfig` value snapshot (read on the main actor by the caller).
- **Name collision (must handle):** SpudUtilKit exports a public enum also named `VideoHost`. `PipedVideoHost.swift` imports SpudUtilKit, so qualify the conformance as `PipedVideoHost: SpudDataKit.VideoHost`. Enum cases like `.piped` / `.frontEnd(.piped)` resolve by context.
- **SpudDataKit may import SpudUtilKit** — the new files need `import SpudUtilKit`.
- **No emojis** anywhere. **Conventional commit** subjects.
- **New source files require `make project`** (from `Spud/`) before they compile.
- **`import Testing` does not re-export Foundation** — test files need `import Foundation`.
- **Confirm test success** by `✔ Test run with N tests in M suites passed`. Benign noise (keychain OSStatus, deliberate error logs) is not failure.
- **Run `mint run swiftformat <paths>` BEFORE committing**, never after.
- **iOS 18+ SDK** — `URL.host()` available.

Test command (single SpudDataKit suite):
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/<SuiteName> \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
App build: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud`
Sim contention ("Busy (Application failed preflight checks)") → target the booted sim by id.

---

### Task 1: `PipedProxy` — proxy a stream URL through the Piped instance

**Files:**
- Create: `SpudDataKit/Services/VideoHost/PipedProxy.swift`
- Test: `SpudDataKitTests/PipedVideoHostTests.swift` (create; this file also hosts later suites)

**Interfaces:**
- Produces (used by Task 3): `enum PipedProxy { static func rewrite(streamURL: String, proxyPrefix: String) -> URL? }`

- [ ] **Step 1: Write the failing tests**

Create `SpudDataKitTests/PipedVideoHostTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudDataKit

struct PipedProxyTests {
    @Test
    func rewritesToProxyHostAndAppendsOriginalHostParam() throws {
        let stream = "https://rr3---sn-abc.googlevideo.com/videoplayback?expire=123&id=xyz"
        let proxied = try #require(PipedProxy.rewrite(streamURL: stream, proxyPrefix: "https://pipedproxy.kavin.rocks"))
        // The connection host is the proxy — never googlevideo. This IS the privacy guarantee.
        #expect(proxied.host == "pipedproxy.kavin.rocks")
        let comps = try #require(URLComponents(url: proxied, resolvingAgainstBaseURL: false))
        #expect(comps.path == "/videoplayback")
        #expect(comps.queryItems?.contains(URLQueryItem(name: "expire", value: "123")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "id", value: "xyz")) == true)
        #expect(comps.queryItems?.contains(URLQueryItem(name: "host", value: "rr3---sn-abc.googlevideo.com")) == true)
    }

    @Test
    func returnsNilOnUnparseableInput() {
        #expect(PipedProxy.rewrite(streamURL: "", proxyPrefix: "https://p.host") == nil)
        #expect(PipedProxy.rewrite(streamURL: "https://x.googlevideo.com/v", proxyPrefix: "") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedProxyTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build FAILS — `cannot find 'PipedProxy' in scope`.

- [ ] **Step 3: Create `PipedProxy`**

Create `SpudDataKit/Services/VideoHost/PipedProxy.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Rewrites a Piped stream URL (a direct googlevideo `/videoplayback` URL) to go
/// through the Piped instance's own proxy, so Google is never contacted directly.
/// The result always points at the proxy host — never the original.
enum PipedProxy {
    /// - Parameters:
    ///   - streamURL: a direct stream URL from Piped's `/streams` response.
    ///   - proxyPrefix: the response's `proxyUrl` (e.g. `https://pipedproxy.host`).
    /// - Returns: the proxied URL, or nil if either URL cannot be parsed.
    static func rewrite(streamURL: String, proxyPrefix: String) -> URL? {
        guard var comps = URLComponents(string: streamURL), let originalHost = comps.host,
              let proxy = URLComponents(string: proxyPrefix), let proxyHost = proxy.host
        else {
            return nil
        }
        comps.scheme = proxy.scheme ?? "https"
        comps.host = proxyHost
        comps.port = proxy.port
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "host", value: originalHost))
        comps.queryItems = items
        return comps.url
    }
}
```

- [ ] **Step 4: Regenerate the project**

Run: `make project`
Expected: `Created project at .../Spud.xcodeproj`.

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedProxyTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 2 tests in 1 suites passed`.

- [ ] **Step 6: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/PipedProxy.swift SpudDataKitTests/PipedVideoHostTests.swift
git add SpudDataKit/Services/VideoHost/PipedProxy.swift SpudDataKitTests/PipedVideoHostTests.swift
git commit -m "feat: add Piped stream-URL proxy rewriter"
```

---

### Task 2: `PipedInstanceResolver` — pick the Piped apiHost from the user's front-end config

**Files:**
- Create: `SpudDataKit/Services/VideoHost/PipedInstanceResolver.swift`
- Test: `SpudDataKitTests/PipedVideoHostTests.swift` (add a suite)

**Interfaces:**
- Consumes (existing SpudUtilKit): `YouTubeReference.extract(from:) -> YouTubeReference?` (with `.videoId`, `.sourceHost`, `.sourceKind` of `.youtube` / `.frontEnd(.piped)` / `.frontEnd(.invidious)` / `.frontEndShape`); `YouTubeFrontEndCatalog.instance(forHost:) -> YouTubeFrontEndInstance?` (with `.kind: YouTubeFrontEndKind`, `.apiHost: String?`); `URLSanitizerConfig` (`.redirectToFrontEnds`, `.setting(for: .youtube) -> FrontEndConfig` with `.isEnabled`, `.host`).
- Produces (used by Task 3): `enum PipedInstanceResolver { static func apiHost(forYouTubePageURL: URL, config: URLSanitizerConfig) -> String? }`

- [ ] **Step 1: Write the failing tests**

In `SpudDataKitTests/PipedVideoHostTests.swift`, add:

```swift
struct PipedInstanceResolverTests {
    /// A config whose YouTube front-end is the cataloged Piped instance, enabled.
    private var pipedFrontEnd: URLSanitizerConfig {
        var c = URLSanitizerConfig.default
        c.redirectToFrontEnds = true
        c.frontEnds = c.frontEnds.map {
            $0.service == .youtube ? FrontEndConfig(service: .youtube, isEnabled: true, host: "piped.video") : $0
        }
        return c
    }

    private func apiHost(_ urlString: String, _ config: URLSanitizerConfig) -> String? {
        PipedInstanceResolver.apiHost(forYouTubePageURL: URL(string: urlString)!, config: config)
    }

    @Test
    func pipedVideoUrlUsesCatalogApiHost() {
        #expect(apiHost("https://piped.video/watch?v=dQw4w9WgXcQ", .default) == "pipedapi.kavin.rocks")
    }

    @Test
    func youtubeUrlUsesUsersPipedFrontEnd() {
        #expect(apiHost("https://www.youtube.com/watch?v=dQw4w9WgXcQ", pipedFrontEnd) == "pipedapi.kavin.rocks")
    }

    @Test
    func youtubeUrlIsNilWhenFrontEndNotPiped() {
        // Default: redirectToFrontEnds off → no Piped instance for a raw youtube link.
        #expect(apiHost("https://www.youtube.com/watch?v=dQw4w9WgXcQ", .default) == nil)
    }

    @Test
    func nonYoutubeUrlIsNil() {
        #expect(apiHost("https://example.com/article", .default) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedInstanceResolverTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build FAILS — `cannot find 'PipedInstanceResolver' in scope`.

- [ ] **Step 3: Create `PipedInstanceResolver`**

Create `SpudDataKit/Services/VideoHost/PipedInstanceResolver.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Decides which Piped instance (apiHost) should resolve a YouTube-family page URL
/// for inline playback, honoring the user's front-end preference.
enum PipedInstanceResolver {
    /// - Returns: the Piped apiHost to resolve `url` through, or nil if it should
    ///   not be inline-resolved via Piped (→ browser fallback).
    static func apiHost(forYouTubePageURL url: URL, config: URLSanitizerConfig) -> String? {
        guard let ref = YouTubeReference.extract(from: url) else { return nil }
        switch ref.sourceKind {
        case .frontEnd(.piped):
            // Already on a cataloged Piped instance.
            return YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost
        case .youtube:
            // Canonical youtube.com/youtu.be: use the user's YouTube front-end iff it is Piped.
            guard config.redirectToFrontEnds else { return nil }
            let setting = config.setting(for: .youtube)
            guard setting.isEnabled,
                  let instance = YouTubeFrontEndCatalog.instance(forHost: setting.host),
                  instance.kind == .piped
            else {
                return nil
            }
            return instance.apiHost
        case .frontEnd(.invidious), .frontEndShape:
            return nil
        }
    }
}
```

- [ ] **Step 4: Regenerate the project**

Run: `make project`

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedInstanceResolverTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 4 tests in 1 suites passed`.

- [ ] **Step 6: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/PipedInstanceResolver.swift SpudDataKitTests/PipedVideoHostTests.swift
git add SpudDataKit/Services/VideoHost/PipedInstanceResolver.swift SpudDataKitTests/PipedVideoHostTests.swift
git commit -m "feat: resolve the Piped apiHost from the user's front-end config"
```

---

### Task 3: `VideoHostKind.piped` + `PipedVideoHost` (recognize + resolve)

**Files:**
- Modify: `SpudDataKit/Services/VideoHost/VideoHostTypes.swift` (add enum case)
- Create: `SpudDataKit/Services/VideoHost/PipedVideoHost.swift`
- Test: `SpudDataKitTests/PipedVideoHostTests.swift` (add two suites)

**Interfaces:**
- Consumes: `PipedProxy.rewrite` (Task 1); `PipedInstanceResolver.apiHost` (Task 2); `YouTubeReference` (SpudUtilKit); the seam types.
- Produces (used by Task 4): `public struct PipedVideoHost` with `init(fetch:config:)` and `kind == .piped`; `VideoHostKind.piped`.

- [ ] **Step 1: Write the failing tests**

In `SpudDataKitTests/PipedVideoHostTests.swift`, add:

```swift
struct PipedVideoHostRecognitionTests {
    private let host = PipedVideoHost()

    private func match(_ s: String) -> VideoHostMatch? {
        host.recognize(URL(string: s)!)
    }

    @Test
    func recognizesCanonicalYouTube() {
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
        #expect(match("https://youtu.be/dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
        #expect(match("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.kind == .piped)
    }

    @Test
    func recognizesPipedVideo() {
        #expect(match("https://piped.video/watch?v=dQw4w9WgXcQ")?.identifier == "dQw4w9WgXcQ")
    }

    @Test
    func doesNotClaimInvidiousOrNonVideo() {
        #expect(match("https://yewtu.be/watch?v=dQw4w9WgXcQ") == nil)
        #expect(match("https://example.com/article") == nil)
    }
}

struct PipedVideoHostResolutionTests {
    private func host(returning json: String?, config: URLSanitizerConfig) -> PipedVideoHost {
        PipedVideoHost(fetch: { _ in json.map { Data($0.utf8) } }, config: config)
    }

    private var pipedConfig: URLSanitizerConfig {
        var c = URLSanitizerConfig.default
        c.redirectToFrontEnds = true
        c.frontEnds = c.frontEnds.map {
            $0.service == .youtube ? FrontEndConfig(service: .youtube, isEnabled: true, host: "piped.video") : $0
        }
        return c
    }

    private let ytMatch = VideoHostMatch(
        kind: .piped,
        identifier: "dQw4w9WgXcQ",
        pageUrl: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
    )

    @Test
    func prefersHlsMasterPlaylist() async throws {
        let json = """
        {"title":"Song","thumbnailUrl":"https://pipedproxy.kavin.rocks/thumb.jpg",\
        "hls":"https://pipedproxy.kavin.rocks/hls/master.m3u8","proxyUrl":"https://pipedproxy.kavin.rocks",\
        "videoStreams":[{"url":"https://x.googlevideo.com/v?id=1","videoOnly":false,"bitrate":500}]}
        """
        let resolved = try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        #expect(resolved.streamUrl.absoluteString == "https://pipedproxy.kavin.rocks/hls/master.m3u8")
        #expect(resolved.title == "Song")
    }

    @Test
    func proxiesHighestBitrateProgressiveWhenNoHls() async throws {
        let json = """
        {"proxyUrl":"https://pipedproxy.kavin.rocks",\
        "videoStreams":[{"url":"https://rr1.googlevideo.com/videoplayback?id=lo","videoOnly":false,"bitrate":300},\
        {"url":"https://rr2.googlevideo.com/videoplayback?id=hi","videoOnly":false,"bitrate":800}]}
        """
        let resolved = try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        // Highest bitrate, proxied — the connection host must be the proxy, never googlevideo.
        #expect(resolved.streamUrl.host == "pipedproxy.kavin.rocks")
        #expect(resolved.streamUrl.absoluteString.contains("id=hi"))
    }

    @Test
    func refusesWhenOnlyAdaptiveStreams() async {
        let json = #"{"proxyUrl":"https://pipedproxy.kavin.rocks","videoStreams":[{"url":"https://x.googlevideo.com/v","videoOnly":true,"bitrate":900}]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        }
    }

    @Test
    func refusesWhenNoProxyUrl() async {
        let json = #"{"videoStreams":[{"url":"https://x.googlevideo.com/v","videoOnly":false,"bitrate":500}]}"#
        await #expect(throws: VideoHostResolutionError.noPlayableFile) {
            try await host(returning: json, config: pipedConfig).resolve(ytMatch)
        }
    }

    @Test
    func unresolvableWhenFrontEndNotPiped() async {
        await #expect(throws: VideoHostResolutionError.unresolvable) {
            try await host(returning: #"{"hls":"https://p/hls.m3u8"}"#, config: .default).resolve(ytMatch)
        }
    }

    @Test
    func networkErrorWhenFetchNil() async {
        await #expect(throws: VideoHostResolutionError.network) {
            try await host(returning: nil, config: pipedConfig).resolve(ytMatch)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedVideoHostRecognitionTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: build FAILS — `cannot find 'PipedVideoHost' in scope` / `.piped` not a `VideoHostKind` member.

- [ ] **Step 3: Add the `.piped` kind**

In `SpudDataKit/Services/VideoHost/VideoHostTypes.swift`, change:
```swift
public enum VideoHostKind: Equatable, Sendable {
    case streamable
    case peertube
}
```
to:
```swift
public enum VideoHostKind: Equatable, Sendable {
    case streamable
    case peertube
    case piped
}
```

- [ ] **Step 4: Create `PipedVideoHost`**

Create `SpudDataKit/Services/VideoHost/PipedVideoHost.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

/// Recognizes YouTube / Piped video URLs and resolves them to a Piped-PROXIED
/// stream (never a direct googlevideo URL), honoring the user's front-end choice.
///
/// Recognition is preference-free (so every YouTube post classifies as video); the
/// preference gates resolution — a raw youtube.com link resolves only when the
/// user's YouTube front-end is a Piped instance (see ``PipedInstanceResolver``),
/// otherwise resolution throws and playback falls back to the browser.
///
/// `VideoHost` is qualified as `SpudDataKit.VideoHost` because `import SpudUtilKit`
/// also brings a same-named enum into scope.
public struct PipedVideoHost: SpudDataKit.VideoHost {
    public let kind: VideoHostKind = .piped

    private let fetch: @Sendable (URL) async -> Data?
    private let config: URLSanitizerConfig

    /// - Parameters:
    ///   - fetch: injected so tests can stub the API response.
    ///   - config: a Sendable snapshot of the user's URL-sanitizer config, read on
    ///     the main actor by the caller (used only in `resolve`).
    public init(
        fetch: @escaping @Sendable (URL) async -> Data? = { url in
            try? await URLSession.shared.data(from: url).0
        },
        config: URLSanitizerConfig = .default
    ) {
        self.fetch = fetch
        self.config = config
    }

    public func recognize(_ url: URL) -> VideoHostMatch? {
        guard let ref = YouTubeReference.extract(from: url) else { return nil }
        switch ref.sourceKind {
        case .youtube, .frontEnd(.piped):
            return VideoHostMatch(kind: .piped, identifier: ref.videoId, pageUrl: url)
        case .frontEnd(.invidious), .frontEndShape:
            return nil
        }
    }

    public func resolve(_ match: VideoHostMatch) async throws -> ResolvedVideo {
        guard match.kind == .piped,
              let apiHost = PipedInstanceResolver.apiHost(forYouTubePageURL: match.pageUrl, config: config),
              let apiUrl = URL(string: "https://\(apiHost)/streams/\(match.identifier)")
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
        return ResolvedVideo(
            streamUrl: streamUrl,
            posterUrl: response.thumbnailUrl.flatMap { URL(string: $0) },
            title: response.title
        )
    }

    /// Privacy invariant: return only a Piped-proxied stream, never a direct
    /// googlevideo URL. Prefer the HLS master (Piped already proxies it, and it is
    /// adaptive); otherwise proxy the best progressive muxed stream through
    /// `proxyUrl`; refuse if neither is possible.
    private static func playableStreamUrl(from response: Response) throws -> URL {
        if let hls = response.hls, let url = URL(string: hls) {
            return url
        }
        guard let proxyPrefix = response.proxyUrl, !proxyPrefix.isEmpty else {
            throw VideoHostResolutionError.noPlayableFile
        }
        let bestMuxed = (response.videoStreams ?? [])
            .filter { $0.videoOnly == false }
            .compactMap { stream -> (url: String, bitrate: Int)? in
                guard let url = stream.url else { return nil }
                return (url, stream.bitrate ?? 0)
            }
            .max { $0.bitrate < $1.bitrate }
        if let bestMuxed, let proxied = PipedProxy.rewrite(streamURL: bestMuxed.url, proxyPrefix: proxyPrefix) {
            return proxied
        }
        throw VideoHostResolutionError.noPlayableFile
    }

    private struct Response: Decodable {
        struct VideoStream: Decodable {
            let url: String?
            let videoOnly: Bool?
            let bitrate: Int?
        }

        let title: String?
        let thumbnailUrl: String?
        let hls: String?
        let proxyUrl: String?
        let videoStreams: [VideoStream]?
    }
}
```

- [ ] **Step 5: Regenerate the project**

Run: `make project`

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PipedVideoHostRecognitionTests \
  -only-testing:SpudDataKitTests/PipedVideoHostResolutionTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 9 tests in 2 suites passed` (3 recognition + 6 resolution).

- [ ] **Step 7: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/PipedVideoHost.swift SpudDataKit/Services/VideoHost/VideoHostTypes.swift SpudDataKitTests/PipedVideoHostTests.swift
git add SpudDataKit/Services/VideoHost/PipedVideoHost.swift SpudDataKit/Services/VideoHost/VideoHostTypes.swift SpudDataKitTests/PipedVideoHostTests.swift
git commit -m "feat: add PipedVideoHost recognition and privacy-safe resolution"
```

---

### Task 4: Wire the Piped host into the registry + inject the live config

**Files:**
- Modify: `SpudDataKit/Services/VideoHost/VideoHostRegistry.swift`
- Modify: `Spud/Services/App/AppService.swift` (protocol + class)
- Modify: `Spud/Utils/UIViewController+VideoPlayer.swift` (`playVideo`)
- Test: `SpudDataKitTests/PostContentDetectorTests.swift` (add one test)

**Interfaces:**
- Consumes (from Task 3): `PipedVideoHost(config:)`.
- Produces: `VideoHostRegistry(pipedConfig:)`; `AppServiceType.urlSanitizerConfig`; a `youtube.com` post classifies as `.video`.

- [ ] **Step 1: Write the failing detector test**

In `SpudDataKitTests/PostContentDetectorTests.swift`, add (inside `struct PostContentDetectorTests`):

```swift
    @Test
    func youTubeUrl_isDetectedAsVideo() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let type = contentType(url: url)
        guard case let .video(video) = type else {
            Issue.record("YouTube URL should be a video, got \(type)")
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
Expected: FAIL — records "YouTube URL should be a video, got externalLink" (the default registry doesn't include the Piped host yet).

- [ ] **Step 3: Restructure the registry inits to include the Piped host**

In `SpudDataKit/Services/VideoHost/VideoHostRegistry.swift`, add `import SpudUtilKit` under `import Foundation`, then replace:
```swift
    public init(hosts: [any VideoHost] = [StreamableVideoHost(), PeerTubeVideoHost()]) {
        self.hosts = hosts
    }
```
with:
```swift
    public init(hosts: [any VideoHost]) {
        self.hosts = hosts
    }

    /// Production default. `pipedConfig` is the caller's snapshot of the user's
    /// URL-sanitizer config; it gates PeerTube-style YouTube resolution (recognition
    /// is preference-free). The detector uses `.default` (it never resolves).
    public init(pipedConfig: URLSanitizerConfig = .default) {
        self.init(hosts: [StreamableVideoHost(), PeerTubeVideoHost(), PipedVideoHost(config: pipedConfig)])
    }
```
(`VideoHostRegistry()` now resolves to `init(pipedConfig:)`; existing `VideoHostRegistry(hosts:)` callers are unchanged.)

- [ ] **Step 4: Expose the config on `AppService`**

In `Spud/Services/App/AppService.swift`, in the `AppServiceType` protocol add (next to the other `var`/`func` requirements):
```swift
    /// The user's current URL-sanitizer config (front-end preferences). Read on the
    /// main actor to build a preference-aware video-host registry for playback.
    var urlSanitizerConfig: URLSanitizerConfig { get }
```
and in `class AppService`, add:
```swift
    var urlSanitizerConfig: URLSanitizerConfig {
        preferencesService.urlSanitizerConfig
    }
```

- [ ] **Step 5: Inject the live config in `playVideo`**

In `Spud/Utils/UIViewController+VideoPlayer.swift`, ensure `import SpudUtilKit` is present (add it under the existing imports if not), then change:
```swift
        let registry = VideoHostRegistry()
```
to:
```swift
        let registry = VideoHostRegistry(pipedConfig: appService.urlSanitizerConfig)
```

- [ ] **Step 6: Run the detector test + build the app**

Run:
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests/PostContentDetectorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with N tests in 1 suites passed` (N = previous + 1).

Then:
```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: SUCCESS, 0 errors (pre-existing warnings only).

- [ ] **Step 7: Format and commit**

```sh
mint run swiftformat SpudDataKit/Services/VideoHost/VideoHostRegistry.swift Spud/Services/App/AppService.swift Spud/Utils/UIViewController+VideoPlayer.swift SpudDataKitTests/PostContentDetectorTests.swift
git add SpudDataKit/Services/VideoHost/VideoHostRegistry.swift Spud/Services/App/AppService.swift Spud/Utils/UIViewController+VideoPlayer.swift SpudDataKitTests/PostContentDetectorTests.swift
git commit -m "feat: play YouTube posts inline via Piped, front-end-gated"
```

---

### Task 5: Documentation

**Files (all Modify):**
- `docs/features/media-viewer.md`
- `docs/features/post-thumbnails.md`
- `docs/features/external-link-handling.md`
- `docs/features/README.md`

**Interfaces:** none.

Read each file and make these edits (locate by the quoted anchors; if an anchor doesn't match, STOP and report NEEDS_CONTEXT).

- [ ] **Step 1: media-viewer.md**

In the "Recognized video hosts play inline" bullet, extend the host list to include YouTube-via-Piped and add a note. After the existing PeerTube sentence, add:
```markdown
  YouTube links (`youtube.com`/`youtu.be`/`piped.video`) play inline **through the user's
  Piped front-end** — the stream is fetched from the Piped instance and served via its proxy,
  so Google's servers are never contacted. This works only when the user's YouTube front-end
  (Privacy settings) is a Piped instance; otherwise the post opens in the browser. Livestreams
  are supported (HLS).
```

In the "Not supported / out of scope" list, update the "Video hosts other than streamable and PeerTube (e.g. YouTube)…" bullet: YouTube is now partially supported (Piped, front-end-gated), so change it to name **Invidious and other non-Piped front-ends** as the not-inline case, e.g.:
```markdown
- Inline video-host playback covers streamable, PeerTube, and YouTube-via-Piped. YouTube plays
  inline only when the user's front-end is a Piped instance; Invidious and other front-ends open
  in the browser. Spud never contacts Google directly — if a proxied stream can't be produced,
  the video opens in the browser instead.
```

- [ ] **Step 2: post-thumbnails.md**

In the "Content type drives the thumbnail" bullet, extend the recognized-host list: after "streamable.com or a PeerTube instance", add ", or a YouTube/Piped link". Add a sentence: "YouTube posts always show the video badge, but inline playback happens only when the user's front-end is a Piped instance (otherwise tapping opens the browser)."

- [ ] **Step 3: external-link-handling.md**

Add a bullet under "Behavior and rules":
```markdown
- **YouTube plays inline via Piped when configured.** A YouTube link is classified as a video;
  tapping resolves it through the user's Piped front-end (never Google) and plays inline, or —
  when the front-end isn't Piped or resolution fails — opens in the browser (rewritten to the
  chosen front-end). See [Media viewer and inline video](media-viewer.md).
```

- [ ] **Step 4: README index**

In `docs/features/README.md`, extend the media-viewer capability-table row and the "Feature coverage by area" entry to mention YouTube-via-Piped alongside streamable + PeerTube. Smallest edit; no table restructuring.

- [ ] **Step 5: Commit**

```sh
git add docs/features/media-viewer.md docs/features/post-thumbnails.md docs/features/external-link-handling.md docs/features/README.md
git commit -m "docs: document inline YouTube-via-Piped playback"
```

---

## Final verification

- [ ] **Full SpudDataKit suite:**
```sh
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudDataKitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with N tests ... passed`.

- [ ] **App build:**
```sh
python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud
```
Expected: SUCCESS, 0 errors.

- [ ] **Manual on-device check** (not automatable — idb tap is dead): with the YouTube front-end set to `piped.video`, open a youtube.com post → confirm the video badge, tap → inline playback (verify via Charles/console that only the Piped proxy host is contacted, never `googlevideo.com`); with the front-end unset/Invidious, confirm the badge shows but tapping opens the browser.

## Notes for the reviewer

- **Privacy invariant** is the crux: `playableStreamUrl` returns the HLS master (Piped-proxied) or a `PipedProxy`-rewritten progressive stream, and throws `.noPlayableFile` rather than emit a googlevideo URL. The resolution tests assert `streamUrl.host == "pipedproxy.kavin.rocks"` for the progressive path.
- **Recognition is preference-free by necessity** — the detector (SpudDataKit) can't read the `@MainActor` app-level `PreferencesService`, so all YouTube posts classify `.video`; the preference gates resolution in `playVideo` (which reads the config on the main actor and injects a Sendable snapshot). This is the accepted feed change.
- The registry `init` restructuring keeps `init(hosts:)` for tests; `VideoHostRegistry()` now includes the Piped host (with `.default` config, never resolved by the detector).
- No new snapshot test (identical `.video` render path); classification guarded by the detector test.
