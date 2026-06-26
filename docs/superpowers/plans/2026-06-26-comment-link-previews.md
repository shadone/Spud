# Comment & body link previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich in-body link-preview cards (comments, post bodies) with the link's anchor text plus a thumbnail and title for video links (YouTube / Invidious / PeerTube), and show the server-provided title/thumbnail on the post-header link card — gated by a default-on "Load link previews" preference.

**Architecture:** A pure `VideoLinkParser` (SpudUtilKit) classifies video URLs and derives thumbnail/oEmbed URLs. A `LinkEmbedService` (SpudDataKit) fetches the oEmbed title (and PeerTube thumbnail), caching results. `CommentLinkPreview` gains anchor text + a kind; the existing `LinkPreviewView` card is enhanced to show title + anchor text + a play badge. The comment cell and post-header cell fill cards asynchronously when the preference is on. The preference gating lives in the app target (the cell), keeping `LinkEmbedService` dependency-clean.

**Tech Stack:** Swift 6, UIKit, GRDB-backed services, `swift-snapshot-testing`, XCTest. Frameworks: `SpudUtilKit` (pure), `SpudMarkdownKit` (markdown model), `SpudDataKit` (services), `Spud` (app).

## Global Constraints

- No emojis in code, comments, docs, or commit messages.
- `.swiftformat` is authoritative; run `mint run swiftformat <paths>` before staging.
- Frameworks must not import the app target. `LinkEmbedService` (SpudDataKit) must NOT read `PreferencesService` (app target) — the preference is checked by the app-target caller.
- Swift 6 language mode is on for all shipped targets + `SpudDataKitTests`; `SpudUtilKitTests` / `SpudMarkdownKitTests` follow their target's mode.
- Tests run on **iPhone 17 Pro**. Snapshot refs are git-annex managed — record one class at a time, `git add` only the specific re-recorded refs.
- After adding a new source file, run `make project` (XcodeGen) before building.
- Build/test wrapper: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"`. For a single test class use `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:<Target>/<Class> -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`.
- Per-comment preview cap stays at **3** (`commentLinkPreviews(limit: 3)`).
- Preference default: `fetchLinkEmbeds = true`. Off ⇒ in-body cards are local only (anchor text + host), zero third-party contact.

---

### Task 1: `VideoLinkParser` (pure URL classifier)

**Files:**
- Create: `SpudUtilKit/Markdown/VideoLinkParser.swift`
- Test: `SpudUtilKitTests/VideoLinkParserTests.swift`

**Interfaces:**
- Produces:
  - `public enum VideoHost: Equatable, Sendable { case youtube, invidious, peertube }`
  - `public struct VideoLink: Equatable, Sendable { public let host: VideoHost; public let videoId: String; public let thumbnailURL: URL?; public let oEmbedURL: URL? }`
  - `public enum VideoLinkParser { public static func parse(_ url: URL) -> VideoLink? }`

- [ ] **Step 1: Write the failing test**

Create `SpudUtilKitTests/VideoLinkParserTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudUtilKit

final class VideoLinkParserTests: XCTestCase {
    private func parse(_ s: String) -> VideoLink? {
        VideoLinkParser.parse(URL(string: s)!)
    }

    func test_youtubeWatch_idFromQuery() throws {
        let v = try XCTUnwrap(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5"))
        XCTAssertEqual(v.host, .youtube)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(v.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(v.oEmbedURL?.host, "www.youtube.com")
        XCTAssertEqual(v.oEmbedURL?.path, "/oembed")
    }

    func test_youtubeShort_idFromPath() throws {
        let v = try XCTUnwrap(parse("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertEqual(v.host, .youtube)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
    }

    func test_youtubeNoCookieAndMobileHosts() throws {
        XCTAssertEqual(parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ")?.host, .youtube)
        XCTAssertEqual(parse("https://www.youtube-nocookie.com/watch?v=dQw4w9WgXcQ")?.host, .youtube)
    }

    func test_invidious_watchShape() throws {
        let v = try XCTUnwrap(parse("https://yewtu.be/watch?v=dQw4w9WgXcQ"))
        XCTAssertEqual(v.host, .invidious)
        XCTAssertEqual(v.videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(v.thumbnailURL?.absoluteString, "https://yewtu.be/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(v.oEmbedURL?.absoluteString, "https://yewtu.be/oembed?url=https://yewtu.be/watch%3Fv%3DdQw4w9WgXcQ&format=json")
    }

    func test_peertube_wAndVideosWatch() throws {
        let short = try XCTUnwrap(parse("https://video.example/w/abc123XYZ"))
        XCTAssertEqual(short.host, .peertube)
        XCTAssertEqual(short.videoId, "abc123XYZ")
        XCTAssertNil(short.thumbnailURL, "PeerTube thumbnail comes from oEmbed, not derivable")
        XCTAssertEqual(short.oEmbedURL?.path, "/services/oembed")

        let long = try XCTUnwrap(parse("https://video.example/videos/watch/9c9de5e8-0a1e-484a-b099-e80766180a6d"))
        XCTAssertEqual(long.host, .peertube)
        XCTAssertEqual(long.videoId, "9c9de5e8-0a1e-484a-b099-e80766180a6d")
    }

    func test_negatives() {
        XCTAssertNil(parse("https://example.com/article"))
        XCTAssertNil(parse("https://example.com/image.jpg"))
        XCTAssertNil(parse("https://lemmy.world/c/games/p/1/slug"))
        XCTAssertNil(parse("https://example.com/watch?v=short")) // id too short for YT shape
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudUtilKitTests/VideoLinkParserTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `cannot find 'VideoLinkParser' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `SpudUtilKit/Markdown/VideoLinkParser.swift`:

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
    case peertube
}

