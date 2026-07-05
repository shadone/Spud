# Alternative YouTube Link Wrappers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize alternative YouTube front-end links (Invidious, Piped, plus `/shorts`, `/live`) as first-class YouTube videos — enriching their preview cards privacy-first and, opt-in, normalizing them to the user's chosen front-end.

**Architecture:** A single pure extractor, `YouTubeReference`, backed by a curated `YouTubeFrontEndCatalog`, becomes the shared source of truth for YouTube-video recognition. The preview path (`VideoLinkParser` → `LinkEmbedService`) uses it to classify Invidious vs Piped and resolve titles/thumbnails from the front-end itself (never Google) — Piped via its `/streams` API. The rewrite path (`FrontEndRewriteStep`) uses it to rebuild any wrapper as grammar-correct `/watch?v=<id>` on the user's chosen host, gated by a new `rewriteThirdPartyFrontEnds` preference.

**Tech Stack:** Swift 6 / strict concurrency, Swift Testing (`import Testing`, `#expect`/`#require`), XcodeGen, GRDB-adjacent but no DB changes. Frameworks: SpudUtilKit (pure logic), SpudDataKit (LinkEmbedService), Spud (Preferences UI).

## Global Constraints

- Swift 6.0 language mode + complete strict concurrency on all touched targets; new types must be `Sendable`.
- Swift Testing only (no XCTest); suites are `struct`; tests are `@Test func` (no `test` prefix); use `#expect`/`#require`. `import Testing` does NOT re-export Foundation — add `import Foundation` where `URL`/`Data` are used.
- No emojis in code, comments, docs, or commit messages. Conventional commit subjects (`feat:`/`fix:`/`refactor:`/`test:`/`docs:`).
- Copyright header on every new Swift file (match sibling files): `//\n// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>\n//\n// SPDX-License-Identifier: BSD-2-Clause\n//`.
- New source/test files require `make project` (XcodeGen) before they compile; sources are folder-globbed so no `project.yml` edit is needed.
- Run `mint run swiftformat <changed paths>` BEFORE the final test verify, never after a green verify.
- Privacy invariant: a front-end link (Invidious/Piped/uncataloged shape) must never trigger a request to Google (`i.ytimg.com`, `youtube.com`). Canonical `youtube.com`/`youtu.be` previews keep contacting Google as today.
- Layer direction: new pure logic lives in SpudUtilKit; frameworks never import the app target.
- Verify commands run on `platform=iOS Simulator,name=iPhone 17 Pro` (or a booted sim by id) with `-skipPackagePluginValidation -skipMacroValidation`.
- Work on a branch/worktree off local `main` (this is a shared checkout; verify `git branch --show-current` before committing; stage explicit paths, never `git add -A`; never commit `.remember/remember.md`).

---

### Task 1: `YouTubeReference` extractor + `YouTubeFrontEndCatalog`

**Files:**
- Create: `SpudUtilKit/URLSanitizer/YouTubeFrontEndCatalog.swift`
- Create: `SpudUtilKit/Markdown/YouTubeReference.swift`
- Test: `SpudUtilKitTests/YouTubeReferenceTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces:
  - `enum YouTubeFrontEndKind: Equatable, Sendable { case invidious, piped }`
  - `struct YouTubeFrontEndInstance: Equatable, Sendable { let host: String; let kind: YouTubeFrontEndKind; let apiHost: String? }`
  - `enum YouTubeFrontEndCatalog { static let instances: [YouTubeFrontEndInstance]; static func instance(forHost: String) -> YouTubeFrontEndInstance? }`
  - `struct YouTubeReference: Equatable, Sendable { let videoId: String; let sourceHost: String; let sourceKind: SourceKind; let timestampSeconds: Int?; static func extract(from url: URL) -> YouTubeReference? }` with `enum YouTubeReference.SourceKind: Equatable, Sendable { case youtube; case frontEnd(YouTubeFrontEndKind); case frontEndShape }`

- [ ] **Step 1: Write the failing test**

Create `SpudUtilKitTests/YouTubeReferenceTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing
@testable import SpudUtilKit

struct YouTubeReferenceTests {
    private func ref(_ s: String) -> YouTubeReference? {
        YouTubeReference.extract(from: URL(string: s)!)
    }

