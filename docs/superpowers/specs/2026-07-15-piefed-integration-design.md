# PieFed integration — design

Date: 2026-07-15
Status: Design approved-pending — Phase 0 (verification) complete; awaiting go-ahead to build
Branch: `feat/piefed-integration` (Spud) + paired LemmyKit work
Related: [instance-software-detection.md](../../features/instance-software-detection.md), the Lemmy v3/v4 neutral-API work, `docs/superpowers/specs/2026-07-05-nodeinfo-platform-detection-design.md`

## Goal

Make PieFed a first-class citizen in Spud: let users log into and fully use PieFed
home instances (browse, vote, comment, post, subscribe, DMs), not just see PieFed
content that federates into the Lemmy instances Spud connects to. Do it the way that
best fits Spud + LemmyKit's existing architecture.

## Phase 0 — verified API reality (piefed.social, PieFed 1.7.5, 2026-07-15)

Empirically probed, not assumed. These facts override the initial research's
higher-level claims where they differ.

1. **NodeInfo works.** `/.well-known/nodeinfo` → 200; software `piefed`. Spud already
   detects `InstanceSoftware.piefed`.
2. **`/api/v3` is a probe-only shim.** `/api/v3/site` → 200 (Lemmy-shaped `site_view`,
   `version: "1.7.5"`), but `/api/v3/post/list`, `/api/v3/community/list`,
   `/api/v3/user/login` all → **404**. So Spud can *detect/connect* to PieFed today
   (the site probe succeeds) but **cannot browse it** — feeds 404. Current real status
   is federation-only.
3. **PieFed's real API is entirely under `/api/alpha/*`.** `/api/alpha/site`,
   `/api/alpha/post/list`, `/api/alpha/community/list`, `/api/alpha/user/login` all
   → 200. Route names mirror Lemmy v3 (`post/list`, `community/follow`,
   `private_message/*`, `user/login`, `search`, `resolve_object`). Confirmed by
   PieFed's own repo (`app/api/alpha/routes.py`) and its OpenAPI 3.1 spec.
4. **Responses are Lemmy-shaped at the VIEW level, divergent at the ENTITY level.**
   `PostView`/`CommunityView` wrappers carry every Lemmy-required flag (`subscribed`
   as the `NotSubscribed` enum string, `saved`, `read`, `my_vote`,
   `creator_is_moderator`, `creator_is_admin`, `creator_banned_from_community`,
   `banned_from_community`, `unread_comments`, `counts`, `creator`, `community`,
   `post`). But the nested entities rename required fields:

   | Lemmy field (required) | PieFed `/api/alpha` field |
   |---|---|
   | `post.creator_id` | `post.user_id` |
   | `post.name` (post title) | `post.title` |
   | `post.featured_community` / `featured_local` | `post.sticky` / `instance_sticky` |
   | `person.name` / `display_name` / `bot_account` | `creator.user_name` / `title` / `bot` |
   | `community.posting_restricted_to_mods` | `community.restricted_to_mods` |
   | `community.visibility` (required in v0.19) | *absent* |
   | `banned_from_community: Bool` | `null` on community list |

   PieFed-native additions (`ai_generated`, `emoji_reactions`, `flair`, `flair_list`,
   `post_type`, `tags`, `question_answer`, `small_thumbnail_url`, `blurred`,
   `can_auth_user_moderate`, `activity_alert`) decode-safely (swift-openapi-generated
   Codable ignores unknown keys — verified: zero custom decoders, no
   `additionalProperties`).
5. **Error envelope differs.** Bad-cred login → `{"code":400,"message":
   "incorrect_login","status":"Bad Request"}`, NOT Lemmy's `{"error":"..."}`. PieFed
   error mapping is its own path.
6. **Login field differs.** PieFed `/api/alpha/user/login` takes `username` (no
   `username_or_email`, no `totp_2fa_token`).

**Conclusion:** Lemmy's generated v3 models CANNOT decode PieFed's `/api/alpha`
responses (missing `creator_id`, `name`, `visibility`; `banned_from_community: null`
into a non-optional `Bool`). PieFed needs real response *adaptation*, not a path swap.
But the divergence is systematic and shallow — a rename/restructure per entity — and
maps cleanly onto LemmyKit's existing neutral-DTO facade.

## LemmyKit attach points (verified)