/// A recognized video link and the derived resources to enrich its preview.
public struct VideoLink: Equatable, Sendable {
    public let host: VideoHost
    public let videoId: String
    /// Locally-derivable thumbnail (YouTube/Invidious). nil for PeerTube (its
    /// thumbnail comes from the oEmbed response).
    public let thumbnailURL: URL?
    /// The host's oEmbed endpoint for this link, used to fetch the title.
    public let oEmbedURL: URL?
}

/// Classifies a URL as a known video link. Pure and side-effect free.
///
/// YouTube is matched by host. Invidious and PeerTube are matched by URL *shape*
/// (there is no instance allowlist) — a false positive merely yields an oEmbed
/// fetch that fails and a card that degrades to anchor text + host.
public enum VideoLinkParser {
    private static let youTubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com",
        "music.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com",
    ]

    public static func parse(_ url: URL) -> VideoLink? {
        guard
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return nil
        }
        let segments = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        // YouTube (definitive, by host).
        if host == "youtu.be", let id = segments.first, isYouTubeId(id) {
            return youTube(id: id, original: url)
        }
        if youTubeHosts.contains(host), segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return youTube(id: id, original: url)
        }

        // Invidious (heuristic): non-YouTube host, /watch?v=<yt-id>.
        if segments.first == "watch", let id = queryValue("v", url), isYouTubeId(id) {
            return VideoLink(
                host: .invidious,
                videoId: id,
                thumbnailURL: URL(string: "https://\(host)/vi/\(id)/hqdefault.jpg"),
                oEmbedURL: oEmbedURL(host: host, path: "/oembed", original: url)
            )
        }

        // PeerTube (heuristic): /w/<id> or /videos/watch/<uuid>.
        if segments.count == 2, segments[0] == "w", isPeerTubeId(segments[1]) {
            return peerTube(id: segments[1], host: host, original: url)
        }
        if segments.count == 3, segments[0] == "videos", segments[1] == "watch", isPeerTubeId(segments[2]) {
            return peerTube(id: segments[2], host: host, original: url)
        }

        return nil
    }

    private static func youTube(id: String, original: URL) -> VideoLink {
        VideoLink(
            host: .youtube,
            videoId: id,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
            oEmbedURL: oEmbedURL(host: "www.youtube.com", path: "/oembed", original: original)
        )
    }

    private static func peerTube(id: String, host: String, original: URL) -> VideoLink {
        VideoLink(
            host: .peertube,
            videoId: id,
            thumbnailURL: nil,
            oEmbedURL: oEmbedURL(host: host, path: "/services/oembed", original: original)
        )
    }

    /// `https://<host><path>?url=<original>&format=json`.
    private static func oEmbedURL(host: String, path: String, original: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "url", value: original.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    private static func queryValue(_ name: String, _ url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }

    /// YouTube ids are exactly 11 chars of [A-Za-z0-9_-].
    private static func isYouTubeId(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0 == "_" || $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// PeerTube short ids / UUIDs: word chars + dashes, at least 6 long.
    private static func isPeerTubeId(_ s: String) -> Bool {
        s.count >= 6 && s.allSatisfy { $0 == "-" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }
}
```

- [ ] **Step 4: Add the file to the project, run the test**

Run: `make project` then the Step 2 command.
Expected: PASS — all `VideoLinkParserTests` green. (If `test_invidious_watchShape`'s oEmbed assertion fails on percent-encoding, relax it to assert `oEmbedURL?.path == "/oembed"` and the `url` query item equals the original; URL query encoding of `?`/`=` is acceptable either way.)

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudUtilKit/Markdown/VideoLinkParser.swift SpudUtilKitTests/VideoLinkParserTests.swift
git add SpudUtilKit/Markdown/VideoLinkParser.swift SpudUtilKitTests/VideoLinkParserTests.swift
git commit -m "feat: VideoLinkParser classifies YouTube/Invidious/PeerTube links"
```

---

### Task 2: `[MarkdownInline].plainText` flattener

**Files:**
- Create: `SpudMarkdownKit/Model/MarkdownInline+PlainText.swift`
- Test: `SpudMarkdownKitTests/MarkdownInlinePlainTextTests.swift`

**Interfaces:**
- Produces: `public extension [MarkdownInline] { var plainText: String { get } }` — flattens an inline run to a plain string (anchor text for a link).

- [ ] **Step 1: Write the failing test**

Create `SpudMarkdownKitTests/MarkdownInlinePlainTextTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import XCTest
@testable import SpudMarkdownKit

final class MarkdownInlinePlainTextTests: XCTestCase {
    func test_plainText_flattensTextAndEmphasis() {
        let inlines: [MarkdownInline] = [.text("Foo "), .strong([.text("bar")])]
        XCTAssertEqual(inlines.plainText, "Foo bar")
    }

    func test_plainText_code_and_mentions() {
        XCTAssertEqual([MarkdownInline.code("ls")].plainText, "ls")
        XCTAssertEqual([MarkdownInline.mention(name: "alice", instance: "lemmy.world")].plainText, "alice@lemmy.world")
        XCTAssertEqual([MarkdownInline.community(name: "tech", instance: "beehaw.org")].plainText, "tech@beehaw.org")
    }

    func test_plainText_link_usesItsOwnText() {
        let link = MarkdownInline.link(text: [.text("Foobar")], url: URL(string: "https://example.com")!)
        XCTAssertEqual([link].plainText, "Foobar")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme SpudMarkdownKit -only-testing:SpudMarkdownKitTests/MarkdownInlinePlainTextTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `value of type '[MarkdownInline]' has no member 'plainText'`.

- [ ] **Step 3: Write minimal implementation**

Create `SpudMarkdownKit/Model/MarkdownInline+PlainText.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

public extension [MarkdownInline] {
    /// The inline run flattened to plain text (e.g. a link's anchor text). Styling
    /// is dropped; mentions/communities render as `name@instance`.
    var plainText: String {
        map(\.plainText).joined()
    }
}

public extension MarkdownInline {
    var plainText: String {
        switch self {
        case let .text(s), let .code(s), let .emoji(s):
            return s
        case let .customEmoji(shortcode):
            return ":\(shortcode):"
        case let .strong(children),
             let .emphasis(children),
             let .strikethrough(children),
             let .highlight(children),
             let .superscript(children),
             let .subscript(children):
            return children.plainText
        case let .link(text, _):
            return text.plainText
        case let .mention(name, instance), let .community(name, instance):
            return "\(name)@\(instance)"
        case let .footnoteReference(label):
            return "[\(label)]"
        }
    }
}
```

- [ ] **Step 4: Add the file, run the test**

Run: `make project` then the Step 2 command.
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat SpudMarkdownKit/Model/MarkdownInline+PlainText.swift SpudMarkdownKitTests/MarkdownInlinePlainTextTests.swift
git add SpudMarkdownKit/Model/MarkdownInline+PlainText.swift SpudMarkdownKitTests/MarkdownInlinePlainTextTests.swift
git commit -m "feat: add [MarkdownInline].plainText flattener"
```

---

### Task 3: `LinkEmbed` model + `LinkEmbedService`

**Files:**
- Create: `SpudDataKit/Services/LinkEmbed/LinkEmbed.swift`
- Create: `SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift`
- Test: `SpudDataKitTests/LinkEmbedServiceTests.swift`

**Interfaces:**
- Consumes: `VideoLinkParser.parse` (SpudUtilKit).
- Produces:
  - `public struct LinkEmbed: Equatable, Sendable { public enum Kind: Sendable { case video, generic }; public let kind: Kind; public let title: String?; public let thumbnailURL: URL? }`
  - `public protocol LinkEmbedServiceType: Sendable { func embed(for url: URL) async -> LinkEmbed? }`
  - `public final class LinkEmbedService: LinkEmbedServiceType` with `public init(fetch: @escaping @Sendable (URL) async -> Data? = { try? await URLSession.shared.data(from: $0).0 })`.

Note: the service is **preference-agnostic** (the app-target caller gates it). It returns `nil` for non-video URLs (generic links get only anchor text + host in the UI, no fetch).

- [ ] **Step 1: Write the failing test**

Create `SpudDataKitTests/LinkEmbedServiceTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import XCTest
@testable import SpudDataKit

final class LinkEmbedServiceTests: XCTestCase {
    private func youtubeOEmbedJSON(title: String) -> Data {
        #"{"title":"\#(title)","thumbnail_url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"}"#.data(using: .utf8)!
    }

    func test_youtube_returnsTitleAndDerivedThumbnail() async throws {
        let service = LinkEmbedService { _ in self.youtubeOEmbedJSON(title: "Never Gonna Give You Up") }
        let embed = try XCTUnwrap(await service.embed(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!))
        XCTAssertEqual(embed.kind, .video)
        XCTAssertEqual(embed.title, "Never Gonna Give You Up")
        XCTAssertEqual(embed.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    func test_nonVideoLink_returnsNilWithoutFetching() async {
        let fetched = Atomic(false)
        let service = LinkEmbedService { _ in fetched.value = true; return nil }
        let embed = await service.embed(for: URL(string: "https://example.com/article")!)
        XCTAssertNil(embed)
        XCTAssertFalse(fetched.value, "must not fetch for a non-video link")
    }

    func test_oEmbedFailure_keepsDerivedThumbnail() async throws {
        let service = LinkEmbedService { _ in nil } // network/JSON failure
        let embed = try XCTUnwrap(await service.embed(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!))
        XCTAssertNil(embed.title)
        XCTAssertEqual(embed.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
    }

    func test_cache_secondCallDoesNotRefetch() async {
        let count = Atomic(0)
        let service = LinkEmbedService { _ in count.value += 1; return self.youtubeOEmbedJSON(title: "t") }
        _ = await service.embed(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!)
        _ = await service.embed(for: URL(string: "https://youtu.be/dQw4w9WgXcQ")!)
        XCTAssertEqual(count.value, 1)
    }
}
```

(`Atomic` is the existing `SpudUtilKit` helper — add `import SpudUtilKit` if the test needs it; if `Atomic` isn't visible, use an `actor` counter instead.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudDataKitTests/LinkEmbedServiceTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `cannot find 'LinkEmbedService' in scope`.

- [ ] **Step 3: Write the model**

Create `SpudDataKit/Services/LinkEmbed/LinkEmbed.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation

/// Resolved preview metadata for a link. `title` is fetched (oEmbed) for video
/// links; `thumbnailURL` is derived locally (YouTube/Invidious) or from oEmbed
/// (PeerTube).
public struct LinkEmbed: Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case video
        case generic
    }

    public let kind: Kind
    public let title: String?
    public let thumbnailURL: URL?

    public init(kind: Kind, title: String?, thumbnailURL: URL?) {
        self.kind = kind
        self.title = title
        self.thumbnailURL = thumbnailURL
    }
}
```

- [ ] **Step 4: Write the service**

Create `SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import SpudUtilKit

public protocol LinkEmbedServiceType: Sendable {
    /// Resolves preview metadata for a recognized video link, else nil. Caches by
    /// URL. Network/parse failures degrade to the derived thumbnail (no title).
    func embed(for url: URL) async -> LinkEmbed?
}

public final class LinkEmbedService: LinkEmbedServiceType {
    private let fetch: @Sendable (URL) async -> Data?
    private let cache = LinkEmbedCache()

    public init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    public func embed(for url: URL) async -> LinkEmbed? {
        guard let video = VideoLinkParser.parse(url) else { return nil }
        if let cached = await cache.value(for: url) { return cached }

        var title: String?
        var thumbnailURL = video.thumbnailURL
        if let oEmbedURL = video.oEmbedURL, let data = await fetch(oEmbedURL) {
            let response = try? JSONDecoder().decode(OEmbedResponse.self, from: data)
            title = response?.title
            if thumbnailURL == nil { thumbnailURL = response?.thumbnailUrl.flatMap(URL.init(string:)) }
        }

        let embed = LinkEmbed(kind: .video, title: title, thumbnailURL: thumbnailURL)
        await cache.set(embed, for: url)
        return embed
    }
}

private struct OEmbedResponse: Decodable {
    let title: String?
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnailUrl = "thumbnail_url"
    }
}

/// Small in-memory cache. An actor for thread-safety; results are cheap to
/// recompute across launches, so no disk persistence in v1.
private actor LinkEmbedCache {
    private var storage: [String: LinkEmbed] = [:]

    func value(for url: URL) -> LinkEmbed? { storage[url.absoluteString] }
    func set(_ embed: LinkEmbed, for url: URL) { storage[url.absoluteString] = embed }
}
```

- [ ] **Step 5: Add the files, run the test**

Run: `make project` then the Step 2 command.
Expected: PASS. (If `Atomic` is unavailable in `SpudDataKitTests`, replace the two tests' counters with an `actor Counter { var n = 0; func bump() { n += 1 } }` and `await`.)

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat SpudDataKit/Services/LinkEmbed/LinkEmbed.swift SpudDataKit/Services/LinkEmbed/LinkEmbedService.swift SpudDataKitTests/LinkEmbedServiceTests.swift
git add SpudDataKit/Services/LinkEmbed/ SpudDataKitTests/LinkEmbedServiceTests.swift
git commit -m "feat: LinkEmbedService fetches oEmbed title for video links"
```

---

### Task 4: `fetchLinkEmbeds` preference + Settings toggle

**Files:**
- Modify: `Spud/Services/Preferences/PreferencesService.swift` (protocol ~line 105; impl ~line 292)
- Modify: `Spud/Scenes/Preferences/PreferencesViewModel.swift` (add `fetchLinkEmbeds` getter + `updateFetchLinkEmbeds`)
- Modify: `Spud/Scenes/Preferences/PreferencesGeneralView.swift` (add the toggle to the Links section)

**Interfaces:**
- Produces: `PreferencesService.fetchLinkEmbeds: Bool` (default `true`) + `fetchLinkEmbedsStream: AsyncStream<Bool>`.

- [ ] **Step 1: Add the preference to the protocol**

In `PreferencesService.swift`, after the `blurNsfwStream` protocol lines (~105), add:

```swift
    /// Whether the app fetches link-embed metadata (thumbnail + title) for video
    /// links in comment/post bodies. Default `true`. Off ⇒ in-body link cards
    /// stay local (anchor text + host), with no third-party fetch.
    var fetchLinkEmbeds: Bool { get set }
    var fetchLinkEmbedsStream: AsyncStream<Bool> { get }
```

And after the `blurNsfw` implementation (~292):

```swift
    @UserDefaultsBacked(key: "fetchLinkEmbeds")
    var fetchLinkEmbeds: Bool = true

    var fetchLinkEmbedsStream: AsyncStream<Bool> {
        $fetchLinkEmbeds
    }
```

- [ ] **Step 2: Add the view-model accessors**

Open `Spud/Scenes/Preferences/PreferencesViewModel.swift`, find the `blurNsfw` getter and `updateBlurNsfw` method, and add the parallel pair:

```swift
    var fetchLinkEmbeds: Bool { preferencesService.fetchLinkEmbeds }

    func updateFetchLinkEmbeds(_ value: Bool) {
        preferencesService.fetchLinkEmbeds = value
    }
```

(Match the surrounding style; if `blurNsfw` uses an `@Observable`/stream-backed property there, mirror that exact shape instead.)

- [ ] **Step 3: Add the toggle to the Links section**

Open `Spud/Scenes/Preferences/PreferencesGeneralView.swift`. Find the Section that holds the external-link ("Links") settings. Add the binding near the other bindings:

```swift
    private var fetchLinkEmbeds: Binding<Bool> {
        .init { viewModel.fetchLinkEmbeds } set: { viewModel.updateFetchLinkEmbeds($0) }
    }
```

And inside the Links Section, add the toggle (after the existing link-handling controls):

```swift
                Toggle(isOn: fetchLinkEmbeds) {
                    Label(
                        NSLocalizedString("Load Link Previews", comment: "Settings toggle: fetch link preview thumbnails/titles"),
                        systemImage: "rectangle.and.text.magnifyingglass"
                    )
                }
```

Add a footer line to that Section (or extend its existing footer):

```swift
                Text("Fetch thumbnails and titles for video links in comments and posts. Turn off to keep link previews local and avoid contacting third-party sites.")
```

- [ ] **Step 4: Build and verify the toggle appears**

Run: `python3 /Users/denis/dev/info.ddenis/dotfiles/agent-rules/skills/xcode-skill/scripts/build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"`
Expected: Build SUCCESS. (Manual check: Settings → General → Links shows "Load Link Previews", default on.)

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Services/Preferences/PreferencesService.swift Spud/Scenes/Preferences/PreferencesViewModel.swift Spud/Scenes/Preferences/PreferencesGeneralView.swift
git add Spud/Services/Preferences/PreferencesService.swift Spud/Scenes/Preferences/PreferencesViewModel.swift Spud/Scenes/Preferences/PreferencesGeneralView.swift
git commit -m "feat: add Load Link Previews preference + Settings toggle"
```

---

### Task 5: `CommentLinkPreview` — anchor text + kind

**Files:**
- Modify: `Spud/Utils/CommentLinkPreview.swift`
- Test: `SpudTests/CommentLinkPreviewTests.swift` (create if absent; otherwise extend the existing one)

**Interfaces:**
- Consumes: `[MarkdownInline].plainText` (Task 2), `VideoLinkParser.parse` (Task 1).
- Produces: `CommentLinkPreview` gains `let anchorText: String?` and `let kind: LinkPreviewKind` where `enum LinkPreviewKind { case video, generic }`.

- [ ] **Step 1: Write the failing test**

Create `SpudTests/CommentLinkPreviewTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudMarkdownKit
import XCTest
@testable import Spud

final class CommentLinkPreviewTests: XCTestCase {
    func test_webLink_carriesAnchorTextAndKind() throws {
        let blocks: [MarkdownBlock] = [.paragraph([
            .link(text: [.text("Foobar")], url: URL(string: "https://example.com")!),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        XCTAssertEqual(previews.count, 1)
        XCTAssertEqual(previews[0].anchorText, "Foobar")
        XCTAssertEqual(previews[0].kind, .generic)
    }

    func test_youtubeLink_isVideoKind() throws {
        let blocks: [MarkdownBlock] = [.paragraph([
            .link(text: [.text("a video")], url: URL(string: "https://youtu.be/dQw4w9WgXcQ")!),
        ])]
        let previews = blocks.commentLinkPreviews(limit: 3)
        XCTAssertEqual(previews.first?.kind, .video)
        XCTAssertEqual(previews.first?.anchorText, "a video")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan Spud -only-testing:SpudTests/CommentLinkPreviewTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — `value of type 'CommentLinkPreview' has no member 'anchorText'`.

- [ ] **Step 3: Extend the struct**

In `Spud/Utils/CommentLinkPreview.swift`, replace the struct with:

```swift
enum LinkPreviewKind: Equatable {
    case video
    case generic
}

struct CommentLinkPreview: Equatable {
    let displayURL: URL
    let tapURL: URL
    /// The link's anchor text (`[Foobar](url)` -> "Foobar"); nil when it equals the
    /// URL (a bare autolink).
    let anchorText: String?
    let kind: LinkPreviewKind
}
```

- [ ] **Step 4: Thread anchor text + kind through extraction**

In the same file, change the inline `.link` case in the inline collector to pass the anchor text, and update the two builder functions. Replace:

```swift
    case let .link(_, url):
        if let preview = webLinkPreview(for: url) {
            appendPreview(preview, into: &result, seen: &seen)
        }
```

with:

```swift
    case let .link(text, url):
        if let preview = webLinkPreview(for: url, anchorText: text.plainText) {
            appendPreview(preview, into: &result, seen: &seen)
        }
```

Replace `webLinkPreview`:

```swift
private func webLinkPreview(for url: URL, anchorText: String) -> CommentLinkPreview? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return nil
    }
    let trimmed = anchorText.trimmingCharacters(in: .whitespacesAndNewlines)
    // Drop anchor text that is just the URL (bare autolink) — the host line already shows it.
    let anchor = (trimmed.isEmpty || trimmed == url.absoluteString) ? nil : trimmed
    let kind: LinkPreviewKind = VideoLinkParser.parse(url) != nil ? .video : .generic
    return CommentLinkPreview(displayURL: url, tapURL: url, anchorText: anchor, kind: kind)
}
```

Replace `communityLinkPreview`'s return to include the new fields:

```swift
    return CommentLinkPreview(displayURL: displayURL, tapURL: tapURL, anchorText: nil, kind: .generic)
```

Add `import SpudUtilKit` if not already present (for `VideoLinkParser`) — it is already imported.

- [ ] **Step 5: Run the test**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat Spud/Utils/CommentLinkPreview.swift SpudTests/CommentLinkPreviewTests.swift
git add Spud/Utils/CommentLinkPreview.swift SpudTests/CommentLinkPreviewTests.swift
git commit -m "feat: CommentLinkPreview carries anchor text + video/generic kind"
```

---

### Task 6: `LinkPreviewView` enrichment + snapshots

**Files:**
- Modify: `Spud/Utils/Views/LinkPreviewView.swift`
- Test: `SpudSnapshotTests/LinkPreviewViewSnapshotTests.swift` (create)

**Interfaces:**
- Produces a new configure API on `LinkPreviewView`:
  - `var anchorText: String?` (primary line when no title)
  - `var title: String?` (primary line, bold, when present)
  - `var isVideo: Bool` (shows a ▶ badge over the thumbnail)
  - keeps `var url: URL?`, `var thumbnailImage: UIImage?`, `var tapped: ((URL) -> Void)?`, `prepareForReuse()`.

Layout: thumbnail (with optional ▶ badge) · vertical text [ title-or-anchor (label color, semibold) ; "anchor · host" or host (secondary) ] · chevron. When `title == nil && anchorText == nil`, the text is just host + path (current behavior).

- [ ] **Step 1: Write the failing snapshot tests**

Create `SpudSnapshotTests/LinkPreviewViewSnapshotTests.swift`:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SnapshotTesting
import UIKit
import XCTest
@testable import Spud

@MainActor
final class LinkPreviewViewSnapshotTests: XCTestCase {
    private let width: CGFloat = 350

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: style),
            UITraitCollection(displayScale: 2),
        ])
    }

    private func fit(_ view: LinkPreviewView) -> CGSize {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        let h = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let size = CGSize(width: width, height: h)
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutIfNeeded()
        return size
    }

    func test_anchorOnly_light() {
        let v = LinkPreviewView()
        v.url = URL(string: "https://example.com/article")!
        v.anchorText = "Foobar"
        let size = fit(v)
        assertSnapshot(matching: v, as: .image(size: size, traits: traits(.light)))
    }

    func test_videoWithTitleAndThumb_dark() {
        let v = LinkPreviewView()
        v.url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        v.anchorText = "the song"
        v.title = "Rick Astley - Never Gonna Give You Up"
        v.isVideo = true
        v.thumbnailImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { ctx in
            UIColor.systemGray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let size = fit(v)
        assertSnapshot(matching: v, as: .image(size: size, traits: traits(.dark)))
    }
}
```

- [ ] **Step 2: Run to verify it fails (no reference yet)**

Run: `xcodebuild -project Spud.xcodeproj -scheme Spud -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/LinkPreviewViewSnapshotTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipPackagePluginValidation -skipMacroValidation test`
Expected: FAIL — compile error first (`anchorText`/`title`/`isVideo` undefined). After Step 3 it fails with "No reference was found" (records refs).

- [ ] **Step 3: Implement the enriched view**

Edit `Spud/Utils/Views/LinkPreviewView.swift`. Add the three properties near `url`:

```swift
    var anchorText: String? { didSet { textChanged() } }
    var title: String? { didSet { textChanged() } }
    var isVideo: Bool = false { didSet { playBadgeImageView.isHidden = !isVideo } }
```

Change `linkLabel` to allow two lines and add a primary label + a play badge. Replace the `linkLabel` declaration with a vertical text stack:

```swift
    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.isHidden = true
        return label
    }()

    lazy var linkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    lazy var textStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, linkLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }()

    lazy var playBadgeImageView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "play.circle.fill"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        return view
    }()
```

In the `stackView` builder, replace `linkLabel` in the `subviews` array with `textStackView`. After adding the thumbnail to the hierarchy, overlay the play badge on the thumbnail — in `init(frame:)`, after `addSubview(stackView)` add:

```swift
        thumbnailImageView.addSubview(playBadgeImageView)
        NSLayoutConstraint.activate([
            playBadgeImageView.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
            playBadgeImageView.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
            playBadgeImageView.widthAnchor.constraint(equalToConstant: 28),
            playBadgeImageView.heightAnchor.constraint(equalToConstant: 28),
        ])
```

Add a `textChanged()` that sets the primary/secondary lines, and have `urlChanged()` call it. Replace the body of `urlChanged()` to build only the host+path secondary string into a stored `hostPathString`, then call `textChanged()`:

```swift
    private func textChanged() {
        if let title, !title.isEmpty {
            titleLabel.isHidden = false
            titleLabel.text = title
        } else if let anchorText, !anchorText.isEmpty {
            titleLabel.isHidden = false
            titleLabel.text = anchorText
        } else {
            titleLabel.isHidden = true
        }

        // Secondary line: "anchor · host/path" when a title occupies the primary
        // line and we still have anchor text; otherwise just host/path.
        let host = hostPathString()
        if title != nil, let anchorText, !anchorText.isEmpty {
            linkLabel.attributedText = NSAttributedString(
                string: "\(anchorText) · \(host)",
                attributes: [.foregroundColor: UIColor.secondaryLabel]
            )
        } else {
            linkLabel.attributedText = hostPathAttributedString()
        }
    }
```

Extract the existing host/path attributed-string building into `hostPathAttributedString() -> NSAttributedString` (move the closure currently in `urlChanged()` there) and add `hostPathString() -> String { url?.canonicalHost.map { $0 + (url?.path ?? "") } ?? url?.absoluteString ?? "" }`. Make `urlChanged()` just call `textChanged()`.

Update `prepareForReuse()`:

```swift
    func prepareForReuse() {
        url = nil
        thumbnailImage = nil
        anchorText = nil
        title = nil
        isVideo = false
    }
```

- [ ] **Step 4: Record + verify the snapshots**

Run the Step 2 command twice (first records refs + fails, second verifies). Inspect the recorded PNGs to confirm: anchor-only shows "Foobar / example.com/article"; video shows the title + "the song · youtu.be" + a ▶ badge.

- [ ] **Step 5: Format, stage only these refs, commit**

```bash
mint run swiftformat Spud/Utils/Views/LinkPreviewView.swift SpudSnapshotTests/LinkPreviewViewSnapshotTests.swift
git add Spud/Utils/Views/LinkPreviewView.swift SpudSnapshotTests/LinkPreviewViewSnapshotTests.swift SpudSnapshotTests/__Snapshots__/LinkPreviewViewSnapshotTests/
git commit -m "feat: enrich LinkPreviewView with title, anchor text, and play badge"
```

---

### Task 7: Comment cell integration (DI + async enrich, preference-gated)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentViewModel.swift` (add `fetchLinkEmbeds: Bool`)
- Modify: `Spud/Scenes/PostDetail/Content/Comment/PostDetailCommentCell.swift` (`configure`, `configureLinkPreviews`)
- Modify: `Spud/Scenes/PostDetail/Content/PostDetailViewController.swift` (build VM with the flag; pass `linkEmbedService` to `configure`)
- Modify: the app dependency container that vends services to `PostDetailViewController` (register `LinkEmbedService`, expose `linkEmbedService` like `imageService`).

**Interfaces:**
- Consumes: `LinkEmbedServiceType` (Task 3), `LinkPreviewView.anchorText/title/isVideo` (Task 6), `CommentLinkPreview.anchorText/kind` (Task 5), `PreferencesService.fetchLinkEmbeds` (Task 4).

- [ ] **Step 1: Register `LinkEmbedService` in the dependency graph**

Find where `ImageService` is constructed and exposed (grep `ImageService(` and `var imageService` in `Spud/App/` and the dependency-composition protocols). Mirror it: instantiate one `LinkEmbedService()` in the same container, add a `HasLinkEmbedService` protocol (`var linkEmbedService: LinkEmbedServiceType { get }`), and conform the container. Add `LinkEmbedServiceType` to the composed `Dependencies` typealias that `PostDetailViewController` consumes (search `PostDetailViewController` for its `Dependencies` typealias / `HasImageService`).

- [ ] **Step 2: Add `fetchLinkEmbeds` to the comment view model**

In `PostDetailCommentViewModel.swift`, add a stored `let fetchLinkEmbeds: Bool` and set it from the preference where the VM is constructed. In `PostDetailViewController.swift` at the comment VM construction (~line 2232), pass `fetchLinkEmbeds: preferencesService.fetchLinkEmbeds`. (If the VM init is large, add the parameter with a default `false` and pass the real value at the call site.)

- [ ] **Step 3: Thread `linkEmbedService` into `configure`**

Change `PostDetailCommentCell.configure(with:imageService:)` (line 566) to also accept `linkEmbedService: LinkEmbedServiceType`, store it in a property, and update the call site in `PostDetailViewController.swift` (~line 2242) to pass it:

```swift
cell.configure(with: viewModel, imageService: imageService, linkEmbedService: linkEmbedService)
```

- [ ] **Step 4: Enrich cards in `configureLinkPreviews`**

Replace the `for preview in viewModel.linkPreviews` loop body (lines ~476-483) with anchor-text wiring + async enrich. Hold a per-configure token to ignore stale results across cell reuse (add `private var linkEmbedToken = UUID()`; set a fresh `UUID()` at the top of `configureLinkPreviews`). New loop body:

```swift
        let token = UUID()
        linkEmbedToken = token
        for preview in viewModel.linkPreviews {
            let view = LinkPreviewView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.url = preview.displayURL
            view.anchorText = preview.anchorText
            view.isVideo = preview.kind == .video
            let tapURL = preview.tapURL
            view.tapped = { [weak self] _ in self?.linkTapped?(tapURL) }
            view.addInteraction(UIContextMenuInteraction(delegate: self))
            linkPreviewTapURLs[ObjectIdentifier(view)] = tapURL
            linkPreviewsStackView.addArrangedSubview(view)

            guard viewModel.fetchLinkEmbeds, preview.kind == .video, let service = linkEmbedService else { continue }
            Task { [weak self, weak view] in
                guard let embed = await service.embed(for: preview.displayURL) else { return }
                guard let self, self.linkEmbedToken == token, let view else { return }
                if let title = embed.title { view.title = title }
                guard let thumbnailURL = embed.thumbnailURL else { return }
                for await state in self.imageService.fetch(thumbnailURL) {
                    guard self.linkEmbedToken == token else { return }
                    if case let .ready(image) = state { view.thumbnailImage = image }
                }
            }
        }
```

(`imageService` and `linkEmbedService` must be stored on the cell from `configure`. Reuse the existing `imageService` property if present; otherwise store it.)

- [ ] **Step 5: Build and run the comment tests**

Run: `python3 .../build_and_test.py --scheme Spud --simulator "iPhone 17 Pro"` then
`xcodebuild ... -only-testing:SpudTests/CommentLinkPreviewTests ... test`.
Expected: Build SUCCESS, tests green. Manual: open the reported comment (`https://sopuli.xyz/comment/24213735`); the YouTube/Invidious cards show anchor text immediately and fill in title + thumbnail; toggling "Load Link Previews" off shows only anchor text + host.

- [ ] **Step 6: Format and commit**

```bash
mint run swiftformat <the four modified files>
git add <the four modified files>
git commit -m "feat: enrich comment link cards with video thumbnail + title"
```

---

### Task 8: Post-header link card — show server title + thumbnail

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift` (HeaderImage.linkPreview gains `title`)
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift` (`.linkPreview` render case)

**Interfaces:**
- Consumes: `LinkPreviewView.title` (Task 6), `row.urlEmbedTitle`.

- [ ] **Step 1: Carry the title on the enum case**

In `PostDetailHeaderViewModel.swift`, change the enum case (line ~30):

```swift
        case linkPreview(url: URL, thumbnailUrl: URL?, title: String?)
```

and the mapping (line ~226):

```swift
        case let .externalLink(link):
            image = .linkPreview(url: link.url, thumbnailUrl: thumbnailUrlValue, title: row.urlEmbedTitle)
```

- [ ] **Step 2: Render the title in the header cell**

In `PostDetailHeaderCell.swift`, update the `.linkPreview` case (line ~653) to destructure `title` and set it:

```swift
        case let .linkPreview(url, thumbnailUrl, title):
            postImageContainer.isHidden = true
            linkPreviewView.isHidden = false
            linkPreviewView.url = url
            linkPreviewView.title = title
            // ... (existing thumbnail-fetch Task unchanged) ...
```

- [ ] **Step 3: Build + refresh header snapshots**

Run the app build, then the header snapshot class:
`xcodebuild ... -testPlan SpudSnapshots -only-testing:SpudSnapshotTests/PostDetailHeaderSnapshotTests ... test`.
The link-preview header snapshot now shows the server title; re-record that class (delete its PNGs, run to record, run to verify) per the git-annex one-class-at-a-time rule. Add a `communityTitle`/`urlEmbedTitle` value to the link fixture if the existing fixture has no embed title, so the title is visible.

- [ ] **Step 4: Format, stage refs, commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift
git add <the two files> SpudSnapshotTests/__Snapshots__/PostDetailHeaderSnapshotTests/
git commit -m "feat: show server-provided title on the post-header link card"
```

---

### Task 9: Post-body link previews (header cell)

**Files:**
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift` (build `linkPreviews` from `bodyBlocks`)
- Modify: `Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift` (add a `linkPreviewsStackView` below the body; reuse the comment cell's async-enrich logic)

**Interfaces:**
- Consumes: `[MarkdownBlock].commentLinkPreviews(limit:)` (Task 5), `LinkEmbedServiceType`, `PreferencesService.fetchLinkEmbeds`.

- [ ] **Step 1: Expose `linkPreviews` on the header VM**

In `PostDetailHeaderViewModel.swift`, after `bodyBlocks` is built, add:

```swift
    let linkPreviews: [CommentLinkPreview]
    let fetchLinkEmbeds: Bool
```

and set them in init: `linkPreviews = bodyBlocks.commentLinkPreviews(limit: 3)` and `fetchLinkEmbeds = <preference passed in>`. (Thread `fetchLinkEmbeds` into the VM init the same way Task 7 did for the comment VM; the header VM is built in `PostDetailViewController` ~line 2118 where `preferencesService` is available.)

- [ ] **Step 2: Extract the enrich loop into a shared helper (DRY), then reuse it**

The card-building + async-enrich loop is now needed by both the comment cell (Task 7) and the header cell. Extract it once to avoid duplication. Create `Spud/Utils/Views/LinkPreviewCardFactory.swift` with a single function that both cells call:

```swift
//
// Copyright (c) 2026, Denis Dzyubenko <denis@ddenis.info>
//
// SPDX-License-Identifier: BSD-2-Clause
//

import SpudDataKit
import UIKit

enum LinkPreviewCardFactory {
    /// Builds one `LinkPreviewView` per preview into `stack`, wires taps, and
    /// (when `fetchLinkEmbeds` and the link is a video) asynchronously fills in the
    /// title + thumbnail. `token`/`currentToken` guard against a slow fetch landing
    /// on a recycled cell — pass a fresh `UUID()` per configure and a closure
    /// returning the cell's current token.
    @MainActor
    static func populate(
        _ stack: UIStackView,
        previews: [CommentLinkPreview],
        fetchLinkEmbeds: Bool,
        imageService: ImageServiceType,
        linkEmbedService: LinkEmbedServiceType?,
        token: UUID,
        currentToken: @escaping () -> UUID,
        onTap: @escaping (URL) -> Void,
        registerContextMenu: (LinkPreviewView, URL) -> Void
    ) {
        for preview in previews {
            let view = LinkPreviewView()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.url = preview.displayURL
            view.anchorText = preview.anchorText
            view.isVideo = preview.kind == .video
            let tapURL = preview.tapURL
            view.tapped = { _ in onTap(tapURL) }
            registerContextMenu(view, tapURL)
            stack.addArrangedSubview(view)

            guard fetchLinkEmbeds, preview.kind == .video, let service = linkEmbedService else { continue }
            Task { [weak view] in
                guard let embed = await service.embed(for: preview.displayURL) else { return }
                guard currentToken() == token, let view else { return }
                if let title = embed.title { view.title = title }
                guard let thumbnailURL = embed.thumbnailURL else { return }
                for await state in imageService.fetch(thumbnailURL) {
                    guard currentToken() == token else { return }
                    if case let .ready(image) = state { view.thumbnailImage = image }
                }
            }
        }
    }
}
```

Refactor Task 7's `configureLinkPreviews` loop to call `LinkPreviewCardFactory.populate(...)` instead of its inline loop (keeping the `linkPreviewTapURLs[ObjectIdentifier(view)]` bookkeeping inside the `registerContextMenu`/`onTap` closures). Then in `PostDetailHeaderCell.swift`, add a vertical `linkPreviewsStackView` (mirror the comment cell's declaration) placed in the content stack right below the body view, and a `configureBodyLinkPreviews(_ viewModel:)` that calls the same `LinkPreviewCardFactory.populate(...)` with the header cell's `imageService` + injected `linkEmbedService`. Clear the stack on reuse.

- [ ] **Step 3: Thread `linkEmbedService` into the header cell's `configure`**

Add `linkEmbedService: LinkEmbedServiceType` to the header cell's `configure(...)` signature and pass it from the cell provider (`PostDetailViewController` ~line 2121), exactly as Task 7 did for the comment cell.

- [ ] **Step 4: Build + manual verify**

Run the app build. Manual: open a text post whose body contains a YouTube link; the card appears below the body with anchor text + (when the toggle is on) thumbnail + title.

- [ ] **Step 5: Format and commit**

```bash
mint run swiftformat Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderViewModel.swift Spud/Scenes/PostDetail/Content/Header/PostDetailHeaderCell.swift
git add <the two files>
git commit -m "feat: render enriched link previews under the post body"
```

---

### Task 10: Documentation

**Files:**
- Modify: `docs/features/post-detail-and-comments.md`
- Modify: `docs/features/external-link-handling.md` (the new preference)
- Modify: `docs/features/README.md` (coverage line)

- [ ] **Step 1: Document the behavior**

In `post-detail-and-comments.md`, add a "Behavior and rules" bullet: link cards in comment/post bodies show the link's anchor text; YouTube/Invidious/PeerTube links additionally show a thumbnail (with a play badge) + the video title when "Load link previews" is on; the post-header link card shows the server-provided title + thumbnail. Add a scenario. In `external-link-handling.md`, document the "Load Link Previews" toggle (default on; off keeps in-body previews local). Update the `README.md` post-detail coverage line.

- [ ] **Step 2: Commit**

```bash
git add docs/features/post-detail-and-comments.md docs/features/external-link-handling.md docs/features/README.md
git commit -m "docs: rich link previews + Load Link Previews preference"
```

---

## Notes for the implementer

- **Dependency direction:** `LinkEmbedService` lives in `SpudDataKit` and never reads the preference. The preference check happens in the app target (Tasks 7 & 9) before calling `embed(for:)`. Keep it that way.
- **Cell reuse:** the per-configure `UUID` token guards against a slow embed fetch landing on a recycled cell. Always re-check the token after each `await`.
- **Snapshots:** `LinkPreviewView` and header renders are device-sensitive `.image(size:)` snapshots — record on iPhone 17 Pro, one class at a time, and `git add` only the refs you recorded.
- **Graceful degradation:** every fetch failure must leave the card readable (anchor text + host). Never block the card on the network.
