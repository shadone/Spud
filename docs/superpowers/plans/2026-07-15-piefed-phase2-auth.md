# PieFed Phase 2 (Auth + Interactions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make a PieFed account first-class in Spud — log in, vote, save, subscribe, comment, post, mark-read, inbox, DMs, person profiles — by implementing PieFed's `/api/alpha` auth + write surface in LemmyKit's `.piefed` dialect and unblocking/wiring the Spud side, with honest capability gating for the residual gaps.

**Architecture:** Extend the existing Phase-1 dialect: `PiefedClient` gains a JSON-body POST/PUT engine beside its GET engine; new wire models decode the write/auth responses (mostly the same `{post_view}`/`{comment_view}` shapes already modeled); the gated `LemmyApi+*Neutral.swift` `.piefed` arms get real implementations mapped through the existing `neutralX(fromPiefed:)` adapters plus a handful of new ones (my-user, notifications, DMs, person). Spud unblocks PieFed as a home connection (login allowed, register still routed to the web), resolves the login-time `ApiVersion` from NodeInfo, seeds the real PieFed capability gap set, and integrates PieFed auth failures with the existing session-reauth machinery.

**Tech Stack:** Swift 6 (strict concurrency), swift-openapi-runtime `ClientTransport` + `HTTPTypes`, Swift Testing. Two repos: **LemmyKit** (`/Users/denis/dev/info.ddenis/Spud/LemmyKit`, branch `feat/piefed-dialect`, HEAD `98d13ec`) and **Spud** (worktree `/Users/denis/dev/info.ddenis/Spud/Spud/.claude/worktrees/piefed-integration`, branch `feat/piefed-integration`, HEAD `700ab52b`).

## Global Constraints