- LemmyKit is swift-openapi-generated from a submodule spec, with **two** generated
  targets today: `LemmyKit` (v3) and `LemmyKitV4Generated` (v4). Adding PieFed as a
  **third generated target** from PieFed's own OpenAPI spec mirrors exactly how v4 was
  added.
- The `/api/v3` prefix is baked into each **operation path** (not the server URL), so a
  path-rewrite middleware is the seam if we reuse a Lemmy client. But because PieFed's
  entity shapes diverge, we generate PieFed's own client from its spec instead — the
  paths (`/api/alpha/...`) come baked-in correctly and for free.
- The neutral facade dispatches on `ApiVersion` (`enum { v3, v4 }`) across ~38
  `*Neutral.swift` endpoints, each mapping the version-specific response → shared
  **neutral DTOs** (`SiteInfo`, neutral post/comment/community, etc.) via `Adapters/
  *V3Mapping.swift` / `*V4Mapping.swift`. PieFed becomes a third adapter set into the
  SAME neutral DTOs.
- Auth is a bare JWT bearer via an injectable `ClientMiddleware`; transport is
  injectable for tests. PieFed reuses this unchanged.

## Architecture decision (answering "where does it live")

**Extend LemmyKit into a threadiverse-neutral client that speaks Lemmy (v3/v4) AND
PieFed, keeping the package name `LemmyKit` for now.** PieFed is added as a third
dialect behind the existing neutral-DTO facade.

Rejected alternatives:
- **In Spud (app-level compat):** wrong layer. Wire-format translation belongs at the
  API layer; the whole point of LemmyKit's neutral DTOs is that the app never sees the
  dialect. Putting PieFed adaptation in Spud would duplicate/bypass the neutral seam
  and pollute the app.
- **A standalone "compat shim" package:** unnecessary indirection; the neutral facade
  in LemmyKit already IS the compatibility layer (this is exactly what Voyager built
  `threadiverse` to be — LemmyKit already plays that role for v3/v4).
- **Rename to "FediverseKit" now:** premature. PieFed fits the Lemmy-shaped neutral
  DTOs with adaptation; it does NOT justify a ground-up fediverse abstraction. Mbin
  (a genuinely different data model) is not requested. Renaming the SPM package churns
  every import + the remote pin for no current benefit (YAGNI). **We DO structure the
  internals extensibly** (a `Dialect` type + per-dialect adapters) so adding Mbin later
  is a clean extension, and a rename to FediverseKit becomes reasonable *if/when* a
  third genuinely-different platform lands. For now: "Lemmy-or-PieFed framework"
  internally, `LemmyKit` externally.

### The dialect design

- Promote/augment `ApiVersion` into a `ServerDialect` (name TBD) — `{ lemmyV3, lemmyV4,
  piefed }`. This makes the compiler enumerate every one of the ~38 neutral dispatch
  sites, which is desirable: it forces explicit PieFed coverage (or an explicit
  `unsupported` throw) per endpoint rather than silent fallthrough. Justified now
  because PieFed diverges at every entity (not a narrow delta).
- Add `LemmyKitPieFedGenerated` — a third generated target from PieFed's alpha OpenAPI
  spec (vendored into the `Lemmy-OpenAPI-Spec` submodule alongside v3/v4, or a sibling
  spec repo). Gives typed PieFed request/response models with `/api/alpha` paths baked
  in.
- Add `Adapters/*PieFedMapping.swift` — map PieFed's generated types → the neutral DTOs
  (the `user_id→creatorId`, `title→name`, `user_name→name`, `restricted_to_mods→...`,
  `sticky→featured` renames; synthesize `visibility` default; coalesce
  `banned_from_community: null→false`).
- PieFed login helper: `username` field, PieFed error-envelope decoding.
- `ApiVersionProbe` analog: probe `/api/alpha/site` to confirm PieFed; but Spud already
  knows the software from NodeInfo, so dialect is chosen from detected software, not
  probed.

## Spud-side changes (small — the neutral facade absorbs the rest)

- **Dialect selection from NodeInfo.** `AccountService.resolvedApiVersion` currently
  maps a Lemmy version → v3/v4. It must instead consult detected `InstanceSoftware`:
  `.piefed → .piefed` dialect; `.lemmy → v3/v4 by version`. The PieFed version
  (`1.7.5`) must NOT be read on the Lemmy v3/v4 scale.