    @Test
    func youtubeWatchEmbedShortsLiveV() throws {
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.sourceKind == .youtube)
        #expect(ref("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/embed/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/shorts/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/live/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://www.youtube.com/v/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
        #expect(ref("https://youtu.be/dQw4w9WgXcQ")?.sourceKind == .youtube)
    }

    @Test
    func redirectInvidiousIsYoutube() {
        #expect(ref("https://redirect.invidious.io/watch?v=dQw4w9WgXcQ")?.sourceKind == .youtube)
        #expect(ref("https://redirect.invidious.io/embed/dQw4w9WgXcQ")?.videoId == "dQw4w9WgXcQ")
    }

    @Test
    func catalogFrontEnds() throws {
        let inv = try #require(ref("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        #expect(inv.sourceKind == .frontEnd(.invidious))
        #expect(inv.sourceHost == "yewtu.be")
        let piped = try #require(ref("https://piped.video/watch?v=dQw4w9WgXcQ"))
        #expect(piped.sourceKind == .frontEnd(.piped))
        #expect(piped.videoId == "dQw4w9WgXcQ")
    }

    @Test
    func unknownHostFallsBackToShape() {
        #expect(ref("https://some.random.host/watch?v=dQw4w9WgXcQ")?.sourceKind == .frontEndShape)
    }

    @Test
    func timestampParsedFromQueryAndFragment() {
        #expect(ref("https://youtu.be/dQw4w9WgXcQ?t=90")?.timestampSeconds == 90)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&start=42")?.timestampSeconds == 42)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=7")?.timestampSeconds == 7)
        #expect(ref("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s")?.timestampSeconds == nil) // richer forms omitted in v1
        #expect(ref("https://youtu.be/dQw4w9WgXcQ")?.timestampSeconds == nil)
    }

    @Test
    func negatives() {
        #expect(ref("https://example.com/article") == nil)
        #expect(ref("https://www.youtube.com/watch?v=short") == nil) // id must be 11 chars
        #expect(ref("https://youtu.be/dQw4w9WgXcQ/extra") == nil)   // id must be sole segment
        #expect(ref("https://www.youtube.com/results?search_query=cats") == nil) // non-video path
        #expect(ref("ftp://youtu.be/dQw4w9WgXcQ") == nil)           // non-http scheme
    }

    @Test
    func catalogLookupStripsWwwAndM() {
        #expect(YouTubeFrontEndCatalog.instance(forHost: "yewtu.be")?.kind == .invidious)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "piped.video")?.kind == .piped)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "piped.video")?.apiHost != nil)
        #expect(YouTubeFrontEndCatalog.instance(forHost: "unknown.example") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/YouTubeReferenceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: BUILD FAILS — `Cannot find 'YouTubeReference' in scope` (types not yet created; the new test file also isn't in the project until `make project`).

- [ ] **Step 3: Create the catalog**

Create `SpudUtilKit/URLSanitizer/YouTubeFrontEndCatalog.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Which kind of YouTube privacy front-end a host is. Determines how a preview
/// resolves its title/thumbnail: Invidious serves oEmbed + `/vi` thumbnails from
/// its own host; Piped exposes a separate `/streams` API.
public enum YouTubeFrontEndKind: Equatable, Sendable {
    case invidious
    case piped
}

/// A known YouTube privacy front-end instance.
public struct YouTubeFrontEndInstance: Equatable, Sendable {
    public let host: String
    public let kind: YouTubeFrontEndKind
    /// Piped's API host (`kind == .piped` only); nil for Invidious. NOT derivable
    /// from `host` — each Piped instance publishes its own API domain. A wrong
    /// value degrades the preview gracefully (no title/thumbnail) and never
    /// contacts Google.
    public let apiHost: String?

    public init(host: String, kind: YouTubeFrontEndKind, apiHost: String?) {
        self.host = host
        self.kind = kind
        self.apiHost = apiHost
    }
}

/// Built-in registry of known YouTube front-end instances. Like
/// ``FrontEndCatalog``'s default hosts, this list rots over time and is
/// maintained in code; hosts not listed here fall back to ``VideoLinkParser``'s
/// `/watch?v=` shape heuristic (best-effort Invidious).
public enum YouTubeFrontEndCatalog {
    public static let instances: [YouTubeFrontEndInstance] = [
        YouTubeFrontEndInstance(host: "yewtu.be", kind: .invidious, apiHost: nil),
        YouTubeFrontEndInstance(host: "inv.nadeko.net", kind: .invidious, apiHost: nil),
        YouTubeFrontEndInstance(host: "yt.artemislena.eu", kind: .invidious, apiHost: nil),
        // apiHost verified against the live instance in Task 6; graceful-degrades if wrong.
        YouTubeFrontEndInstance(host: "piped.video", kind: .piped, apiHost: "api.piped.video"),
    ]

    /// The catalog entry for `host` (`www.`/`m.` stripped, lowercased), or nil.
    public static func instance(forHost host: String) -> YouTubeFrontEndInstance? {
        let base = baseHost(host.lowercased())
        return instances.first { $0.host == base }
    }

    private static func baseHost(_ host: String) -> String {
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }
}
```

- [ ] **Step 4: Create the extractor**

Create `SpudUtilKit/Markdown/YouTubeReference.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// A recognized reference to a YouTube video, possibly reached through a wrapper
/// or privacy front-end. The single source of truth for YouTube-video
/// recognition, shared by ``VideoLinkParser`` (previews) and
/// ``FrontEndRewriteStep`` (link rewriting). Pure and side-effect free.
public struct YouTubeReference: Equatable, Sendable {
    /// Where the reference was found.
    public enum SourceKind: Equatable, Sendable {
        /// A canonical YouTube host (`youtube.com` family, `youtu.be`) or the
        /// `redirect.invidious.io` privacy redirect (which points at real YouTube).
        case youtube
        /// A host present in ``YouTubeFrontEndCatalog``.
        case frontEnd(YouTubeFrontEndKind)
        /// An unknown host matched only by the `/watch?v=<id>` shape (best-effort
        /// Invidious, matching the legacy heuristic).
        case frontEndShape
    }

    /// Canonical 11-char YouTube video id.
    public let videoId: String
    /// Lowercased host the reference was found on.
    public let sourceHost: String
    public let sourceKind: SourceKind
    /// Start offset in whole seconds parsed from `t`/`start`/`#t=` (plain integer
    /// forms only), else nil.
    public let timestampSeconds: Int?

    private static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
    ]

    /// Classifies `url` as a YouTube video reference, or nil.
    public static func extract(from url: URL) -> YouTubeReference? {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let timestamp = timestampSeconds(url)

        // Canonical YouTube family, by host.
        if youTubeHosts.contains(host) {
            guard let id = youTubePathId(segments: segments, url: url) else { return nil }
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // youtu.be short link: id is the sole path segment.
        if host == "youtu.be", segments.count == 1, isYouTubeId(segments[0]) {
            return YouTubeReference(videoId: segments[0], sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // redirect.invidious.io: privacy redirect to real YouTube.
        if host == "redirect.invidious.io" {
            guard let id = frontEndPathId(segments: segments, url: url) else { return nil }
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .youtube, timestampSeconds: timestamp)
        }
        // Cataloged front-end: /watch?v=<id> or /embed/<id>.
        if let entry = YouTubeFrontEndCatalog.instance(forHost: host),
           let id = frontEndPathId(segments: segments, url: url) {
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .frontEnd(entry.kind), timestampSeconds: timestamp)
        }
        // Unknown host, /watch?v=<id> shape (best-effort Invidious).
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return YouTubeReference(videoId: id, sourceHost: host, sourceKind: .frontEndShape, timestampSeconds: timestamp)
        }
        return nil
    }

    /// YouTube video id from `/watch?v=`, `/embed/<id>`, `/shorts/<id>`,
    /// `/live/<id>`, `/v/<id>`.
    private static func youTubePathId(segments: [String], url: URL) -> String? {
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) { return id }
        if segments.count == 2, ["embed", "shorts", "live", "v"].contains(segments[0]), isYouTubeId(segments[1]) {
            return segments[1]
        }
        return nil
    }

    /// YouTube video id from a front-end `/watch?v=` or `/embed/<id>` link.
    private static func frontEndPathId(segments: [String], url: URL) -> String? {
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) { return id }
        if segments.count == 2, segments[0] == "embed", isYouTubeId(segments[1]) { return segments[1] }
        return nil
    }

    private static func timestampSeconds(_ url: URL) -> Int? {
        for name in ["t", "start"] {
            if let raw = queryValue(name, url), let seconds = Int(raw) { return seconds }
        }
        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
           fragment.hasPrefix("t="), let seconds = Int(fragment.dropFirst(2)) {
            return seconds
        }
        return nil
    }

    private static func queryValue(_ name: String, _ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// YouTube ids are exactly 11 chars of `[A-Za-z0-9_-]`.
    private static func isYouTubeId(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0 == "_" || $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
```

- [ ] **Step 5: Regenerate the project (new files)**

Run:
```bash
make project
```
Expected: `xcodegen generate` succeeds; the two new sources and the new test file are now in the project.

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/YouTubeReferenceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: `✔ Test run with 7 tests ... passed` (look for the Swift Testing `✔` lines, not XCTest's "Executed 0 tests").

- [ ] **Step 7: Commit**

```bash
git add SpudUtilKit/URLSanitizer/YouTubeFrontEndCatalog.swift \
        SpudUtilKit/Markdown/YouTubeReference.swift \
        SpudUtilKitTests/YouTubeReferenceTests.swift
git commit -m "feat: add YouTubeReference extractor + YouTubeFrontEndCatalog"
```

---

### Task 2: Piped-aware previews (`VideoLink.MetadataSource`, `VideoLinkParser`, `LinkEmbedService`)

**Files:**
- Modify: `SpudUtilKit/Markdown/VideoLinkParser.swift` (add `.piped`, replace `oEmbedURL` with `metadataSource`, route through `YouTubeReference`)
- Modify: `SpudUtilKitTests/VideoLinkParserTests.swift` (adapt `oEmbedURL` assertions; add Piped test)
- Modify: `SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift` (switch on `metadataSource`; add Piped decode)
- Modify: `SpudDataKitTests/LinkEmbedServiceTests.swift` (add Piped test)

**Interfaces:**
- Consumes: `YouTubeReference.extract`, `YouTubeFrontEndCatalog.instance(forHost:)`, `YouTubeFrontEndKind` (Task 1).
- Produces:
  - `enum VideoHost { case youtube, invidious, piped, peertube }`
  - `struct VideoLink { let host: VideoHost; let videoId: String; let thumbnailURL: URL?; let metadataSource: MetadataSource }`
  - `enum VideoLink.MetadataSource: Equatable, Sendable { case oEmbed(URL); case pipedStreams(URL); case none }`
  - `VideoLinkParser.parse(_ url: URL) -> VideoLink?` (unchanged signature)

- [ ] **Step 1: Update the preview tests (failing)**

In `SpudUtilKitTests/VideoLinkParserTests.swift`, add this helper inside the struct (below the existing `parse` helper):

```swift
    private func oEmbedURL(_ v: VideoLink) -> URL? {
        if case let .oEmbed(url) = v.metadataSource { return url }
        return nil
    }
```

Replace every `v.oEmbedURL` / `short.oEmbedURL` usage with the helper. Concretely:
- In `youtubeWatch_idFromQuery`: `#expect(oEmbedURL(v)?.host == "www.youtube.com")` and `#expect(oEmbedURL(v)?.path == "/oembed")`.
- In `youtubeEmbed_idFromPath`: `let oEmbed = try #require(oEmbedURL(v))`.
- In `youtubeOEmbedUrlIsCanonicalWatch_forYoutuBe`: `let oEmbed = try #require(oEmbedURL(v))`.
- In `redirectInvidious_watchIsYouTube`: `let oEmbed = try #require(oEmbedURL(v))`.
- In `invidious_watchShape`: `let oEmbed = try #require(oEmbedURL(v))`.
- In `peertube_wAndVideosWatch`: `#expect(oEmbedURL(short)?.path == "/services/oembed")`.

Then add a new Piped test:

```swift
    @Test
    func piped_classifiedAsPipedWithStreamsMetadata() throws {
        let v = try #require(parse("https://piped.video/watch?v=dQw4w9WgXcQ"))
        #expect(v.host == .piped)
        #expect(v.videoId == "dQw4w9WgXcQ")
        #expect(v.thumbnailURL == nil, "Piped thumbnail comes from the /streams API, not derivable")
        guard case let .pipedStreams(url) = v.metadataSource else {
            Issue.record("expected .pipedStreams metadata source")
            return
        }
        #expect(url.absoluteString == "https://api.piped.video/streams/dQw4w9WgXcQ")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/VideoLinkParserTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: BUILD FAILS — `value of type 'VideoLink' has no member 'metadataSource'` / `type 'VideoHost' has no member 'piped'`.

- [ ] **Step 3: Rewrite `VideoLinkParser.swift`**

Replace the entire contents of `SpudUtilKit/Markdown/VideoLinkParser.swift` with:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public enum VideoHost: Equatable, Sendable {
    case youtube
    case invidious
    case piped
    case peertube
}

/// A recognized video link and the derived resources to enrich its preview.
public struct VideoLink: Equatable, Sendable {
    /// How ``LinkEmbedService`` should fetch this link's title (and, when not
    /// locally derivable, thumbnail).
    public enum MetadataSource: Equatable, Sendable {
        /// oEmbed endpoint (YouTube, Invidious, PeerTube). `{ title, thumbnail_url }`.
        case oEmbed(URL)
        /// Piped `/streams/<id>` API. `{ title, thumbnailUrl }`.
        case pipedStreams(URL)
        /// No remote metadata available (front-end with unknown API host).
        case none
    }

    public let host: VideoHost
    public let videoId: String
    /// Locally-derivable thumbnail (YouTube/Invidious). nil for Piped/PeerTube,
    /// whose thumbnail comes from the metadata response.
    public let thumbnailURL: URL?
    public let metadataSource: MetadataSource
}

/// Classifies a URL as a known video link. Pure and side-effect free.
///
/// YouTube and its front-ends (Invidious/Piped, plus the `/watch?v=` shape
/// fallback) are recognized via ``YouTubeReference``. PeerTube is matched by URL
/// *shape*. A false positive merely yields a metadata fetch that fails and a card
/// that degrades to anchor text + host.
public enum VideoLinkParser {
    public static func parse(_ url: URL) -> VideoLink? {
        if let ref = YouTubeReference.extract(from: url) {
            return videoLink(from: ref)
        }

        guard let host = url.host?.lowercased() else { return nil }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // PeerTube (heuristic): /w/<id> or /videos/watch/<uuid>.
        if segments.count == 2, segments[0] == "w", isPeerTubeId(segments[1]) {
            return peerTube(id: segments[1], host: host, original: url)
        }
        if segments.count == 3, segments[0] == "videos", segments[1] == "watch", isPeerTubeId(segments[2]) {
            return peerTube(id: segments[2], host: host, original: url)
        }
        return nil
    }

    private static func videoLink(from ref: YouTubeReference) -> VideoLink {
        switch ref.sourceKind {
        case .youtube:
            // YouTube's oEmbed 404s on the /embed form and is most reliable on the
            // canonical watch URL, so always build url= from the id.
            let canonicalWatchURL = URL(string: "https://www.youtube.com/watch?v=\(ref.videoId)")
            return VideoLink(
                host: .youtube,
                videoId: ref.videoId,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(ref.videoId)/hqdefault.jpg"),
                metadataSource: oEmbedSource(host: "www.youtube.com", path: "/oembed", original: canonicalWatchURL)
            )

        case .frontEnd(.piped):
            // Privacy-first: resolve title/thumbnail from Piped's own API, never Google.
            let apiHost = YouTubeFrontEndCatalog.instance(forHost: ref.sourceHost)?.apiHost
            let streamsURL = apiHost.flatMap { URL(string: "https://\($0)/streams/\(ref.videoId)") }
            return VideoLink(
                host: .piped,
                videoId: ref.videoId,
                thumbnailURL: nil,
                metadataSource: streamsURL.map { .pipedStreams($0) } ?? .none
            )

        case .frontEnd(.invidious), .frontEndShape:
            // Privacy-first: thumbnail + oEmbed from the Invidious instance itself.
            let watchURL = URL(string: "https://\(ref.sourceHost)/watch?v=\(ref.videoId)")
            return VideoLink(
                host: .invidious,
                videoId: ref.videoId,
                thumbnailURL: URL(string: "https://\(ref.sourceHost)/vi/\(ref.videoId)/hqdefault.jpg"),
                metadataSource: oEmbedSource(host: ref.sourceHost, path: "/oembed", original: watchURL)
            )
        }
    }

    private static func peerTube(id: String, host: String, original: URL) -> VideoLink {
        VideoLink(
            host: .peertube,
            videoId: id,
            thumbnailURL: nil,
            metadataSource: oEmbedSource(host: host, path: "/services/oembed", original: original)
        )
    }

    /// `.oEmbed(https://<host><path>?url=<original>&format=json)`, or `.none` when
    /// `original` is nil.
    private static func oEmbedSource(host: String, path: String, original: URL?) -> VideoLink.MetadataSource {
        guard let original else { return .none }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url.map { .oEmbed($0) } ?? .none
    }

    /// PeerTube short ids / UUIDs: word chars + dashes, at least 6 long.
    private static func isPeerTubeId(_ s: String) -> Bool {
        s.count >= 6 && s.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
```

- [ ] **Step 4: Update `LinkEmbedService.swift`**

In `SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift`, replace the body of `embed(for:)` from the `var title` line through the `let embed = ...` line with a `switch`, and add the Piped response type. The method becomes:

```swift
    public func embed(for url: URL) async -> LinkEmbed? {
        guard let video = VideoLinkParser.parse(url) else { return nil }
        if let cached = await cache.value(for: url) { return cached }

        var title: String?
        var thumbnailURL = video.thumbnailURL

        switch video.metadataSource {
        case let .oEmbed(endpoint):
            if let data = await fetch(endpoint) {
                let response = try? JSONDecoder().decode(OEmbedResponse.self, from: data)
                title = response?.title
                if thumbnailURL == nil { thumbnailURL = response?.thumbnailUrl.flatMap(URL.init(string:)) }
            }
        case let .pipedStreams(endpoint):
            if let data = await fetch(endpoint) {
                let response = try? JSONDecoder().decode(PipedStreamsResponse.self, from: data)
                title = response?.title
                if thumbnailURL == nil { thumbnailURL = response?.thumbnailUrl.flatMap(URL.init(string:)) }
            }
        case .none:
            break
        }

        let embed = LinkEmbed(kind: .video, title: title, thumbnailURL: thumbnailURL)
        await cache.set(embed, for: url)
        return embed
    }
```

Add, next to the existing `private struct OEmbedResponse`:

```swift
/// Piped's `/streams/<id>` response (subset). Piped uses camelCase `thumbnailUrl`,
/// which maps 1:1 under the default key strategy.
private struct PipedStreamsResponse: Decodable {
    let title: String?
    let thumbnailUrl: String?
}
```

- [ ] **Step 5: Add the Piped embed test**

In `SpudDataKitTests/LinkEmbedServiceTests.swift`, add:

```swift
    @Test
    func piped_returnsTitleAndThumbnailFromStreamsApi() async throws {
        let json = #"{"title":"Some Video","thumbnailUrl":"https://api.piped.video/thumb.jpg"}"#.data(using: .utf8)!
        let service = LinkEmbedService { _ in json }
        let result = try await service.embed(for: #require(URL(string: "https://piped.video/watch?v=dQw4w9WgXcQ")))
        let embed = try #require(result)
        #expect(embed.kind == .video)
        #expect(embed.title == "Some Video")
        #expect(embed.thumbnailURL?.absoluteString == "https://api.piped.video/thumb.jpg")
    }
```

- [ ] **Step 6: Run the affected tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/VideoLinkParserTests \
  -only-testing:SpudDataKitTests/LinkEmbedServiceTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all `VideoLinkParserTests` and `LinkEmbedServiceTests` pass (Swift Testing `✔` lines).

- [ ] **Step 7: Commit**

```bash
git add SpudUtilKit/Markdown/VideoLinkParser.swift \
        SpudUtilKitTests/VideoLinkParserTests.swift \
        SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift \
        SpudDataKitTests/LinkEmbedServiceTests.swift
git commit -m "feat: privacy-first Piped previews via /streams API"
```

---

### Task 3: `rewriteThirdPartyFrontEnds` config flag + backward-compatible decode

**Files:**
- Modify: `SpudUtilKit/URLSanitizer/URLSanitizerConfig.swift` (add property, default, memberwise init param, custom `init(from:)`)
- Modify: `SpudUtilKitTests/URLSanitizerConfigTests.swift` (default false; legacy decode; round-trip)

**Interfaces:**
- Consumes: nothing new.
- Produces: `URLSanitizerConfig.rewriteThirdPartyFrontEnds: Bool` (default `false`); decoding tolerates JSON written before the key existed.

- [ ] **Step 1: Write the failing tests**

In `SpudUtilKitTests/URLSanitizerConfigTests.swift`, add:

```swift
    @Test
    func default_rewriteThirdPartyFrontEndsOff() {
        #expect(!(URLSanitizerConfig.default.rewriteThirdPartyFrontEnds))
    }

    @Test
    func decodesLegacyConfigWithoutRewriteFlag() throws {
        // JSON written before rewriteThirdPartyFrontEnds existed.
        let legacy = #"""
        {"isEnabled":true,"stripTrackingParams":true,"unwrapRedirectors":true,"upgradeToHTTPS":true,"deAMP":true,"redirectToFrontEnds":true,"frontEnds":[]}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(URLSanitizerConfig.self, from: legacy)
        #expect(!(decoded.rewriteThirdPartyFrontEnds))
        #expect(decoded.redirectToFrontEnds)
        #expect(decoded.isEnabled)
    }

    @Test
    func rewriteFlagRoundTrips() throws {
        var config = URLSanitizerConfig.default
        config.rewriteThirdPartyFrontEnds = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(URLSanitizerConfig.self, from: data)
        #expect(decoded.rewriteThirdPartyFrontEnds)
        #expect(decoded == config)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/URLSanitizerConfigTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: BUILD FAILS — `value of type 'URLSanitizerConfig' has no member 'rewriteThirdPartyFrontEnds'`.

- [ ] **Step 3: Add the property, default, init param, and custom decode**

In `SpudUtilKit/URLSanitizer/URLSanitizerConfig.swift`:

(a) Add the stored property after `redirectToFrontEnds`:

```swift
    /// When true, links already on a third-party front-end (Invidious/Piped) are
    /// also normalized to the chosen YouTube front-end host — e.g. open Invidious
    /// links in Piped. Subordinate to ``redirectToFrontEnds`` and the youtube
    /// service being enabled. Canonical youtube.com/youtu.be rewriting ignores
    /// this flag.
    public var rewriteThirdPartyFrontEnds: Bool
```

(b) Add the parameter to the memberwise `init` (after `redirectToFrontEnds: Bool,`) and assign it. The `init` signature gains `rewriteThirdPartyFrontEnds: Bool,` (place it immediately after `redirectToFrontEnds: Bool,`) with `self.rewriteThirdPartyFrontEnds = rewriteThirdPartyFrontEnds` in the body.

(c) In `static let default`, add `rewriteThirdPartyFrontEnds: false,` immediately after `redirectToFrontEnds: false,`.

(d) Add a custom `Decodable` init so pre-existing stored JSON (without the new key) still loads. Add this inside the struct (Swift keeps synthesizing `encode(to:)` and `CodingKeys` from the stored properties):

```swift
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        stripTrackingParams = try container.decode(Bool.self, forKey: .stripTrackingParams)
        unwrapRedirectors = try container.decode(Bool.self, forKey: .unwrapRedirectors)
        upgradeToHTTPS = try container.decode(Bool.self, forKey: .upgradeToHTTPS)
        deAMP = try container.decode(Bool.self, forKey: .deAMP)
        redirectToFrontEnds = try container.decode(Bool.self, forKey: .redirectToFrontEnds)
        frontEnds = try container.decode([FrontEndConfig].self, forKey: .frontEnds)
        // New in 2026-07: absent in configs written by older builds.
        rewriteThirdPartyFrontEnds = try container.decodeIfPresent(Bool.self, forKey: .rewriteThirdPartyFrontEnds) ?? false
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/URLSanitizerConfigTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all `URLSanitizerConfigTests` pass, including the existing `codableRoundTrip`.

- [ ] **Step 5: Commit**

```bash
git add SpudUtilKit/URLSanitizer/URLSanitizerConfig.swift \
        SpudUtilKitTests/URLSanitizerConfigTests.swift
git commit -m "feat: add rewriteThirdPartyFrontEnds config flag (backward-compatible decode)"
```

---

### Task 4: id-based YouTube rewrite in `FrontEndRewriteStep`

**Files:**
- Modify: `SpudUtilKit/URLSanitizer/Steps/FrontEndRewriteStep.swift` (add id-based YouTube branch before the generic host-swap loop)
- Modify: `SpudUtilKitTests/FrontEndRewriteStepTests.swift` (add real-id grammar + gated-front-end tests)

**Interfaces:**
- Consumes: `YouTubeReference.extract` (Task 1), `URLSanitizerConfig.rewriteThirdPartyFrontEnds` (Task 3).
- Produces: no new public API; behavior change to `FrontEndRewriteStep.apply`.

Note: the existing tests in `rewritesYouTubeRedditImgur` use fake short ids (`abc`), which are NOT valid 11-char YouTube ids — so `YouTubeReference.extract` returns nil for them and they keep hitting the generic host-swap path unchanged. Do not modify those assertions; they must keep passing.

- [ ] **Step 1: Write the failing tests**

In `SpudUtilKitTests/FrontEndRewriteStepTests.swift`, add:

```swift
    @Test
    func youtubeVideo_rewritesToWatchGrammarOnChosenHost() {
        let c = allEnabled() // youtube host = catalog default "yewtu.be"
        #expect(rewritten("https://youtu.be/dQw4w9WgXcQ?t=90", c) == "https://yewtu.be/watch?v=dQw4w9WgXcQ&t=90")
        #expect(rewritten("https://www.youtube.com/shorts/dQw4w9WgXcQ", c) == "https://yewtu.be/watch?v=dQw4w9WgXcQ")
        #expect(rewritten("https://www.youtube.com/watch?v=dQw4w9WgXcQ", c) == "https://yewtu.be/watch?v=dQw4w9WgXcQ")
    }

    @Test
    func thirdPartyFrontEnd_rewrittenOnlyWhenFlagOn() {
        var c = allEnabled()
        // Flag off (default): a front-end video link is left unchanged.
        #expect(rewritten("https://piped.video/watch?v=dQw4w9WgXcQ", c) == "https://piped.video/watch?v=dQw4w9WgXcQ")
        #expect(rewritten("https://inv.nadeko.net/watch?v=dQw4w9WgXcQ", c) == "https://inv.nadeko.net/watch?v=dQw4w9WgXcQ")

        // Flag on: normalize to the chosen host.
        c.rewriteThirdPartyFrontEnds = true
        #expect(rewritten("https://piped.video/watch?v=dQw4w9WgXcQ", c) == "https://yewtu.be/watch?v=dQw4w9WgXcQ")
        #expect(rewritten("https://inv.nadeko.net/watch?v=dQw4w9WgXcQ", c) == "https://yewtu.be/watch?v=dQw4w9WgXcQ")
    }

    @Test
    func invidiousLinkOpensInPipedWhenChosen() {
        var c = allEnabled()
        c.rewriteThirdPartyFrontEnds = true
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .youtube else { return entry }
            return FrontEndConfig(service: .youtube, isEnabled: true, host: "piped.video")
        }
        #expect(rewritten("https://yewtu.be/watch?v=dQw4w9WgXcQ", c) == "https://piped.video/watch?v=dQw4w9WgXcQ")
    }

    @Test
    func youtubeVideoNotRewrittenWhenYoutubeServiceDisabled() {
        var c = allEnabled()
        c.frontEnds = c.frontEnds.map { entry in
            guard entry.service == .youtube else { return entry }
            return FrontEndConfig(service: .youtube, isEnabled: false, host: entry.host)
        }
        #expect(rewritten("https://youtu.be/dQw4w9WgXcQ", c) == "https://youtu.be/dQw4w9WgXcQ")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/FrontEndRewriteStepTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: the four new tests FAIL (e.g. `youtu.be/dQw4w9WgXcQ?t=90` currently host-swaps to `https://yewtu.be/dQw4w9WgXcQ?t=90`, not the `/watch?v=` grammar).

- [ ] **Step 3: Add the id-based YouTube branch**

Replace the contents of `SpudUtilKit/URLSanitizer/Steps/FrontEndRewriteStep.swift` with:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Rewrites a URL to a configured privacy front-end. For YouTube video links
/// (canonical or any recognized front-end/`/watch?v=` shape) it extracts the
/// video id and rebuilds a grammar-correct `/watch?v=<id>` on the chosen host —
/// so `youtu.be/<id>` and `/shorts/<id>` normalize correctly and, when
/// ``URLSanitizerConfig/rewriteThirdPartyFrontEnds`` is on, an Invidious link can
/// open in Piped. Other services (and non-video YouTube pages) fall back to a
/// host-swap preserving path/query. Matches `www.`/`m.`/`mobile.` subdomains but
/// not arbitrary ones such as `api.twitter.com`.
public struct FrontEndRewriteStep: URLRewriteStep {
    public init() { }

    public func apply(_ url: URL, config: URLSanitizerConfig) -> URL {
        guard config.redirectToFrontEnds else { return url }

        // YouTube video links: id-based, grammar-correct rewrite (canonical always;
        // third-party front-ends only when the flag is on).
        let youtube = config.setting(for: .youtube)
        if youtube.isEnabled, !youtube.host.isEmpty,
           let ref = YouTubeReference.extract(from: url),
           ref.sourceKind == .youtube || config.rewriteThirdPartyFrontEnds,
           let rewritten = watchURL(host: youtube.host, id: ref.videoId, seconds: ref.timestampSeconds) {
            return rewritten
        }

        // Generic host-swap for the remaining sources (twitter/reddit/imgur, and
        // non-video youtube.com pages such as channels/playlists).
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.host?.lowercased()
        else {
            return url
        }

        let baseHost: String
        if let label = ["www.", "mobile.", "m."].first(where: { host.hasPrefix($0) }) {
            baseHost = String(host.dropFirst(label.count))
        } else {
            baseHost = host
        }

        for entry in FrontEndCatalog.entries {
            let setting = config.setting(for: entry.service)
            guard setting.isEnabled, !setting.host.isEmpty else { continue }
            guard entry.sourceDomains.contains(baseHost) else { continue }
            components.host = setting.host
            return components.url ?? url
        }
        return url
    }

    /// `https://<host>/watch?v=<id>[&t=<seconds>]`.
    private func watchURL(host: String, id: String, seconds: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/watch"
        var items = [URLQueryItem(name: "v", value: id)]
        if let seconds { items.append(URLQueryItem(name: "t", value: String(seconds))) }
        components.queryItems = items
        return components.url
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -only-testing:SpudUtilKitTests/FrontEndRewriteStepTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation test
```
Expected: all `FrontEndRewriteStepTests` pass — the four new ones AND every pre-existing one (`rewritesYouTubeRedditImgur` with `abc` still host-swaps, twitter/reddit/imgur unchanged).

- [ ] **Step 5: Commit**

```bash
git add SpudUtilKit/URLSanitizer/Steps/FrontEndRewriteStep.swift \
        SpudUtilKitTests/FrontEndRewriteStepTests.swift
git commit -m "feat: id-based YouTube front-end rewrite (fixes youtu.be grammar; enables Invidious->Piped)"
```

---

### Task 5: Preferences toggle ("Rewrite Third-Party Front-ends")

**Files:**
- Modify: `Spud/Scenes/Preferences/PreferencesViewModel.swift` (add `updateRewriteThirdPartyFrontEnds`)
- Modify: `Spud/Scenes/Preferences/PreferencesPrivacyView.swift` (add the Toggle + footer note)

**Interfaces:**
- Consumes: `URLSanitizerConfig.rewriteThirdPartyFrontEnds` (Task 3), the existing `mutateSanitizerConfig` helper.
- Produces: `PreferencesViewModel.updateRewriteThirdPartyFrontEnds(_ value: Bool)`.

This is UI wiring with no unit-test target for the SwiftUI view; verify by building and by the full test plan staying green (Task 6), plus a manual settings check.

- [ ] **Step 1: Add the view-model update method**

In `Spud/Scenes/Preferences/PreferencesViewModel.swift`, immediately after `updateRedirectToFrontEnds(_:)`, add:

```swift
    func updateRewriteThirdPartyFrontEnds(_ value: Bool) {
        mutateSanitizerConfig { $0.rewriteThirdPartyFrontEnds = value }
    }
```

- [ ] **Step 2: Add the Toggle to the Front-ends section**

In `Spud/Scenes/Preferences/PreferencesPrivacyView.swift`, in the `Section` whose header is `Text("Front-ends")`, insert this Toggle immediately after the existing `Toggle("Redirect to Front-ends", ...)` and before the `ForEach(FrontEndService.allCases, ...)`:

```swift
                Toggle("Rewrite Third-Party Front-ends", isOn: toggle(viewModel.urlSanitizerConfig.rewriteThirdPartyFrontEnds) {
                    viewModel.updateRewriteThirdPartyFrontEnds($0)
                })
                .disabled(!viewModel.urlSanitizerConfig.redirectToFrontEnds)
```

Then update that section's `footer` text to explain the new toggle. Replace the existing footer:

```swift
            } footer: {
                Text("Public front-end instances change often. If one stops working, edit its host or turn it off.")
            }
```

with:

```swift
            } footer: {
                Text("Public front-end instances change often. If one stops working, edit its host or turn it off. \"Rewrite Third-Party Front-ends\" also re-points links already on a front-end (e.g. Invidious) to your chosen host.")
            }
```

- [ ] **Step 3: Build the app target to verify it compiles**

Run:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Spud/Scenes/Preferences/PreferencesViewModel.swift \
        Spud/Scenes/Preferences/PreferencesPrivacyView.swift
git commit -m "feat: add Rewrite Third-Party Front-ends settings toggle"
```

---

### Task 6: Docs, format, and full verification

**Files:**
- Modify: `docs/features/external-link-handling.md`
- Modify: `docs/features/README.md` (reconcile capability table + by-area map if wording drifts)

**Interfaces:** none (documentation + verification only).

- [ ] **Step 1: Update `external-link-handling.md`**

In the "Load Link Previews (default on)" bullet, change the list of recognized hosts to include Piped and note the resolution source. Replace the sentence fragment "for YouTube, Invidious, and PeerTube video links fetch a thumbnail and title via oEmbed" with:

```
for YouTube, Invidious, Piped, and PeerTube video links fetch a thumbnail and title before displaying — YouTube via Google's oEmbed, Invidious via the instance's own oEmbed, and Piped via its `/streams` API (front-end links are resolved from the front-end itself, never Google)
```

In the "Redirect to Front-ends" bullet, append:

```
Video links are recognized on any wrapper form (`youtu.be`, `/shorts`, `/live`, Invidious, Piped) and rewritten to a grammar-correct `/watch?v=<id>` on the chosen host. A separate "Rewrite Third-Party Front-ends" toggle controls whether links already on a front-end (e.g. Invidious) are re-pointed to your chosen host (e.g. open Invidious links in Piped); when off, only canonical `youtube.com`/`youtu.be` links are rewritten.
```

Add three Given/When/Then scenarios in the Scenarios section:

```markdown
### Piped link preview resolves privately via Piped's API

- **Given** Load Link Previews is on
- **And** a comment contains a `piped.video/watch?v=<id>` link
- **Then** the preview card shows the video title and thumbnail fetched from Piped's `/streams` API
- **And** no request is made to Google (`i.ytimg.com` / `youtube.com`)

### Rewrite Third-Party Front-ends on — Invidious link opens in the chosen front-end

- **Given** Clean Outgoing Links and Redirect to Front-ends are on
- **And** the YouTube front-end host is set to `piped.video`
- **And** Rewrite Third-Party Front-ends is on
- **When** the user opens an `yewtu.be/watch?v=<id>` link
- **Then** it opens as `https://piped.video/watch?v=<id>`

### Rewrite Third-Party Front-ends off — front-end links are left alone

- **Given** Redirect to Front-ends is on and Rewrite Third-Party Front-ends is off
- **When** the user opens an `yewtu.be/watch?v=<id>` link
- **Then** it opens unchanged (only canonical youtube.com/youtu.be links are rewritten)
```

- [ ] **Step 2: Reconcile the README feature index**

Open `docs/features/README.md`. If the capability table or "Feature coverage by area" map describes link cleaning / front-end redirect / link previews, update the wording to mention Piped support and the "Rewrite Third-Party Front-ends" control. If no row needs changing, make no edit. Keep `Status:` honest.

- [ ] **Step 3: Format changed Swift files**

Run:
```bash
mint run swiftformat \
  SpudUtilKit/URLSanitizer/YouTubeFrontEndCatalog.swift \
  SpudUtilKit/Markdown/YouTubeReference.swift \
  SpudUtilKit/Markdown/VideoLinkParser.swift \
  SpudUtilKit/URLSanitizer/URLSanitizerConfig.swift \
  SpudUtilKit/URLSanitizer/Steps/FrontEndRewriteStep.swift \
  SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift \
  Spud/Scenes/Preferences/PreferencesViewModel.swift \
  Spud/Scenes/Preferences/PreferencesPrivacyView.swift \
  SpudUtilKitTests/YouTubeReferenceTests.swift \
  SpudUtilKitTests/VideoLinkParserTests.swift \
  SpudUtilKitTests/URLSanitizerConfigTests.swift \
  SpudUtilKitTests/FrontEndRewriteStepTests.swift \
  SpudDataKitTests/LinkEmbedServiceTests.swift
```
Expected: files reformatted in place (or no changes). If SwiftFormat rewrites anything, re-run the relevant test target to confirm still-green before committing.

- [ ] **Step 4: Full unit-test verification**

Run the whole Spud test plan:
```bash
xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -skipPackagePluginValidation -skipMacroValidation \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 test
```
Expected: TEST SUCCEEDED — all suites pass, including SpudUtilKitTests, SpudDataKitTests, and the pre-existing UI tests. (Snapshot tests are a separate plan; no snapshots change in this feature.)

- [ ] **Step 5: On-device Piped API sanity check (verify the seeded apiHost)**

The `piped.video` `apiHost` was seeded as `api.piped.video` and must serve `/streams/<id>`. Verify it resolves (the app degrades gracefully if not, but the seed should be correct):
```bash
curl -sS -o /dev/null -w "%{http_code}\n" "https://api.piped.video/streams/dQw4w9WgXcQ"
```
Expected: `200`. If it is not 200, find the correct API host from the official Piped instances list (https://github.com/TeamPiped/Piped/wiki/Instances) and update the `piped.video` entry's `apiHost` in `YouTubeFrontEndCatalog.swift`, then re-run Task 2 Step 6.

- [ ] **Step 6: Commit docs (and any apiHost correction)**

```bash
git add docs/features/external-link-handling.md docs/features/README.md
# include YouTubeFrontEndCatalog.swift too if Step 5 corrected the apiHost
git commit -m "docs: document Piped previews + Rewrite Third-Party Front-ends"
```

---

## Notes for the executor

- Run `make project` once (Task 1 Step 5) after the new files exist; later tasks only modify existing files.
- If a run reports "Simulator device failed to launch ... Busy", another iPhone 17 sim is already booted — target the booted sim by id (`xcrun simctl list devices | grep Booted`) instead of `name=`.
- Swift Testing prints "Executed 0 tests" in the XCTest summary for Swift-Testing-only targets; trust the `✔ Test run with N tests ... passed` line and per-test `✔`/`✘`.
- Do not run `git add -A`; stage the explicit paths listed. Never stage `.remember/remember.md`.
