# PieFed Phase 1 (Browse) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make Spud browse a native PieFed instance (`piefed.social`) for real — feeds, communities, posts, comments, search — by teaching LemmyKit to speak PieFed's `/api/alpha` API as a third dialect behind its existing neutral-DTO facade. Credential-free and fully verifiable.

**Architecture:** LemmyKit gains a `.piefed` `ApiVersion` dialect. Hand-written PieFed Codable models decode `/api/alpha` JSON via a transport-based `PiefedClient`; `neutralX(fromPiefed:)` adapters map them into the SAME neutral DTOs the v3/v4 adapters produce, so Spud consumes them unchanged. Spud picks the dialect from NodeInfo software detection and routes PieFed browse through it.

**Tech Stack:** Swift 6 (strict concurrency), swift-openapi-runtime `ClientTransport`, Swift Testing (LemmyKit + Spud unit tests). Two repos: **LemmyKit** (`/Users/denis/dev/info.ddenis/Spud/LemmyKit`, branch `feat/piefed-dialect`) and **Spud** (worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/piefed-integration`, branch `feat/piefed-integration`).

## Global Constraints

- **Design contract is authoritative:** `docs/superpowers/specs/2026-07-15-piefed-integration-design.md` (in the Spud worktree) holds the verified neutral-DTO target shapes, the field-rename table, and the Phase 0 findings. Adapters MUST produce the exact neutral DTOs listed there.
- **No emojis** anywhere. BSD-2-Clause 5-line header on every new file (copy from a sibling in the same repo).
- **Swift 6 strict concurrency**; all new types `Sendable`. LemmyKit is Swift 6 language mode.
- **PieFed field renames** (PieFed `/api/alpha` → Lemmy/neutral): `post.user_id→creatorId`, `post.title→name`, `post.sticky/instance_sticky→featuredCommunity/featuredLocal`, `comment.body→content`, `comment.user_id→creatorId`, `person.user_name→name`, `person.title→displayName`, `person.bot→botAccount`, `community.restricted_to_mods→postingRestrictedToMods`. Synthesize community `visibility` (absent→`._public`; `hidden==true`→`.unlisted`). Coalesce `banned_from_community: null→false`.
- **Bare-bool → sentinel:** PieFed sends bare `saved`/`read`/`hidden` bools and an `my_vote` Int score (like Lemmy v3), NOT v4 timestamps. Reuse the existing `v3ActionSentinel` (`Date(timeIntervalSince1970: 0)`) pattern when building `PostActions`/`CommentActions`/`CommunityActions`, exactly as `Adapters/PostViewV3Mapping.swift` does.
- **`.piefed` is exhaustive:** adding it to `ApiVersion` breaks all 38 neutral-endpoint switches. Read endpoints (this plan) get real implementations; every other endpoint throws `LemmyApiError.unsupportedByDialect` (new case) — no silent fallthrough, no `default:`.
- **PieFed error envelope** is `{"code","message","status"}` (not Lemmy's `{"error"}`). Decode it and surface via the existing `LemmyApiError.serverError(ErrorResponse)` by synthesizing `ErrorResponse(error: code-or-status, message: message)`.
- **LemmyKit tests:** `swift test` from `/Users/denis/dev/info.ddenis/Spud/LemmyKit` (the openapi-generator build plugin runs under SPM; if it needs `--disable-sandbox` or a trust prompt, resolve it and note how). Do not break the existing v3/v4 suite.
- **Spud paired-dev override (do NOT commit `project.yml`):** while iterating, Spud's `project.yml` LemmyKit pin is replaced with `path: /Users/denis/dev/info.ddenis/Spud/LemmyKit` (uncommitted), then a clean SPM resolve so the local path wins (`rm Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && xcodebuild -resolvePackageDependencies …`). Stage only code, never `project.yml`. Do NOT tag or release LemmyKit (unvalidated) — see [[dont-tag-unvalidated-releases]].
- **Conventional commits;** end messages with the two trailers (`Co-Authored-By:` + `Claude-Session:`).
- **Fixtures are live PieFed 1.7.5 JSON** captured 2026-07-15. Each LemmyKit task that needs them captures fresh from `https://piefed.social/api/alpha/…` (shapes are stable) into `LemmyKit/Tests/LemmyKitTests/Fixtures/piefed-*.json`. Use a browser User-Agent (PieFed may WAF non-browser UAs).

## File Structure

**LemmyKit (branch `feat/piefed-dialect`):**
- Create `Sources/LemmyKit/PieFed/PiefedEntities.swift` — `PiefedPost`, `PiefedPerson`, `PiefedCommunity`, `PiefedComment` + counts structs (Codable, Sendable).
- Create `Sources/LemmyKit/PieFed/PiefedViews.swift` — `PiefedPostView`, `PiefedCommentView`, `PiefedCommunityView`, `PiefedSiteView`, and response wrappers (`PiefedGetSiteResponse`, `PiefedGetPostsResponse`, `PiefedGetPostResponse`, `PiefedGetCommentsResponse`, `PiefedListCommunitiesResponse`, `PiefedGetCommunityResponse`, `PiefedSearchResponse`, `PiefedResolveObjectResponse`).
- Create `Sources/LemmyKit/PieFed/PiefedError.swift` — `PiefedErrorBody` decode + mapping to `ErrorResponse`.
- Create `Sources/LemmyKit/PieFed/PiefedClient.swift` — transport-based `/api/alpha` GET client.
- Create `Sources/LemmyKit/Adapters/PiefedMapping.swift` (or split per entity) — `neutralX(fromPiefed:)` functions.
- Modify `Sources/LemmyKit/Neutral/ApiVersion.swift` — add `.piefed`.
- Modify `Sources/LemmyKit/LemmyApiError.swift` — add `.unsupportedByDialect`.
- Modify `Sources/LemmyKit/LemmyApi.swift` — construct/hold a `PiefedClient` when `apiVersion == .piefed`.
- Modify the 38 `LemmyApi+*Neutral.swift` — add `.piefed` case (read = real, rest = throw).
- Create `Tests/LemmyKitTests/Piefed*Tests.swift` + `Tests/LemmyKitTests/Fixtures/piefed-*.json`.

**Spud (worktree, branch `feat/piefed-integration`):**
- Modify `SpudDataKit/Services/Account/AccountService.swift` — dialect from NodeInfo software.
- Modify wherever the browse `LemmyService`/`LemmyApi` is constructed to pass the resolved dialect.
- Modify `project.yml` (UNCOMMITTED local-path override).
- Create `docs/features/piefed.md` + README index (Task 7).

---

### Task 1: PieFed read models + decoding tests (LemmyKit)

**Repo/branch:** LemmyKit, `feat/piefed-dialect` (create it: `git -C /Users/denis/dev/info.ddenis/Spud/LemmyKit checkout -b feat/piefed-dialect main`).

**Files:**
- Create: `Sources/LemmyKit/PieFed/PiefedEntities.swift`, `PiefedViews.swift`, `PiefedError.swift`
- Create: `Tests/LemmyKitTests/Fixtures/piefed-{site,post_list,post_detail,comment_list,community_list,search}.json`
- Create: `Tests/LemmyKitTests/PiefedDecodingTests.swift`

**Interfaces produced:** `PiefedPostView`, `PiefedCommentView`, `PiefedCommunityView`, `PiefedSiteView`, `PiefedPost`, `PiefedPerson`, `PiefedCommunity`, `PiefedComment`, response wrappers, `PiefedErrorBody` — all `Codable, Sendable`, decoding PieFed `/api/alpha` JSON exactly.

- [ ] **Step 1: Capture fixtures.** From the LemmyKit dir, curl the live instance (browser UA) into `Tests/LemmyKitTests/Fixtures/`:
  - `piefed-site.json` ← `GET /api/alpha/site`
  - `piefed-post_list.json` ← `GET /api/alpha/post/list?type_=Local&limit=3&sort=New`
  - `piefed-post_detail.json` ← `GET /api/alpha/post?id=<a local post id from the list>`
  - `piefed-comment_list.json` ← `GET /api/alpha/comment/list?post_id=<a post id with comments>&sort=Hot&max_depth=8`
  - `piefed-community_list.json` ← `GET /api/alpha/community/list?type_=Local&limit=3&sort=Active`
  - `piefed-search.json` ← `GET /api/alpha/search?q=technology&type_=Communities&limit=3`
  Confirm each is HTTP 200 JSON. If `Bundle.module` fixtures need a `resources:` entry in `Package.swift` for the test target, verify the existing Fixtures dir is already bundled (the v3/v4 tests load `Fixtures/*.json` via `Bundle.module` — mirror that; no Package.swift change if the dir is already a resource).

- [ ] **Step 2: Write the failing decode test.** `PiefedDecodingTests.swift` (Swift Testing, `import Testing` + `import Foundation` + `@testable import LemmyKit`):

```swift
struct PiefedDecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        // PieFed publishes ISO-8601 with fractional seconds and a trailing 'Z' on some
        // fields and none on others; use the same lenient date strategy LemmyKit uses
        // for the v3/v4 clients (see LemmyDateTranscoder) or a custom decode.
        return d
    }

    @Test func decodesPostList() throws {
        let resp = try decoder.decode(PiefedGetPostsResponse.self, from: fixture("piefed-post_list"))
        let view = try #require(resp.posts.first)
        #expect(view.post.id > 0)
        #expect(!view.post.title.isEmpty)          // PieFed post title key is `title`
        #expect(view.post.user_id > 0)             // PieFed creator key is `user_id`
        #expect(view.creator.user_name.isEmpty == false)
        #expect(view.subscribed == "NotSubscribed" || view.subscribed == "Subscribed" || view.subscribed == "Pending")
    }
    @Test func decodesCommentList() throws {
        let resp = try decoder.decode(PiefedGetCommentsResponse.self, from: fixture("piefed-comment_list"))
        let view = try #require(resp.comments.first)
        #expect(!view.comment.body.isEmpty)        // PieFed comment content key is `body`
        #expect(view.comment.user_id > 0)
    }
    @Test func decodesCommunityList() throws {
        let resp = try decoder.decode(PiefedListCommunitiesResponse.self, from: fixture("piefed-community_list"))
        #expect(try #require(resp.communities.first).community.name.isEmpty == false)
    }
    @Test func decodesPostDetail() throws {
        let resp = try decoder.decode(PiefedGetPostResponse.self, from: fixture("piefed-post_detail"))
        #expect(resp.post_view.post.id > 0)
    }
    @Test func decodesSite() throws {
        let resp = try decoder.decode(PiefedGetSiteResponse.self, from: fixture("piefed-site"))
        #expect(resp.version.isEmpty == false)
    }
    @Test func decodesSearch() throws {
        let resp = try decoder.decode(PiefedSearchResponse.self, from: fixture("piefed-search"))
        #expect(resp.communities.isEmpty == false || resp.posts.isEmpty == false)
    }
    @Test func decodesErrorEnvelope() throws {
        let data = Data(#"{"code":400,"message":"incorrect_login","status":"Bad Request"}"#.utf8)
        let err = try decoder.decode(PiefedErrorBody.self, from: data)
        #expect(err.message == "incorrect_login")
    }
}
```

- [ ] **Step 3: Run it, confirm it fails** (types undefined): `cd /Users/denis/dev/info.ddenis/Spud/LemmyKit && swift test --filter PiefedDecodingTests` → FAIL.

- [ ] **Step 4: Define the models to match the fixtures.** In `PiefedEntities.swift` / `PiefedViews.swift`, define `Codable, Sendable` structs whose stored properties EXACTLY match the fixture JSON keys (use the raw PieFed key names — `user_id`, `title`, `body`, `user_name`, `restricted_to_mods`, etc. — the adapters do the renaming). Make fields that are absent in some views (e.g. `creator_blocked`, `body`, `url`, `thumbnail_url`, `updated`, `banner`) OPTIONAL. Make `banned_from_community` optional (`Bool?`) since community list sends `null`. Skeleton for the two central types (COMPLETE the rest against the fixtures — the decode test is the spec):

```swift
public struct PiefedPost: Codable, Sendable {
    public let id: Int64
    public let user_id: Int64
    public let community_id: Int64
    public let title: String
    public let body: String?
    public let url: String?
    public let thumbnail_url: String?
    public let small_thumbnail_url: String?
    public let ap_id: String
    public let local: Bool
    public let nsfw: Bool
    public let removed: Bool
    public let deleted: Bool
    public let locked: Bool
    public let sticky: Bool
    public let instance_sticky: Bool
    public let language_id: Int64
    public let published: String            // decode to Date in the adapter or via a Date-tolerant decoder
    public let post_type: String?
    public let ai_generated: Bool?
    // native extras (decoded but unused by the neutral adapter): emoji_reactions, cross_posts, tags, flair
}

public struct PiefedPostView: Codable, Sendable {
    public let post: PiefedPost
    public let creator: PiefedPerson
    public let community: PiefedCommunity
    public let counts: PiefedPostCounts
    public let subscribed: String           // "NotSubscribed" | "Subscribed" | "Pending"
    public let saved: Bool
    public let read: Bool
    public let hidden: Bool
    public let my_vote: Int
    public let creator_banned_from_community: Bool
    public let creator_is_moderator: Bool
    public let creator_is_admin: Bool
    public let banned_from_community: Bool?
    public let unread_comments: Int64
    public let creator_blocked: Bool?
}
```

Decide the Date handling: either keep `published`/`updated` as `String` and parse in the adapter (Task 4) with a tolerant ISO-8601 parser, OR give the decoder a date strategy. Prefer parsing in the adapter (keeps models pure strings, avoids decoder global state). Provide a small `piefedDate(_ s: String?) -> Date?` helper (fractional-seconds ISO-8601, tolerate trailing `Z` and its absence).

- [ ] **Step 5: Run tests green.** `swift test --filter PiefedDecodingTests` → PASS. Also run the full `swift test` to confirm nothing else broke.

- [ ] **Step 6: Commit** (LemmyKit repo): `feat: add PieFed /api/alpha read response models`

---

### Task 2: `PiefedClient` — transport-based `/api/alpha` reads (LemmyKit)

**Files:**
- Create: `Sources/LemmyKit/PieFed/PiefedClient.swift`
- Modify: `Sources/LemmyKit/LemmyApiError.swift` (add `.unsupportedByDialect`), `Sources/LemmyKit/PieFed/PiefedError.swift`
- Create: `Tests/LemmyKitTests/PiefedClientTests.swift`

**Interfaces produced:** `struct PiefedClient: Sendable` with `init(baseURL: URL, token: String?, transport: any ClientTransport, userAgent: String)` and async read methods returning the Task-1 response models, throwing `LemmyApiError`; `LemmyApiError.unsupportedByDialect(operation: String)`.

- [ ] **Step 1: Write the failing test.** Model the stub transport on `Tests/LemmyKitTests/GetPostNeutralTests.swift`'s `StubTransport` (a `ClientTransport` returning canned bytes) and `PathCapturingStubTransport` (records `request.path`). Test that `PiefedClient.getPosts(...)` (a) issues `GET /api/alpha/post/list` with the expected query params (`type_`, `sort`, `limit`, `page`/`page_cursor`), (b) adds `Authorization: Bearer <token>` when a token is set, and (c) decodes the canned `piefed-post_list.json` body into `PiefedGetPostsResponse`. Also test that a non-2xx body `{"code":400,"message":"x","status":"Bad Request"}` throws `LemmyApiError.serverError` with `error == "400"`-or-`"x"`.

- [ ] **Step 2: Run, confirm fail.**

- [ ] **Step 3: Implement `PiefedClient`.** It uses the injected `ClientTransport` directly (no generated Client). For each read op, build an `HTTPRequest` (method `.get`, path `/api/alpha/<route>?<query>`), inject the bearer header if `token != nil`, `try await transport.send(request, body: nil, baseURL: baseURL, operationID: "<op>")`, collect the response body bytes, and on 2xx `JSONDecode` into the model, else decode `PiefedErrorBody` → throw `.serverError(ErrorResponse(error: body.code.map(String.init) ?? body.status, message: body.message))` (or `.unknownServerError` if the error body doesn't decode). Methods: `getSite()`, `getPosts(type_:sort:communityId:showNsfw:limit:page:)`, `getPost(id:)`, `getComments(postId:parentId:sort:maxDepth:)`, `getCommunity(id:)`, `listCommunities(type_:sort:limit:page:)`, `search(q:type_:sort:limit:page:)`, `resolveObject(q:)`. Use `URLComponents`/manual query building; percent-encode. Reference how `AuthorizationMiddleware` sets the bearer field (`HTTPField(name: .authorization, value: "Bearer \(token)")`) — do the same on the request directly.

Pagination note: PieFed uses `page` (integer) for `post/list`/`community/list` and returns `next_page` (a cursor string) in some responses. Match what the fixtures show: `comment_list` returned `next_page`; `post/list` — check whether it returns `next_page` or expects `page=N`. Implement to what the live API accepts (confirm by probing `?page=2`). Expose the raw `next_page` (if present) on the response models so the adapter can build a neutral `Cursor`.

- [ ] **Step 4: Green.** `swift test --filter PiefedClientTests` + full `swift test`.
- [ ] **Step 5: Commit:** `feat: add transport-based PiefedClient for /api/alpha reads`

---

### Task 3: `ApiVersion.piefed` + exhaustive-switch handling (LemmyKit)

**Files:**
- Modify: `Sources/LemmyKit/Neutral/ApiVersion.swift` (add `.piefed`), `Sources/LemmyKit/LemmyApi.swift` (hold a `PiefedClient?`, build it when `apiVersion == .piefed`)
- Modify: all 38 `Sources/LemmyKit/LemmyApi+*Neutral.swift` — add a `.piefed` case to each `switch apiVersion`
- Modify: `Tests/LemmyKitTests/ApiVersionProbeTests.swift` or add `PiefedDialectStubTests.swift`

**Interfaces produced:** `ApiVersion.piefed`; `LemmyApi` builds a `PiefedClient` from `instanceUrl` + credential + transport when `apiVersion == .piefed`; every write/unsupported neutral endpoint throws `LemmyApiError.unsupportedByDialect(operation:)` for `.piefed`.

- [ ] **Step 1: Add the enum case + doc.** `case piefed` in `ApiVersion` with a `///` note: PieFed's `/api/alpha` API, Lemmy-shaped at the view level, mapped via `PiefedClient` + `*PiefedMapping` adapters.

- [ ] **Step 2: Build the PiefedClient in `LemmyApi`.** Where `client`/`v4Client` are constructed (`LemmyApi.swift:73-84` and the test init at `:101`), add `let piefedClient: PiefedClient?` set to a `PiefedClient(baseURL: instanceUrl, token: credential?.jwt, transport: transport, userAgent: userAgent)` when `apiVersion == .piefed`, else `nil`. (The v3/v4 clients can still be built or made lazy — simplest: keep building them; they're unused for `.piefed`.)

- [ ] **Step 3: Add `.unsupportedByDialect`.** In `LemmyApiError`, add `case unsupportedByDialect(operation: String)`.

- [ ] **Step 4: Make every neutral endpoint compile for `.piefed`.** In each of the 38 `LemmyApi+*Neutral.swift`, add `case .piefed:` to the `switch apiVersion`. For THIS task, make ALL of them `throw LemmyApiError.unsupportedByDialect(operation: "<methodName>")` (a one-liner per file). Task 5 replaces the read ones with real calls. This keeps the build green and the existing v3/v4 tests passing while `.piefed` is a hard "not yet" for everything.

- [ ] **Step 5: Test.** Add a test: build `LemmyApi(instanceUrl:credential:nil, transport: <stub>, apiVersion: .piefed)` and assert a write endpoint (e.g. `votePostNeutral`) throws `.unsupportedByDialect`. Confirm the full existing `swift test` suite still passes (v3/v4 unaffected).

- [ ] **Step 6: Commit:** `feat: add .piefed ApiVersion dialect (endpoints gated unsupported)`

---

### Task 4: PieFed → neutral adapters (LemmyKit)

**Files:**
- Create: `Sources/LemmyKit/Adapters/PiefedMapping.swift` (or split: `PostViewPiefedMapping.swift`, `CommentViewPiefedMapping.swift`, `CommunityPiefedMapping.swift`, `SitePiefedMapping.swift`, `PersonPiefedMapping.swift`, `SearchResultsPiefedMapping.swift` — prefer small files, mirroring the `*V3Mapping.swift` layout)
- Create: `Tests/LemmyKitTests/PiefedMappingTests.swift`

**Interfaces produced:** free functions in the `LemmyKit` module producing the exact neutral DTOs (per design-doc contract §1): `neutralPost(fromPiefed:)`, `neutralPostView(fromPiefed:)`, `neutralComment(fromPiefed:)`, `neutralCommentView(fromPiefed:)`, `neutralCommunity(fromPiefed:)`, `neutralCommunityView(fromPiefed:)`, `neutralPerson(fromPiefed:)`, `neutralPersonView(fromPiefed:)`, `neutralSite(fromPiefed:)`, `neutralSiteInfo(fromPiefed:)`, `neutralSearchResults(fromPiefed:)`, `neutralResolvedObject(fromPiefed:)`, `neutralFollowState(fromPiefedSubscribed:)`, `neutralPage(fromPiefed:nextPage:mapItem:)`.

- [ ] **Step 1: Write failing adapter tests.** Pure functions, no transport. Decode each Task-1 fixture into the PieFed model, run the adapter, assert the neutral output. Critically assert the RENAMES resolve correctly:

```swift
struct PiefedMappingTests {
    @Test func postViewMapsRenamedFields() throws {
        let resp = try decode(PiefedGetPostsResponse.self, "piefed-post_list")
        let n = neutralPostView(fromPiefed: try #require(resp.posts.first))
        #expect(n.post.name.isEmpty == false)            // PieFed post.title -> neutral post.name
        #expect(n.post.creatorId == /* fixture user_id */)
        #expect(n.creator.name.isEmpty == false)         // PieFed creator.user_name -> neutral person.name
        #expect(n.community.postingRestrictedToMods == /* fixture restricted_to_mods */)
        // subscribed "NotSubscribed" -> .notFollowing ; my_vote 0 -> .none
        #expect(n.followState == .notFollowing)
        #expect(n.myVote == .none)
    }
    @Test func communityVisibilitySynthesized() throws {
        // hidden==false, no visibility field -> ._public ; hidden==true -> .unlisted
    }
    @Test func commentBodyMapsToContent() throws { /* PieFed comment.body -> neutral comment.content */ }
    @Test func bannedFromCommunityNullCoalescesToFalse() throws { /* community_list banned_from_community: null -> false */ }
}
```

- [ ] **Step 2: Run, confirm fail.**

- [ ] **Step 3: Implement the adapters.** Mirror `Adapters/PostViewV3Mapping.swift` structure exactly, reading PieFed field names. Reference the design-doc contract for every neutral field. Key ones:

```swift
func neutralPost(fromPiefed p: PiefedPost, counts c: PiefedPostCounts) -> Post {
    Post(
        id: p.id, name: p.title, body: p.body, url: p.url,
        embedTitle: nil, embedDescription: nil, thumbnailUrl: p.thumbnail_url,
        altText: nil, imageWidth: nil, imageHeight: nil,
        creatorId: p.user_id, communityId: p.community_id, apId: p.ap_id,
        local: p.local, nsfw: p.nsfw, removed: p.removed, deleted: p.deleted, locked: p.locked,
        featuredCommunity: p.sticky, featuredLocal: p.instance_sticky,
        languageId: p.language_id,
        publishedAt: piefedDate(p.published) ?? Date(timeIntervalSince1970: 0),
        updatedAt: nil, newestCommentTimeAt: piefedDate(c.newest_comment_time),
        score: c.score, upvotes: c.upvotes, downvotes: c.downvotes, comments: c.comments)
}

package func neutralPostView(fromPiefed v: PiefedPostView) -> PostView {
    let post = neutralPost(fromPiefed: v.post, counts: v.counts)
    let voteScore = v.my_vote
    return PostView(
        post: post,
        creator: neutralPerson(fromPiefed: v.creator),
        community: neutralCommunity(fromPiefed: v.community),
        creatorBannedFromCommunity: v.creator_banned_from_community,
        creatorIsModerator: v.creator_is_moderator,
        creatorIsAdmin: v.creator_is_admin,
        creatorBanned: v.banned_from_community ?? false,
        canMod: false,
        postActions: PostActions(
            readAt: v.read ? v3ActionSentinel : nil,
            hiddenAt: v.hidden ? v3ActionSentinel : nil,
            savedAt: v.saved ? v3ActionSentinel : nil,
            votedAt: voteScore != 0 ? v3ActionSentinel : nil,
            voteIsUpvote: voteScore == 0 ? nil : voteScore > 0,
            readCommentsAt: nil,
            readCommentsAmount: max(0, post.comments - v.unread_comments)),
        communityActions: CommunityActions(followState: neutralFollowState(fromPiefedSubscribed: v.subscribed)),
        personActions: PersonActions(blockedAt: (v.creator_blocked ?? false) ? v3ActionSentinel : nil))
}

func neutralFollowState(fromPiefedSubscribed s: String) -> FollowState {
    switch s { case "Subscribed": .accepted; case "Pending": .pending; default: .notFollowing }
}

func neutralCommunity(fromPiefed c: PiefedCommunity) -> Community {
    Community(
        id: c.id, name: c.name, title: c.title, sidebar: c.description, apId: c.actor_id,
        iconUrl: c.icon, bannerUrl: c.banner,
        visibility: c.hidden ? .unlisted : ._public,
        local: c.local, nsfw: c.nsfw, postingRestrictedToMods: c.restricted_to_mods,
        removed: c.removed, deleted: c.deleted,
        publishedAt: piefedDate(c.published) ?? Date(timeIntervalSince1970: 0),
        updatedAt: piefedDate(c.updated),
        subscribers: /* c.counts if a counted variant */ 0, posts: 0, comments: 0)
}
```

Implement the remaining (`neutralPerson`: `user_name→name`, `title→displayName`, `bot→botAccount`, `avatar→avatarUrl`, `actor_id→apId`; `neutralComment`: `body→content`, `user_id→creatorId`, `path`, counts; `neutralCommentView`; `neutralCommunityView` from the community-list wrapper WITH counts for subscribers/posts/comments; `neutralSite`/`neutralSiteInfo` from `piefed-site.json` — inspect its exact shape; `neutralSearchResults`: PieFed `users→persons`; `neutralResolvedObject`; `neutralPage` building a `Cursor` from PieFed `next_page`). Where PieFed provides community counts (community-list `counts`), populate `subscribers/posts/comments`; where only a bare community is embedded (in a post view), leave them 0 — same as the v3 adapter's two overloads.

- [ ] **Step 4: Green.** `swift test --filter PiefedMappingTests` + full `swift test`.
- [ ] **Step 5: Commit:** `feat: add PieFed -> neutral DTO adapters`

---

### Task 5: Wire the read endpoints' `.piefed` dispatch (LemmyKit)

**Files:**
- Modify the 8 read `LemmyApi+*Neutral.swift`: `GetSiteNeutral`, `GetPostsNeutral`, `GetPostNeutral`, `GetCommentsNeutral`, `GetCommunityNeutral`, `ListCommunitiesNeutral`, `SearchNeutral`, `ResolveObjectNeutral`
- Create: `Tests/LemmyKitTests/PiefedNeutralEndpointTests.swift`

**Interfaces produced:** the 8 neutral read methods return correct neutral DTOs for `.piefed` (replacing the Task-3 `unsupportedByDialect` throw), via `piefedClient` + Task-4 adapters.

- [ ] **Step 1: Write failing endpoint tests.** Mirror `GetPostNeutralTests.swift`'s three-legged pattern: build `LemmyApi(instanceUrl:credential:nil, transport: <StubTransport returning piefed-*.json>, apiVersion: .piefed)`, call each neutral read method, assert the neutral DTO. e.g. `getPostsNeutral(listingType:.Local, sort:.new)` → `Page<PostView>` whose first item's `post.name` matches the fixture title; `getCommentsNeutral(postId:)` → `Page<CommentView>`; `getSiteNeutral()` → `SiteInfo` with the fixture version; `searchNeutral(query:type:.communities)` → `SearchResults`. The stub transport must route by request path (`/api/alpha/post/list` → post_list fixture, etc.) — extend the existing path-routing stub pattern.

- [ ] **Step 2: Run, confirm fail** (they currently throw `unsupportedByDialect`).

- [ ] **Step 3: Implement each `.piefed` case.** In each of the 8 files, replace `throw .unsupportedByDialect` with a `…Piefed` helper that calls `piefedClient` (force-unwrap is safe — only reachable when `apiVersion == .piefed`, which guarantees a non-nil client; still guard and throw `unsupportedByDialect` if somehow nil) and maps via Task-4 adapters. Match the existing neutral method's signature/return exactly. Map neutral params → PieFed query: `ListingType` (`.All/.Local/.Subscribed`) → `type_`; `PostSort` → PieFed `sort` string via a small `piefedSort(_:)` (Active/Hot/New/Old/TopDay/… — PieFed uses the same wire strings as Lemmy v3, so reuse/adapt `SortMapping`); `Cursor` → `page`/`page_cursor` per what PiefedClient accepts. Example (`GetPostsNeutral.swift`):

```swift
case .piefed:
    try await getPostsNeutralPiefed(listingType: listingType, sort: sort,
        communityId: communityId, timeRange: timeRange, showNsfw: showNsfw, pageCursor: pageCursor)
// ...
private func getPostsNeutralPiefed(...) async throws -> Page<PostView> {
    guard let piefedClient else { throw LemmyApiError.unsupportedByDialect(operation: "getPosts") }
    let resp = try await piefedClient.getPosts(type_: listingType.rawValue, sort: piefedSort(sort),
        communityId: communityId, showNsfw: showNsfw, limit: nil, page: pageCursor?.rawValue)
    return neutralPage(fromPiefed: resp.posts, nextPage: resp.next_page) { neutralPostView(fromPiefed: $0) }
}
```

- [ ] **Step 4: Green.** `swift test --filter PiefedNeutralEndpointTests` + full `swift test` (existing v3/v4 unaffected). Confirm test output pristine.
- [ ] **Step 5: Commit:** `feat: implement PieFed read endpoints through the neutral facade`. Then push the LemmyKit branch? NO — leave it local/unpushed (unvalidated). Spud consumes it via local path.

---

### Task 6: Spud — select the PieFed dialect + route browse (Spud worktree)

**Repo/branch:** Spud worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/piefed-integration`, `feat/piefed-integration`.

**Files:**
- Modify (UNCOMMITTED): `project.yml` — LemmyKit local-path override
- Modify: `SpudDataKit/Services/Account/AccountService.swift` — `resolvedApiVersion` consults software
- Modify: whatever builds the browse `LemmyService` (trace from `lemmyService(forAccountKeychainId:)`)
- Test: `SpudDataKitTests/NodeInfo/…` dialect-selection test

**Interfaces consumed:** `LemmyKit.ApiVersion.piefed`, `InstanceSoftware.piefed`, the NodeInfo cache.

- [ ] **Step 1: Local-path override + resolve.** Replace the `LemmyKit` pin block in `project.yml` (`revision: …`) with:
  ```yaml
    LemmyKit:
      path: /Users/denis/dev/info.ddenis/Spud/LemmyKit
  ```
  Then `make project`, `rm -f Spud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, and `xcodebuild -resolvePackageDependencies -project Spud.xcodeproj -skipPackagePluginValidation -skipMacroValidation` — confirm it resolves `LemmyKit: <local path>`. Leave `project.yml` UNCOMMITTED. Build once (`make build`) to confirm Spud compiles against the dev LemmyKit with `.piefed`.

- [ ] **Step 2: Failing test for dialect selection.** In SpudDataKitTests, seed an in-memory DB with an account whose host has a `NodeInfoCacheRecord` software `piefed`, and assert `AccountService.resolvedApiVersion(forKeychainId:)` (or a renamed `resolvedDialect`) returns `.piefed`; a Lemmy host still returns `.v3`/`.v4` by version. (Confirm `NodeInfoCacheRecord` exposes a sync read of software-by-host; if not, add one.)

- [ ] **Step 3: Implement.** `resolvedApiVersion(forKeychainId:)` (`AccountService.swift:654`) first checks the account host's detected software via the NodeInfo cache: if `.piefed` → return `.piefed`; else fall through to the existing Lemmy version→v3/v4 logic. Ensure the PieFed version string (`1.7.5`) is NOT parsed on the Lemmy scale. Also fix `instanceCapabilities(forAccountKeychainId:)` (`AccountService.swift:391`) to pass the account's real software (so a PieFed account doesn't inherit `.lemmy`), though the capability gap-set itself is Phase 2 — for Phase 1 it can stay `.allAvailable` (browse doesn't gate).

- [ ] **Step 4: Ensure browse knows it's PieFed.** For the Phase-1 browse validation path (opening a PieFed instance), confirm NodeInfo has detected `.piefed` for the host BEFORE the browse `LemmyService` is built, so `resolvedApiVersion` sees it. Trace the browse-account/`LemmyService` construction; if the browse entry point doesn't already run NodeInfo detection for the target host, add a detection call on that path (the instance-detail screen already probes NodeInfo — prefer validating through that entry point). Do not change the login block in this task (that's Phase 2).

- [ ] **Step 5: Build + test.** `make project && make build && make test-only ONLY=SpudDataKitTests`.
- [ ] **Step 6: Commit** (code only, NOT `project.yml`): `feat: route PieFed instances through the .piefed LemmyKit dialect`

---

### Task 7: Live browse validation + docs (Spud worktree)

**Files:**
- Create: `docs/features/piefed.md`; Modify: `docs/features/README.md`

- [ ] **Step 1: Validate against the live instance.** With the local-path LemmyKit + a booted simulator, drive Spud to browse `piefed.social` (via the instance-detail/Explore path or the DEBUG typed-host seam). Confirm real PieFed feeds, communities, a post's comments, and search results render in Spud — decoded through the neutral DTOs. Capture a screenshot per the "verify tap-gated UI" pattern (temporary `#if DEBUG` launch-arg auto-navigation + `simctl screenshot`, then revert). This is the Phase-1 exit gate: a genuine PieFed browse, not a unit test.

- [ ] **Step 2: Record findings.** Note any endpoint that failed to decode/render against the LIVE instance (vs the captured fixture) — live data has edge cases fixtures miss (empty bodies, unusual post types, deleted authors). File each as a small adapter fix (loop back to Task 4/5 as needed). Phase 1 is done when the four browse surfaces render cleanly on live data.

- [ ] **Step 3: Docs.** Write `docs/features/piefed.md` (honest Status: browse-only shipped; login/interactions = Phase 2, not yet): what works (browse PieFed instances), what doesn't yet (login, vote, comment, post — coming), and the "PieFed is detected and browsable" behavior. Update the README capability table + by-area map. No `.swift` links; link the design doc.
- [ ] **Step 4: Commit:** `docs: document PieFed browse support (Phase 1)`

---

## Final verification (Phase 1)

- [ ] LemmyKit: full `swift test` green (existing v3/v4 + all new PieFed suites).
- [ ] Spud: `make build` + `make test-only ONLY=SpudDataKitTests` green against the local-path LemmyKit.
- [ ] LIVE: Spud browses `piefed.social` — feeds, a community, a post + comments, search — rendering through the neutral DTOs. Screenshot captured.
- [ ] Whole-branch review (LemmyKit diff + Spud diff) before considering Phase 1 complete.
- [ ] `project.yml` override remains UNCOMMITTED; LemmyKit branch remains local/unpushed/untagged (unvalidated). Committed-pin bump is deferred to end-of-initiative (post human validation), per the workspace CLAUDE.md.

## Coverage vs design
- Dialect in LemmyKit (not Spud, not FediverseKit) → Tasks 1–5.
- `/api/alpha` + entity renames + error envelope → Tasks 1, 2, 4.
- Neutral-DTO equivalence → Tasks 4, 5 (fixture → neutral, mirroring v3/v4 tests).
- Spud dialect-from-NodeInfo + browse → Task 6; live validation → Task 7.
- Write/auth endpoints explicitly gated `unsupportedByDialect` (Phase 2) → Task 3.