- **Unblock PieFed login.** `PlatformProfile.speaksLemmyAPI = (software == .lemmy)`
  becomes `software == .lemmy || software == .piefed` (or a broader "speaks a supported
  dialect"). One line; cascades correctly through the existing preflight gate.
- **Capability-gate PieFed's gaps.** `InstanceCapabilities.capabilities(software:
  version:)` (already takes `software:`) returns a PieFed gap set. Every UI/service gate
  already routes through `.can(_:)`, so gating is data, not code. Gap set seeded from
  Phase 0 + Voyager's checklist, then trimmed by on-device testing:
  provisionally-unavailable candidates to VERIFY — registration (web-only?), 2FA login,
  password reset/change, delete account, admin/purge, custom emoji; and the historically
  flaky inbox / subscribed-list / mark-read / profile vote-history.
- **Fix the second hardcoded assumption.** `AccountService.instanceCapabilities` passes
  `software: .lemmy` — must pass the account's real software.
- **Error mapping.** Surface PieFed's `{code,message,status}` errors through the same
  `LemmyServiceError` channels (handled in LemmyKit's PieFed layer, so Spud is
  unaffected).
- Onboarding plumbing (`SiteListRow.forTypedInstance` → `ensureSite` → `ensureAccount`)
  is already software-agnostic — no change.

## Phased plan

- **Phase 1 — Browse a PieFed instance (NO credentials needed; fully verifiable).**
  The keystone. LemmyKit: vendor PieFed's alpha spec, generate the PieFed target, add
  the `piefed` dialect + adapters for the read surface (`getSite`, `getPosts`,
  `getComments`, `getCommunity`, `listCommunities`, `search`, `resolveObject`), path
  baked to `/api/alpha`. Spud: select the PieFed dialect from NodeInfo for browse.
  Exit: sign-out browse of `piefed.social` shows real feeds/communities/comments in
  Spud, decoded through the neutral DTOs. Validated against the live instance with no
  account.
- **Phase 2 — Log in + interact (NEEDS a PieFed test account).** LemmyKit: PieFed login
  (`username` + error envelope), auth'd neutral endpoints (vote/save/subscribe/hide,
  create/edit post+comment, mark-read, my-user, subscribed list, inbox, DMs) mapped +
  capability-gated where PieFed lacks them. Spud: unblock PieFed login, wire dialect
  into the authed service, seed the capability gap set, fix the two hardcoded Lemmy
  assumptions, PieFed error mapping. Exit: log into a real PieFed instance and
  vote/comment/post/subscribe; gated features show clean affordances. Every claim
  re-tested on-device.
- **Phase 3 — PieFed-native polish (optional, later).** Surface PieFed differentiators
  through native `/api/alpha` endpoints: nested `post/replies`, Feeds, Topics, flair,
  mark-comment-as-answer, events, reputation/new-account badges. Opportunistic; each is
  independently shippable.

## Dependencies / open items (must resolve before the phase they gate)

- **PieFed test account** — REQUIRED for Phase 2 (auth) and its on-device validation.
  Phase 1 (browse) needs none. Open: does the user have / can create a PieFed account
  (e.g. on `piefed.social` or a self-host)? [[spud_lemmy_test_instances]] covers Lemmy
  only.
- **PieFed OpenAPI spec provenance** — vendor freamon's published spec / an instance's
  `/api/alpha/swagger`. Confirm it's complete + tracks a pinned PieFed version; the API
  is alpha and fast-moving, so pin + re-verify.
- **Missing-required-field decode risks** — spot-check every neutral read endpoint's
  PieFed payload for absent Lemmy-required fields (e.g. community `visibility`) during
  Phase 1; each is a small adapter default.
- **`banned_from_community: null`** and similar null-into-non-optional — the adapter
  coalesces; audit for others.

## Risks

- **Alpha, fast-moving API.** PieFed 1.x drifts (1.2 → 1.7 in ~a year). Pin a spec
  version; build adapters tolerant of extra fields (already free); expect re-tests.
- **Effort is real.** This is comparable in shape (not necessarily size) to the Lemmy
  v4 initiative: a third dialect through the neutral facade. Phase 1 is bounded and
  credential-free; Phase 2 is the bulk and gated on a test account.
- **Capability gap list is a moving snapshot.** Seed from Phase 0 + Voyager's June-2025
  list, then trust only on-device measurement.