- **Empirical ground truth:** `.superpowers/sdd/phase2-api-probe.md` (live-verified routes/shapes, 2026-07-15, PieFed 1.7.5) and the vendored OpenAPI spec `.superpowers/sdd/piefed-alpha-spec.json` (108 paths, from `/api/alpha/swagger.json`). The probe outranks the spec where they disagree (the spec's `DefaultError` shape is wrong; some live stubs are absent from it). Both files live in the Spud worktree.
- **Validation instance:** `https://piefed1.lemmy.ddenis.info` (user's self-hosted PieFed 1.7.5). Live write tests and fixture captures go ONLY there — never piefed.social. Test account creds: `/Users/denis/dev/info.ddenis/Spud/test-instances.md` § "PieFed (Phase 2 auth)". **Secret discipline (non-negotiable):** read creds with shell into variables in the same command that uses them; never echo the password or any JWT into chat, reports, fixtures, commits, or screenshots; captured fixtures must be grepped for `eyJ`-prefixed strings and the literal password before staging; the login-response fixture is SYNTHESIZED, never captured.
- **Restore state after live writes** (votes → 0, saves/follows undone, test content deleted) — the probe's cleanup discipline.
- **Do not break Lemmy:** v3/v4 arms and all existing tests stay untouched and green (LemmyKit full `swift test`; Spud `make test-only ONLY=SpudDataKitTests`). Do not break Phase-1 signed-out PieFed browse.
- **PieFed error envelope tolerance:** live errors come in THREE shapes — `{"code":Int,"message":String,"status":String}`, `{"message":String}`, `{"error":"not_yet_implemented"}`. Decode all three. **Semantic token goes in `ErrorResponse.error`:** Spud classifiers (`AuthExpiry.authCodes`, `AccountServiceLoginError`, `ContentNotFound`) match semantic strings (e.g. `incorrect_login`, `not_logged_in`) on `ErrorResponse.error` — PieFed carries that token in its `message` field, so the mapping is `ErrorResponse(error: <semantic message/error token>, message: <human-readable or same>)`. (This REVERSES the Phase-1 mapping which put the stringified numeric code in `.error` — Task 2 changes it and updates the Phase-1 test.)
- **Route/method table is the probe's** (§ Summary): vote = `POST post/like` / `comment/like` (`score` −1/0/1); save = **PUT** `post/save` / `comment/save` (`{*_id, save}`); membership follow = `POST community/follow` (`{community_id, follow}`) — **NEVER** `PUT community/subscribe` (that is the separate activity-alert feature); mark post read = `POST post/mark_as_read` (`{post_id, read}` → `{success}`); comment/post create = POST + edit = PUT on `/comment` / `/post`, delete = `POST comment/delete` / `post/delete` (`{*_id, deleted}`); login = `POST user/login` (`{username, password}` → `{jwt}`, **username not email, no 2FA field**); my-user = `GET /site` authed (`my_user` embed) and `GET user/me`; unread = `GET user/unread_count` (`{mentions, other, private_messages, replies}`); inbox = Lemmy-compat `GET user/replies` / `user/mentions` (wrapper `{replies, next_page}`) + `POST user/mark_all_as_read`; single reply mark-read = `POST comment/mark_as_read` (`{comment_reply_id, read}`); DMs = `GET private_message/list` (`{private_messages}`), `POST private_message` (`{content, recipient_id}`), `POST private_message/mark_as_read`; hide = `POST post/hide`.
- **PieFed field renames** (write-side mirrors read-side): person `user_name`/`title`; comment body = `body` (neutral `content`); DM body = `content` (matches neutral); `subscribed` = string enum `NotSubscribed|Subscribed|Pending`.
- **Stays gated in Phase 2** (documented, not wired): register (web-only confirmed — doubled path + Closed), password change/reset (live stubs), saveUserSettings + avatar/banner (server settings push), image upload (multipart), block person/community, account feeds (saved/read/hidden/liked lists). PieFed-native extras (emoji reactions, private votes, activity-alert subscribe, feeds/topics, polls/events) are Phase 3.
- **Spud paired-dev:** `project.yml` keeps the UNCOMMITTED local-path LemmyKit override (already in place). Stage only code, never `project.yml`, never the cosmetic annex-`M` snapshot PNGs. LemmyKit stays local/unpushed/untagged ([[dont-tag-unvalidated-releases]]); the committed pin bump is the LAST step of the whole initiative, post human validation.
- **No emojis.** BSD-2-Clause 5-line header on every new file (copy a sibling's). Swift 6 strict concurrency; new types `Sendable`. Conventional commits ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **In the Spud worktree, use WORKTREE-rooted paths only** — never the main checkout `/Users/denis/dev/info.ddenis/Spud/Spud/…`.

## File Structure

**LemmyKit (branch `feat/piefed-dialect`):**
- Create `Sources/LemmyKit/PieFed/PiefedAuthEntities.swift` — login/my-user/local-user wire models.
- Create `Sources/LemmyKit/PieFed/PiefedWriteResponses.swift` — `{post_view}`/`{comment_view}`/`{success}` write-response wrappers.
- Create `Sources/LemmyKit/PieFed/PiefedInboxEntities.swift` — replies/mentions item + wrapper, unread counts, private-message models.
- Modify `Sources/LemmyKit/PieFed/PiefedClient.swift` — JSON-body POST/PUT engine + the write/auth methods; 3-envelope error decode; semantic-token error mapping.
- Modify `Sources/LemmyKit/PieFed/PiefedError.swift` — tolerant 3-shape error body.
- Create `Sources/LemmyKit/Adapters/MyUserPiefedMapping.swift`, `PrivateMessagePiefedMapping.swift`, `NotificationPiefedMapping.swift`, `PersonDetailsPiefedMapping.swift`, `UnreadCountsPiefedMapping.swift` — small files mirroring the `*V3Mapping.swift` layout.
- Modify the gated `LemmyApi+*Neutral.swift` `.piefed` arms being implemented (login, vote×2, save×2, follow, markPostAsRead, hidePost, delete×2, create/edit comment+post, getMyUser, getSiteAndMyUser, unreadCounts, personDetails, personContent, listNotifications, markNotification×2, getPrivateMessages, createPrivateMessage).
- Create `Tests/LemmyKitTests/PiefedWriteClientTests.swift`, `PiefedAuthMappingTests.swift`, `PiefedWriteEndpointTests.swift`, `PiefedInboxEndpointTests.swift` + new `Fixtures/piefed-*.json`.

**Spud (worktree, branch `feat/piefed-integration`):**
- Modify `SpudDataKit/Services/NodeInfo/PlatformProfile.swift` — PieFed speaks a supported dialect; registration stays web-routed.
- Modify `SpudDataKit/Services/NodeInfo/PlatformRouter.swift` + `SpudDataKit/Services/Account/AccountService.swift` — purpose-aware preflight; login-time ApiVersion from NodeInfo; `loginNeutral`.
- Modify `SpudDataKit/Services/NodeInfo/InstanceCapabilities.swift` — real PieFed gap set.
- Modify `SpudDataKit/Services/Lemmy/LemmyService.swift` — software-aware internal `instanceCapabilities()`.
- Modify `SpudDataKit/Services/Lemmy/AuthExpiry.swift` — PieFed auth-failure shape.
- Modify `SpudDataKit/Services/Lemmy/LoadFailure.swift` (+ its error-surface consumers) — non-retriable `.notSupported` bucket.
- Modify `docs/features/piefed.md`, `docs/features/README.md`, `docs/features/instance-software-detection.md`, `docs/features/instance-capability-gating.md` (Task 9).
- Tests: `SpudDataKitTests` (dialect selection, login routing, capabilities, AuthExpiry, LoadFailure).

Task order: LemmyKit 1–6, then Spud 7–8, live validation + docs 9, polish 10. Each task = own test cycle + commit(s); LemmyKit tasks run `swift test` from the LemmyKit dir; Spud tasks run `make build` / `make test-only ONLY=SpudDataKitTests` from the worktree.

---

### Task 1: PieFed auth/write/inbox wire models + fixtures (LemmyKit)

**Files:**
- Create: `Sources/LemmyKit/PieFed/PiefedAuthEntities.swift`, `PiefedWriteResponses.swift`, `PiefedInboxEntities.swift`
- Create: `Tests/LemmyKitTests/Fixtures/piefed-login.json` (SYNTHESIZED), `piefed-user_me.json`, `piefed-site_authed.json`, `piefed-unread_count.json`, `piefed-post_response.json`, `piefed-comment_response.json`, `piefed-community_follow.json`, `piefed-success.json` (synthesized `{"success": true}`), `piefed-pm_list.json`, `piefed-pm_view.json` (synthetic from spec, labeled), `piefed-replies.json`, `piefed-person_details.json`
- Create: `Tests/LemmyKitTests/PiefedAuthDecodingTests.swift`

**Interfaces produced:** `PiefedLoginResponse` (`jwt`), `PiefedUserMeResponse` (`local_user_view{local_user, person, counts}`, `follows`, `moderates`, plus block lists + `discussion_languages` as optionals), `PiefedLocalUser`, `PiefedGetSiteAuthedResponse` (or an optional `my_user` added to the existing `PiefedGetSiteResponse` — prefer that), `PiefedUnreadCountResponse`, `PiefedPostResponse` (`post_view`), `PiefedCommentResponse` (`comment_view`), `PiefedCommunityFollowResponse` (`community_view`, optional `discussion_languages`), `PiefedSuccessResponse` (`success`), `PiefedPrivateMessage`, `PiefedPrivateMessageView` (`private_message`, `creator`, `recipient`, optional `conversation_id`), `PiefedPrivateMessageListResponse`, `PiefedRepliesResponse` (`replies`, `next_page`), `PiefedReplyItem` (the reply/mention item), `PiefedPersonDetailsResponse` — all `Codable, Sendable`, raw PieFed key names, **every field the adapters won't read is Optional** (the Phase-1 alpha-drift rule; when in doubt, Optional).

- [ ] **Step 1: Capture fixtures from piefed1** (authed where needed). From the LemmyKit dir, with creds read per the secret discipline (shell vars, one command), login and capture:
  - `piefed-user_me.json` ← `GET /api/alpha/user/me` (authed)
  - `piefed-site_authed.json` ← `GET /api/alpha/site` (authed — has `my_user`)
  - `piefed-unread_count.json` ← `GET /api/alpha/user/unread_count`
  - `piefed-post_response.json` ← the response of `POST /api/alpha/post/like {"post_id": <existing post>, "score": 1}` — then RESTORE with `score: 0`
  - `piefed-comment_response.json` ← the response of `POST /api/alpha/comment {"body": "Spud fixture capture - will be deleted", "post_id": <existing post>}` — then DELETE it (`POST comment/delete {"comment_id": <id>, "deleted": true}`)
  - `piefed-community_follow.json` ← response of `POST /api/alpha/community/follow {"community_id": <existing>, "follow": true}` — then RESTORE `follow: false`
  - `piefed-pm_list.json` ← `GET /api/alpha/private_message/list` (empty list is fine — it pins the wrapper key)
  - `piefed-replies.json` ← `GET /api/alpha/user/replies` (empty is fine)
  - `piefed-person_details.json` ← the person-details route: consult `piefed-alpha-spec.json` for the `GET /user` (or equivalent) path and its parameters, then capture it live for the test account's own person id (from `user/me`). Record the exact route+params you used in a comment at the top of `PiefedAuthDecodingTests.swift`.
  - SYNTHESIZE `piefed-login.json` as `{"jwt": "fixture.jwt.value"}` (never capture a real one) and `piefed-success.json` as `{"success": true}`.
  - `piefed-pm_view.json`: build from the spec's `PrivateMessageResponse`/`PrivateMessageView` schema (the probe recorded the field list: `private_message{id, creator_id, recipient_id, content, deleted, read, published, ap_id, local}`, `creator`, `recipient`, `conversation_id`) with person objects copied from a real fixture. Mark it `"_comment": "synthetic from spec …"`? — NO: instead note its synthetic provenance in the decode test's doc comment (fixtures must stay verbatim-shaped, no foreign keys).
  - Because `piefed-replies.json` is empty, ALSO synthesize a single-item variant `piefed-replies_item.json` from the spec's reply-view schema (mirror the CommentReplyView-like shape; person/comment sub-objects copied from real fixtures) and document its synthetic provenance in the test. It will be re-validated live in Task 9.
  - **Grep every captured file for `eyJ` and the literal password before staging.**
- [ ] **Step 2: Write the failing decode test.** `PiefedAuthDecodingTests.swift`, mirroring `PiefedDecodingTests.swift`'s `fixture(_:)` helper: one `@Test` per fixture asserting a pinned real value from the capture (e.g. `user_me` decodes with `local_user_view.person.user_name == "<the account's name>"`, `follows` decodes; `post_response.post_view.my_vote == 1`; `comment_response.comment_view.comment.body == "Spud fixture capture - will be deleted"`; `pm_list.private_messages.isEmpty`; `login.jwt == "fixture.jwt.value"`; `success.success == true`). Run `swift test --filter PiefedAuthDecodingTests` → FAIL (types undefined).
- [ ] **Step 3: Define the models** in the three new source files to make the fixtures decode. Reuse existing types (`PiefedPerson`, `PiefedPostView`, `PiefedCommentView`, `PiefedCommunityView`) — the write responses embed the SAME view shapes Phase 1 already decodes. Adapter-unread fields Optional.
- [ ] **Step 4: Green.** `swift test --filter PiefedAuthDecodingTests` → PASS; full `swift test` → all green.
- [ ] **Step 5: Commit:** `feat: add PieFed auth/write/inbox wire models`

---

### Task 2: PiefedClient write engine + auth methods + error-mapping reconciliation (LemmyKit)

**Files:**
- Modify: `Sources/LemmyKit/PieFed/PiefedClient.swift`, `Sources/LemmyKit/PieFed/PiefedError.swift`
- Modify: `Tests/LemmyKitTests/PiefedClientTests.swift` (the existing `nonTwoHundredResponseThrowsServerErrorWithMappedFields` changes)
- Create: `Tests/LemmyKitTests/PiefedWriteClientTests.swift`

**Interfaces produced:**
- `PiefedClient` gains a private generic `send<Body: Encodable, Response: Decodable & Sendable>(_ method: HTTPRequest.Method, _ path: String, body: Body, operationID: String) async throws -> Response` mirroring the existing `get` (same auth header, User-Agent, 10 MB cap, error decode; `Content-Type: application/json`).
- Public methods (names/params to match the probe's table): `login(username:password:) -> PiefedLoginResponse`, `userMe() -> PiefedUserMeResponse`, `getSiteAuthed()` (reuse `getSite()` — the authed embed rides the same route; just ensure `my_user` is an Optional field on the response model), `unreadCount() -> PiefedUnreadCountResponse`, `likePost(postId:score:) -> PiefedPostResponse`, `likeComment(commentId:score:) -> PiefedCommentResponse`, `savePost(postId:save:) -> PiefedPostResponse` (PUT), `saveComment(commentId:save:) -> PiefedCommentResponse` (PUT), `followCommunity(communityId:follow:) -> PiefedCommunityFollowResponse`, `markPostAsRead(postId:read:) -> PiefedSuccessResponse`, `hidePost(postId:hide:)` (shape per spec — check `paths["/post/hide"]` in the vendored spec; if the spec lacks it, probe live once and match), `createComment(body:postId:parentId:languageId:) -> PiefedCommentResponse`, `editComment(commentId:body:languageId:) -> PiefedCommentResponse` (PUT), `deleteComment(commentId:deleted:) -> PiefedCommentResponse`, `createPost(communityId:title:body:url:nsfw:languageId:) -> PiefedPostResponse`, `editPost(postId:title:body:url:nsfw:) -> PiefedPostResponse` (PUT), `deletePost(postId:deleted:) -> PiefedPostResponse`, `getReplies(unreadOnly:page:) -> PiefedRepliesResponse`, `getMentions(unreadOnly:page:) -> PiefedRepliesResponse`, `markCommentReplyAsRead(commentReplyId:read:)`, `markAllAsRead()`, `getPrivateMessages(unreadOnly:page:) -> PiefedPrivateMessageListResponse`, `createPrivateMessage(content:recipientId:) -> PiefedPrivateMessageView`-wrapper, `markPrivateMessageAsRead(privateMessageId:read:)`, `getPersonDetails(...)` (route/params from Task 1's capture).
- **Error mapping change** in both `get` and `send`: tolerant decode of the three envelopes —

```swift
// PiefedError.swift — replace the rigid struct with a tolerant one:
public struct PiefedErrorBody: Codable, Sendable {
    public let code: Int?
    public let message: String?
    public let status: String?
    public let error: String?   // the {"error":"not_yet_implemented"} stub shape
}

// PiefedClient error path (shared by get + send):
// semantic token precedence: message ?? error ?? status ?? String(code)
let token = piefedError.message ?? piefedError.error ?? piefedError.status ?? piefedError.code.map(String.init)
if let token {
    throw LemmyApiError.serverError(Components.Schemas.ErrorResponse(error: token, message: piefedError.message))
}
throw LemmyApiError.unknownServerError(httpStatusCode: response.status.code, error: nil)
```

  (An all-nil decode falls through to `unknownServerError`.) **Update the existing test**: `#expect(errorResponse.error == "incorrect_login")` (was `"400"`); add cases for the `{message}`-only and `{error}`-only shapes.

- [ ] **Step 1: Write failing tests.** In `PiefedWriteClientTests.swift`, using the existing `RecordingStubTransport` pattern extended to also capture the request BODY bytes and method: (a) `likePost` issues `POST /api/alpha/post/like` with JSON body `{"post_id":13,"score":1}` and `Authorization: Bearer <token>`; (b) `savePost` issues **PUT** `/api/alpha/post/save`; (c) `login` issues `POST /api/alpha/user/login` with `{"username":"u","password":"p"}` and NO auth header when token is nil, decoding `piefed-login.json`; (d) responses decode via the Task-1 fixtures (`piefed-post_response.json` etc.); (e) the three error-envelope shapes each throw `.serverError` with the semantic token in `.error`. Update the Phase-1 error test expectation in `PiefedClientTests.swift`. Run → FAIL.
- [ ] **Step 2: Implement** the `send` engine + methods + error mapping. Body encoding via `JSONEncoder` with the raw PieFed key names (models are wire-shaped, so plain `Encodable` structs or dictionaries per method — prefer small per-request `Encodable` structs local to `PiefedClient.swift` or a sibling `PiefedRequests.swift` if the file grows past ~500 lines).
- [ ] **Step 3: Green.** `swift test --filter 'PiefedWriteClientTests|PiefedClientTests'` then full `swift test`.
- [ ] **Step 4: Commit:** `feat: add PieFed write/auth client engine with tolerant error envelopes`

---

### Task 3: my-user / inbox / DM / person adapters (LemmyKit)

**Files:**
- Create: `Sources/LemmyKit/Adapters/MyUserPiefedMapping.swift`, `UnreadCountsPiefedMapping.swift`, `PrivateMessagePiefedMapping.swift`, `NotificationPiefedMapping.swift`, `PersonDetailsPiefedMapping.swift`
- Create: `Tests/LemmyKitTests/PiefedAuthMappingTests.swift`

**Interfaces produced (match the neutral types EXACTLY — read each `Neutral/*.swift` first):**
- `package func neutralMyUser(fromPiefed response: PiefedUserMeResponse) -> MyUser` — `person` via existing `neutralPerson(fromPiefed:)`; `localUserId` from `local_user.id`; booleans from `local_user` (map what exists; PieFed-absent settings take the same defaults `MyUserV3Mapping.swift` uses); `follows: [Community]` via `neutralCommunity(fromPiefed:)` over the `follows` entries; `moderates: [Int64]` from moderated community ids. Mirror `MyUserV3Mapping.swift` / `MyUserV4Mapping.swift` field-for-field and doc-comment every PieFed-absent field's default.
- `package func neutralUnreadCounts(fromPiefed response: PiefedUnreadCountResponse) -> UnreadCounts` — read `Neutral/UnreadCounts.swift` for the exact fields; PieFed supplies `mentions`, `replies`, `private_messages` (fold `other` into whatever total the neutral type carries, mirroring how the v3 mapping totals).
- `package func neutralPrivateMessageView(fromPiefed view: PiefedPrivateMessageView) -> PrivateMessageView` + the list-item mapping to `PrivateMessageListItem` (read `Neutral/PrivateMessageListItem.swift` — it carries `isRead`; PieFed `private_message.read` feeds it). Mirror `PrivateMessageViewV3Mapping.swift`.
- `package func neutralNotificationView(fromPiefedReply item: PiefedReplyItem, kind: NotificationKind) -> NotificationView` — mirrors `CommentReplyNotificationV3Mapping.swift`: build the `CommentView` via `neutralCommentView(fromPiefed:)` from the item's embedded comment/creator/community/counts, `NotificationEntry(id: <the item's reply id>, kind: kind, isRead: item.read, publishedAt: …)`.
- `package func neutralPersonDetails(fromPiefed response: PiefedPersonDetailsResponse) -> PersonDetails` and the person-content page mapping to `Page<PostOrComment>` (read `Neutral/PersonDetails.swift` + `Neutral/PostOrComment.swift`; posts/comments map via the existing Phase-1 view adapters).
- [ ] **Step 1: Failing tests** — decode each Task-1 fixture, run the adapter, assert pinned values (e.g. `neutralMyUser` yields the account's `person.name`, non-empty `follows` iff the fixture has follows; `neutralUnreadCounts` sums correctly; the synthetic reply item maps with `kind == .reply` and `isRead` faithful). Run → FAIL.
- [ ] **Step 2: Implement.** Small files, one mapping concern each, mirroring the corresponding `*V3Mapping.swift`.
- [ ] **Step 3: Green** (`--filter PiefedAuthMappingTests`, then full suite). **Step 4: Commit:** `feat: add PieFed my-user/inbox/DM/person neutral adapters`

---

### Task 4: Wire the write endpoints' `.piefed` dispatch (LemmyKit)

**Files:**
- Modify: `LemmyApi+LoginNeutral.swift`, `LemmyApi+VotePostNeutral.swift`, `LemmyApi+VoteCommentNeutral.swift`, `LemmyApi+SavePostNeutral.swift`, `LemmyApi+SaveCommentNeutral.swift`, `LemmyApi+FollowCommunityNeutral.swift`, `LemmyApi+MarkPostAsReadNeutral.swift`, `LemmyApi+HidePostNeutral.swift`, `LemmyApi+DeletePostNeutral.swift`, `LemmyApi+DeleteCommentNeutral.swift`, `LemmyApi+CreateCommentNeutral.swift`, `LemmyApi+EditCommentNeutral.swift`, `LemmyApi+CreatePostNeutral.swift`, `LemmyApi+EditPostNeutral.swift`
- Create: `Tests/LemmyKitTests/PiefedWriteEndpointTests.swift`

**Interfaces:** the existing neutral signatures (unchanged — see the Phase-1 inventory in the progress ledger): `loginNeutral(usernameOrEmail:password:totp:) -> String`, `votePostNeutral(id:direction:) -> PostView`, `voteCommentNeutral(id:direction:) -> CommentView`, `savePostNeutral(id:saved:) -> PostView`, `saveCommentNeutral(id:saved:) -> CommentView`, `followCommunityNeutral(id:follow:) -> CommunityView`, `markPostAsReadNeutral(id:read:)`, `hidePostNeutral(id:hidden:)`, `deletePostNeutral(id:deleted:) -> PostView`, `deleteCommentNeutral(id:deleted:) -> CommentView`, `createCommentNeutral(content:postId:parentId:languageId:) -> CommentView`, `editCommentNeutral(id:content:) -> CommentView`, `createPostNeutral(name:communityId:url:body:nsfw:languageId:) -> PostView`, `editPostNeutral(id:name:url:body:nsfw:) -> PostView`.

- [ ] **Step 1: Failing endpoint tests** mirroring `PiefedNeutralEndpointTests.swift`'s `PathRoutingStubTransport` (extend it to also match on HTTP method and to serve write responses): build `LemmyApi(instanceUrl:credential:LemmyCredential(jwt:"t"), transport:, apiVersion: .piefed)`, call each neutral method, assert the neutral DTO (e.g. `votePostNeutral(id:direction:.up)` hits `POST /api/alpha/post/like`, returns a `PostView` whose `postActions.voteIsUpvote == true`; `followCommunityNeutral` returns `followState == .accepted` from the follow fixture; `loginNeutral` returns `"fixture.jwt.value"`). Run → FAIL (they currently throw `unsupportedByDialect`).
- [ ] **Step 2: Implement each `.piefed` case** as a private `…NeutralPiefed` helper (the Phase-1 pattern: `guard let piefedClient else { throw … }`, call, map via adapters). Specifics:
  - `loginNeutral`: PieFed logs in by USERNAME; pass `usernameOrEmail` through as `username` (document: PieFed has no email login). `totp` is IGNORED for `.piefed` (no wire field; PieFed test accounts must have 2FA off) — doc-comment this.
  - Vote: convert `direction: VoteDirection` to the −1/0/1 score with the SAME conversion the v3 arm uses in the same file — reuse/extract it, don't duplicate.
  - `markPostAsReadNeutral` returns Void — call, decode `{success}`, discard (throw on transport/server error only).
  - `hidePostNeutral(id:hidden:)` → `POST post/hide` with the body shape confirmed in Task 2.
  - `editPostNeutral(name:)` is Optional in the neutral signature; PieFed edit accepts partial bodies — send only non-nil fields.
- [ ] **Step 3: Green** (`--filter PiefedWriteEndpointTests` then full `swift test` — the `PiefedDialectTests` gated-contract test samples `votePostNeutral`/`createCommentNeutral`/`followCommunityNeutral`/`hidePostNeutral`/`loginNeutral`, which are now IMPLEMENTED — update that test to sample endpoints that remain gated, e.g. `registerNeutral`, `blockPersonNeutral`, `uploadImageNeutral`, `saveUserSettingsNeutral`).
- [ ] **Step 4: Commit:** `feat: implement PieFed write endpoints through the neutral facade`

---

### Task 5: Wire my-user / site / person / unread endpoints (LemmyKit)

**Files:**
- Modify: `LemmyApi+GetMyUserNeutral.swift`, `LemmyApi+GetSiteAndMyUserNeutral.swift`, `LemmyApi+UnreadCountsNeutral.swift`, `LemmyApi+GetPersonDetailsNeutral.swift`, `LemmyApi+ListPersonContentNeutral.swift`
- Create: `Tests/LemmyKitTests/PiefedIdentityEndpointTests.swift`

**Interfaces:** `getMyUserNeutral() -> MyUser`, `getSiteAndMyUserNeutral() -> SiteWithMyUser`, `unreadCountsNeutral() -> UnreadCounts`, `personDetailsNeutral(personId:) -> PersonDetails`, `personContentNeutral(personId:pageCursor:) -> Page<PostOrComment>`.

- [ ] **Step 1: Failing tests** (PathRoutingStubTransport + Task-1 fixtures): `getMyUserNeutral` → `MyUser` with the fixture's person name; `getSiteAndMyUserNeutral` → single authed `GET /api/alpha/site` (the `my_user` embed — v3-style one-request implementation; assert only ONE path was hit), `myUser == nil` when the fixture lacks `my_user` (signed-out shape must still work); `unreadCountsNeutral` totals; `personDetailsNeutral`/`personContentNeutral` against `piefed-person_details.json`. Run → FAIL.
- [ ] **Step 2: Implement.** `getSiteAndMyUserNeutral` for `.piefed` = one authed `getSite()` call, `SiteWithMyUser(site: neutralSiteInfo(fromPiefed:), myUser: response.my_user.map(neutralMyUser…))` — note the my-user embed model must be reachable from the site response (Task 1 put an optional `my_user` on `PiefedGetSiteResponse`; the `neutralMyUser` adapter needs a variant accepting that embed if its shape differs from `user/me` — check the two captured fixtures and share one wire model if identical, else add the second thin adapter overload).
  `personContentNeutral` pages with the same integer-cursor convention Phase 1 used (`Cursor(rawValue: String(page))`) — reuse `neutralPage(fromPiefed:nextPage:mapItem:)`.
- [ ] **Step 3: Green** + full suite. **Step 4: Commit:** `feat: implement PieFed identity and person endpoints`

---

### Task 6: Wire inbox + DM endpoints (LemmyKit)

**Files:**
- Modify: `LemmyApi+ListNotificationsNeutral.swift`, `LemmyApi+MarkNotificationNeutral.swift`, `LemmyApi+GetPrivateMessagesNeutral.swift`, `LemmyApi+CreatePrivateMessageNeutral.swift`
- Create: `Tests/LemmyKitTests/PiefedInboxEndpointTests.swift`

**Interfaces:** `listNotificationsNeutral(unreadOnly:pageCursor:kind:) -> Page<NotificationView>`, `markNotificationAsReadNeutral(id:read:)`, `markAllNotificationsAsReadNeutral()`, `getPrivateMessagesNeutral(unreadOnly:pageCursor:) -> Page<PrivateMessageListItem>`, `createPrivateMessageNeutral(content:recipientId:) -> PrivateMessageView`.

- [ ] **Step 1: Failing tests**: `listNotificationsNeutral(kind: .reply)` → `GET /api/alpha/user/replies` (assert path), maps the synthetic item fixture to a `NotificationView` with `kind == .reply`; `kind: .mention` → `user/mentions`; `kind: nil` → both routes merged (or document + implement kind-required-for-piefed — see Step 2 decision); `markNotificationAsReadNeutral` → `POST comment/mark_as_read` `{comment_reply_id, read}`; `markAllNotificationsAsReadNeutral` → `POST user/mark_all_as_read`; `getPrivateMessagesNeutral` decodes the empty list fixture to an empty `Page`; `createPrivateMessageNeutral` posts `{content, recipient_id}` and maps the synthetic `piefed-pm_view.json`. Run → FAIL.
- [ ] **Step 2: Implement.** Design decisions:
  - Spud's inbox only ever calls `listNotificationsNeutral` with an explicit `kind` (`.reply`/`.mention` — see `LemmyService+Inbox.swift:135,179`). For `.piefed`, implement `.reply`→`user/replies`, `.mention`→`user/mentions`; for `kind: nil` or kinds PieFed's Lemmy-compat surface lacks (mod actions), throw `unsupportedByDialect(operation: "listNotifications(kind:nil)")` with a doc comment — do NOT silently merge.
  - **Mention mark-read:** the Lemmy-compat mention item's id semantics must be confirmed against the spec (`user/mentions` item — does it carry a `comment_reply_id`-equivalent, or does mention mark-read need `PUT user/notification_state`?). Implement what the spec supports; if mentions have no per-item mark-read on the compat surface, mark-read for `.mention`-sourced ids throws `unsupportedByDialect(operation: "markNotificationAsRead(mention)")` and the LIMITATION is doc-commented (Task 9 documents it user-facing; mark-ALL still works).
  - `unreadOnly` maps to the routes' `unread_only` param (confirm the exact param name in the spec; Lemmy-compat routes usually take `unread_only=true`).
- [ ] **Step 3: Green** + full `swift test`. **Step 4: Commit:** `feat: implement PieFed inbox and private-message endpoints`

---

### Task 7: Spud — unblock PieFed login + route it (Spud worktree)

**Files:**
- Modify: `SpudDataKit/Services/NodeInfo/PlatformProfile.swift`, `SpudDataKit/Services/NodeInfo/PlatformRouter.swift`, `SpudDataKit/Services/Account/AccountService.swift`
- Test: extend `SpudDataKitTests` (a `PlatformProfile`/`PlatformRouter` test file exists — find it; plus `AccountServiceDialectSelectionTests`-adjacent login-routing tests)

**Interfaces consumed:** `LemmyApi.loginNeutral(usernameOrEmail:password:totp:) -> String` (now piefed-implemented), `ApiVersion.piefed`, `AppDatabase.nodeInfoCachedSoftwareSync` (from Phase-1 Task 6, `SpudDataKit/Services/AppDatabase/NodeInfoCacheQueries.swift`).

- [ ] **Step 1: Failing tests.**
  (a) `PlatformProfile.profile(for: .piefed).speaksLemmyAPI == true` (or the renamed predicate — see Step 2) and `.profile(for: .mbin).speaksLemmyAPI == false`;
  (b) registration purpose still blocks PieFed: `PlatformRouter.evaluateHomeConnection(host:purpose:.register)` (new param) returns `.block` for a `.piefed` host while `.login` returns `.allow`;
  (c) login routing: with a NodeInfo cache row saying `.piefed` for the host, `AccountService.login` builds the login `LemmyApi` with `apiVersion == .piefed` (test via the existing test seams — the `AccountServiceDialectSelectionTests` file shows how to seed the cache row and how `makeApi` is observed; if `makeApi` isn't observable, assert on the stored account's subsequent `lemmyService` dialect + that login succeeded against a stub transport serving `piefed-login.json`-shaped `{jwt}` from `/api/alpha/user/login`).
  Run: `make test-only ONLY=SpudDataKitTests` (targeted `-only-testing:` while iterating) → FAIL.
- [ ] **Step 2: Implement.**
  - `PlatformProfile.swift:36`: `speaksLemmyAPI: software == .lemmy || software == .piefed` — and update the property's doc comment ("speaks a Lemmy-compatible API surface Spud can drive (Lemmy v3/v4 or PieFed /api/alpha dialect)"). Add `supportsAppRegistration: Bool` = `software == .lemmy` with a doc comment (PieFed registration is web-only — verified 2026-07-15: doubled register path + stub password flows).
  - `PlatformRouter.evaluateHomeConnection(host:)` gains `purpose: HomeConnectionPurpose` (`enum HomeConnectionPurpose: Sendable { case login, register }`): block when `!profile.canBeHomeConnection || (purpose == .register && !profile.supportsAppRegistration)`. `AccountService.preflightHomeConnection(host:)` gains the same param; `login`/`reauthenticate` pass `.login`, `register` passes `.register`. Keep the existing block-sheet copy path working for both (the sheet already names the software; registration-block for PieFed shows the same platform sheet routing to Safari — confirm the copy reads sensibly for "registration on PieFed happens on the web" and adjust the sheet copy ONLY if it's software-parameterized already; do not build a new sheet).
  - `AccountService.login` (`:695`) + `reauthenticate` (`:747`): replace `makeApi(url, nil, .v3)` with a host-resolved version: `.piefed` when `appDatabase.nodeInfoCachedSoftwareSync(host:)`-equivalent reports `.piefed` (the preflight's `detect` has just populated the cache), else `.v3`. Replace the `api.login(usernameOrEmail:password:totp2faToken:)` + `response.jwt` guard with `let jwt = try await api.loginNeutral(usernameOrEmail: username, password: password, totp: totp2faToken)` — `AccountServiceLoginError.init(from:)` keeps working because PieFed's `incorrect_login` now lands in `ErrorResponse.error` (Task 2).
- [ ] **Step 3: Build + tests.** `make build && make test-only ONLY=SpudDataKitTests` — ALL green (this task's + the whole target).
- [ ] **Step 4: Commit** (code only): `feat: allow PieFed login and route it through the .piefed dialect`

---

### Task 8: Spud — capability gap set, software-aware gating, auth-expiry, not-supported presentation (Spud worktree)

**Files:**
- Modify: `SpudDataKit/Services/NodeInfo/InstanceCapabilities.swift`, `SpudDataKit/Services/Lemmy/LemmyService.swift` (`instanceCapabilities()`, `:807-813`), `SpudDataKit/Services/Lemmy/AuthExpiry.swift`, `SpudDataKit/Services/Lemmy/LoadFailure.swift` + its consumers (`FeedStateSurfaceView` / the error-surface enum it renders)
- Tests: `SpudDataKitTests` (InstanceCapabilities, AuthExpiry, LoadFailure suites exist — extend them)

- [ ] **Step 1: Empirically pin PieFed's invalid-token behavior.** One-off curl against piefed1: authed route (`GET /api/alpha/user/unread_count`) with `Authorization: Bearer invalid.token.value` — record HTTP status + body shape in the test's doc comment (no secrets involved; the token is fake). This determines the AuthExpiry arm: if 401 → already covered by `.unauthorized`/`unknownServerError(401)`; if 400/`{…"message":"…"}` → add that semantic token to `AuthExpiry.authCodes` (it reaches `.error` via Task 2's mapping).
- [ ] **Step 2: Failing tests.**
  (a) `InstanceCapabilities.capabilities(software: .piefed, version: nil)` lacks exactly `.imageUpload` and `.serverUserSettings` and has everything else; `.lemmy` stays `.allAvailable`.
  (b) `LemmyService`'s internal gating is software-aware: a `LemmyService` whose account host has a `.piefed` NodeInfo cache row resolves capabilities WITHOUT `.imageUpload` (test through an existing seam — `LemmyServiceContentNotFoundTests` shows how a `LemmyService` is built in tests; assert via a gated path, e.g. `markAsRead` capability check, or expose the resolved capabilities through the existing test surface if one exists — mirror how `requireCapability` is already tested).
  (c) `AuthExpiry.isAuthExpiry` true for the Step-1 shape.
  (d) `LoadFailure` maps `.unsupportedByDialect` and `.unsupportedByInstance` to a NEW non-retriable case `.notSupported` (not `.unreachable`).
  Run → FAIL.
- [ ] **Step 3: Implement.**
  - `InstanceCapabilities.capabilities(software:version:)`: `switch software { case .piefed: return InstanceCapabilities(available: Set(InstanceCapability.allCases).subtracting([.imageUpload, .serverUserSettings])) default: return .allAvailable }` — match the type's actual constructor (read the file; there may be a set-based init or `.allAvailable` factory to mirror). Doc-comment each PieFed gap with the probe evidence (image upload = multipart, deferred; server settings push = unverified shape, deferred — local prefs still work).
  - `LemmyService.instanceCapabilities()` (`LemmyService.swift:807`): stop hardcoding `.lemmy` — resolve the account's software the same way `AccountService.instanceCapabilities` does (`isPiefed` branch): read the account's instance host + NodeInfo cache via `appDatabase` (both reads exist as sync helpers from Phase-1 Task 6; LemmyService is an actor — use the async `appDatabase` variants if the sync ones are main-actor-bound, mirroring the existing `accountSiteVersion` call on the neighboring line).
  - `AuthExpiry`: per Step 1.
  - `LoadFailure`: add `.notSupported`; map both unsupported cases to it; update the error-surface rendering (find the switch that renders `LoadFailure` cases — `FeedStateSurfaceView` or its state enum) with copy `"Not available on this instance"` + NO retry affordance (mirror how a non-retriable state, if any exists, is rendered; otherwise render the same surface minus the retry button). Update `ErrorMessage.swift`'s `.unsupportedByDialect` copy to match terminology ("This isn't available on your account's instance."). If an existing snapshot test covers the error surface states, add the new state to it and re-record ONLY that class per the snapshot ceremony.
- [ ] **Step 4: Build + full target tests green.** `make build && make test-only ONLY=SpudDataKitTests` (+ `ONLY=SpudTests` if `ErrorMessage`/surface tests live there — run the changed classes).
- [ ] **Step 5: Commit:** `feat: seed PieFed capability gaps, software-aware gating, and not-supported presentation`

---

### Task 9: Live end-to-end validation on piefed1 + docs (Spud worktree)

**Files:**
- Modify: `docs/features/piefed.md`, `docs/features/README.md`, `docs/features/instance-software-detection.md`, `docs/features/instance-capability-gating.md`

- [ ] **Step 1: Live validation.** Build with the local-path LemmyKit (`make build`), install on the booted reference sim, and drive the REAL flows against `piefed1.lemmy.ddenis.info` with the test account (creds typed via XCUITest seam or the login UI driven by a temporary `#if DEBUG` launch-arg auto-nav; NEVER screenshot a screen with the password visible; revert all temp code after). Validate, screenshotting each to `.superpowers/sdd/task-9-screens/`:
  1. Log in (instance entry → login → lands signed-in; Account tab shows the person).
  2. Authed feed shows interaction state (`my_vote`/saved reflected after actions).
  3. Vote a post up + back (optimistic pill updates, outbox drains, survives re-fetch).
  4. Save/unsave a post. 5. Subscribe/unsubscribe a community (state + Communities tab). 6. Comment on a post (optimistic insert → server id lands), edit it, delete it. 7. Create a post (composer), edit, delete. 8. Post opens → mark-read pushes without error (the Phase-1 log seam is gone — check About → Logs shows no `markPostAsRead` unsupported error). 9. Inbox opens without capability error (empty is fine); DM list opens; send a DM to self if PieFed permits, else note. 10. Person profile opens from an author tap AND from a search-users result (the Phase-1 dead-end is gone). 11. Sign-in gate no longer intercepts (signed-in). 12. Session-reauth: not directly testable without expiring the token — SKIP live, covered by unit tests.
  Restore instance state afterward (unvote/unsave/unsubscribe/delete test content). Record any live decode/render failure, fix at the right layer (loop back to Tasks 1-6 files with a regression test), re-validate.
- [ ] **Step 2: Docs.** `piefed.md`: `Status:` → shipped for browse + sign-in + interactions (list what now works); rewrite the "Not supported" section to the REAL residual gaps (register/password flows = web-only; image upload; server-settings push; account feeds (Saved/liked lists); blocks; mention per-item mark-read if Task 6 confirmed the limitation; PieFed-native extras = Phase 3); fix the Phase-1 residual nit (personDetails/personContent are credential-free reads, not "auth-shaped"); update the mark-read passage (now implemented). Update README's two PieFed rows. `instance-software-detection.md`: PieFed is now loginable (registration still web-routed). `instance-capability-gating.md`: document the first real gap set (PieFed: imageUpload, serverUserSettings). Scenarios in Given/When/Then per the template; no `.swift` links; no emojis.
- [ ] **Step 3: Commit:** `docs: document PieFed sign-in and interactions (Phase 2)`

---

### Task 10: Phase-1 debt polish (Spud worktree)

**Files:**
- Modify: `SpudDataKit/Services/Account/AccountService.swift` (memoize piefed-ness beside the existing `lemmyServiceApiVersions` cache; invalidate wherever that cache is evicted AND on NodeInfo cache upsert if an eviction hook exists — if none exists, invalidate on the same self-healing re-resolve path and doc-comment the staleness bound), `Spud/Scenes/Account/InstanceDetail/InstanceDetailViewController.swift` (`browseTapped`: reentry guard — disable the button / ignore re-taps while the NodeInfo await is in flight — plus a `UIActivityIndicatorView` or button-config spinner during it)
- Tests: extend `AccountServiceDialectSelectionTests` (memoization: second `lemmyService()` call performs no additional NodeInfo cache read — observe via a counting spy DB or assert on the cached value being served; mirror how the existing self-healing cache is tested)

- [ ] **Step 1: failing memoization test → implement → green.** **Step 2: browseTapped guard** (no automated UI test — idb dead; verify by code review + the existing build). **Step 3: `make build && make test-only ONLY=SpudDataKitTests` green. Commit:** `refactor: memoize dialect resolution and guard Browse against re-entry`

---

## Final verification (Phase 2)

- [ ] LemmyKit: full `swift test` green (Phase-1 suites + all new PieFed auth/write suites).
- [ ] Spud: `make build` + `make test-only ONLY=SpudDataKitTests` green; changed `SpudTests` classes green.
- [ ] LIVE: the Task-9 checklist passed on `piefed1.lemmy.ddenis.info` with screenshots; instance state restored.
- [ ] Lemmy regression: existing UITest stubs unaffected (neutral wire shapes unchanged for v3/v4).
- [ ] Whole-branch review (LemmyKit Phase-2 diff + Spud Phase-2 diff) before considering Phase 2 complete.
- [ ] `project.yml` override still UNCOMMITTED; LemmyKit still local/unpushed/untagged. Integration (LemmyKit merge/push, Spud pin bump by revision, Spud merge to main) remains gated on HUMAN validation — not part of this plan.

## Coverage vs design (Phase-2 section of `docs/superpowers/specs/2026-07-15-piefed-integration-design.md`)

- PieFed login (username + error envelope) → Tasks 2, 4, 7.
- Auth'd neutral endpoints (vote/save/subscribe/hide, create/edit post+comment, mark-read, my-user, subscribed list via MyUser.follows, inbox, DMs) → Tasks 1-6.
- Capability-gate PieFed's gaps → Task 8 (gap set: imageUpload, serverUserSettings; register/password web-only enforced at the platform-router level in Task 7).
- Unblock PieFed login + fix the two hardcoded Lemmy assumptions (`speaksLemmyAPI`, `LemmyService.instanceCapabilities` software) → Tasks 7, 8.
- PieFed error mapping through existing channels (incl. the error-code inversion landmine from the Phase-1 final review) → Task 2 (+ AuthExpiry in Task 8).
- Person profiles dead-end (Phase-1 documented gap) → Tasks 5, 9.
- Every claim re-tested on-device → Task 9.
- Phase-1 review debt (memoization, browse reentry, not-supported presentation) → Tasks 8, 10.
