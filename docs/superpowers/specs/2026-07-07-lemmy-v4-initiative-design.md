# Lemmy 1.0 (API v4) support — initiative design

Date: 2026-07-07
Status: Approved — decisions locked via grilling session; Phase 1 plan follows
Scope: multi-repo — `Spud` (this repo), `LemmyKit`, `Lemmy-OpenAPI-Spec`. This
document is the initiative-level record; each phase gets its own executable
plan under `docs/superpowers/plans/`.

## Problem

Lemmy 1.0 ships a new HTTP API (`/api/v4`) that is a rewrite of the v3 API
Spud speaks today. Instances will upgrade on their own schedules after 1.0
releases, so Spud must interoperate with 0.19.x (v3) and 1.0 (v4) instances
simultaneously — including an instance flipping versions underneath a
logged-in account.

## Research findings (verified against specs + the 1.0.0-alpha.18 server)

1. **A 1.0 server keeps serving a partial v3 shim, always-on.** Login, feeds,
   post/comment read + create + vote + save, community list/follow, search and
   resolveObject keep working via `/api/v3`. Absent from the shim: person
   profiles (`GET /user`), replies/mentions inbox, all private-message
   endpoints, `save_user_settings`, image upload, `/post/hide`,
   `/post/mark_as_read`, modlog, captcha. So Spud-as-is degrades against a
   1.0 instance but does not die.
2. **v4 is a rewrite, not additive.** Cursor pagination everywhere
   (bidirectional, numeric `page` gone); aggregates flattened onto entities;
   flat booleans (`saved`, `read`, `my_vote`) replaced by nested
   `post_actions`/`community_actions` objects carrying timestamps
   (`saved_at`, `vote_is_upvote: Bool?`); subscribe's 3-state enum becomes the
   4-state `CommunityFollowerState` (`accepted`, `pending`,
   `approval_required`, `denied`); `my_user` removed from getSite (separate
   `GET /account`); person details split into profile + `person/content`;
   notifications unified into one discriminated-union endpoint; image upload
   becomes first-class (`POST /api/v4/image`); sort model splits `TopDay`-style
   variants into sort + `time_range_seconds`; auth (Bearer JWT header) is
   unchanged.
3. **Detection is nearly free.** NodeInfo `software.version` is already cached
   host-keyed pre-login (`nodeInfoCache`, v30); `SiteRecord.version` is already
   persisted from every getSite import; `/api/v4/site` 404s on 0.19.x (clean
   positive probe). `PlatformProfile.profile(for:version:)` already threads a
   version param that nothing branches on yet.
4. **The dominant cost is vocabulary leakage in Spud.** ~378 files reference
   the OpenAPI-generated `Components.Schemas.*` namespace; the generated v3
   types (`PostID`, `SortType`, `ListingType`, ...) are the app's vocabulary
   across ~75 UI files, and the ~75-method `LemmyServiceType` protocol is
   spelled in them. The GRDB layer is already clean (app-owned records,
   mapped in `Importers/`).
5. **Two spec-side landmines before any v4 codegen** (in `Lemmy-OpenAPI-Spec`):
   the v4 spec's `RequestState_*` response envelope is a js-client artifact,
   not the wire format — it must be stripped via `overlay.yaml`; and
   `normalize.mjs` must stay in the build or every id decodes as `Double`.
6. **The optimistic outbox is version-sensitive.** Vote/save/hide/subscribe
   baselines encode v3 semantics (notably the 3-valued subscribe codec), and a
   queued op recorded against a 0.19 instance may replay after it upgrades.

## Decisions

### D1 — Target: first-class v4 support, built in phases starting now

Detection + capability gating ships first (it is useful the day any instance
upgrades); the version-independent seam work proceeds now; the v4 wire layer
stays regeneratable until 1.0 final (`scripts/sync-v4.sh` in the spec repo).
Rejected: shim-only stopgap (leaves the app degraded with no path forward);
waiting for 1.0 final (forces the 378-file refactor under time pressure).

### D2 — LemmyKit owns the version-neutral surface

LemmyKit grows a hand-written, version-neutral public surface — neutral
vocabulary + DTOs + the `LemmyApi` facade — and the two generated clients
become internal implementation details. Spud migrates its vocabulary once and
never sees a generated namespace again. Rejected: Spud-owned seam (relocates
the same work, leaves both generated namespaces public, not reusable);
v4-to-v3 down-conversion (lossy — the server's own shim proves it — and
cements a deprecated vocabulary).

### D3 — The neutral surface speaks v4 semantics wholesale; V3 emulates upward

- Opaque bidirectional cursor type; the V3 backend synthesizes cursors
  wrapping page numbers.
- `getSite` drops `my_user`; neutral `getMyUser()` exists (V3 serves it from
  its cached combined getSite response; V4 maps 1:1).
- Unified `listNotifications(type:cursor:)`; V3 fans out to
  replies/mentions/PMs and k-way merges for the combined view.
- Neutral vote enum (`.up`/`.down`/`.none`), 4-state follow enum, and
  `savedAt`/`readAt`/`hiddenAt: Date?` with derived `isSaved` etc. (v3
  backends report state with `nil` timestamps).
- Neutral sort = v4 style (sort kind + optional time range); V3 recombines
  into `TopDay`-style variants.
- Person profile split into two neutral operations; V3 serves both from its
  one endpoint.

Rejected: per-flow v3 ergonomics — it hides fan-out calls inside the V4 path
and re-breaks the surface when v3 dies; the migration touches call sites
anyway, so pay the full cost once.

### D4 — Version resolution: explicit injection; getSite-driven re-evaluation

- `LemmyApi(instanceUrl:credential:apiVersion:)` with an `ApiVersion` enum;
  LemmyKit never auto-detects (deterministic, testable). LemmyKit also ships a
  standalone probe utility (`/api/v4/site` reachable → `.v4`) as a tool.
- Spud derives the version per instance (not per account): NodeInfo
  `softwareVersion` pre-login; `GetSiteResponse.version` re-parsed on every
  getSite import post-connection — the existing site-refresh scheduler is the
  re-detection loop.
- Self-healing flip: a v3-configured client's `GET /site` still works on 1.0
  (shim serves it), returns the 1.0 version string, the importer sees the
  flip, and `AccountService` rebuilds cached services for accounts on that
  instance.
- Unknown/unparseable defaults to `.v3` (today's installed base; core v3
  still works against 1.0 until the getSite round-trip corrects it).
- Derive the flavor from persisted version strings; no stored `apiVersion`
  column until a manual override feature earns it.

### D5 — GRDB records change only where behavior demands it

Importers map neutral (v4-shaped) DTOs into existing record shapes. Three
forced exceptions:

1. Follow state becomes 4-valued — the subscribe outbox's 3-valued baseline
   codec gets a versioned extension; the reconcile guard must decide what
   `denied` means for a pending op.
2. The sort model (sort + time range) is stored in user prefs — tolerant
   decode-and-map of existing raw strings, not a destructive migration.
3. Outbox op payloads must be encoded in neutral vocabulary so a queued op
   survives a mid-queue version flip; explicit audit pass required.

Timestamps (`saved_at` etc.), `can_mod`, community tags stay out of the DB
until a feature renders them.

### D6 — Capability gating: semantic `InstanceCapabilities` on `PlatformProfile`

- Capabilities are feature semantics (`canViewProfiles`, `canUseInbox`,
  `canUploadImages`, `canEditSettings`, `canHidePosts`,
  `canUsePrivateMessages`, ...), derived from (software, version, apiFlavor).
  UI asks "can I?", never "which version?".
- Enforced twice: UI entry points consult capabilities via the existing
  scope; `LemmyService` throws a typed
  `LemmyServiceError.unsupportedByInstance(capability:)` backstop (clean,
  loggable via the diagnostic log, instead of a raw 404).
- Presentation: during the shim period (features users had, temporarily
  gone) — explain, don't hide (explanatory empty states / sheets). For
  permanent version gaps (v4-only features on v3 instances) — hidden by
  default.
- Rejected: version checks at call sites (scatters the shim table, inverts
  meaning once v4 support ships, dies on fork version strings).

### D7 — LemmyKit package structure + two-stage migration

```
LemmyKit (package)
├── LemmyKitV3Generated   <- symlink -> specs/v3/0.19.11, plugin-generated
├── LemmyKitV4Generated   <- symlink -> specs/v4/..., plugin-generated
└── LemmyKit (facade)     <- neutral vocabulary + DTOs + LemmyApi
                             + V3/V4 backend adapters; sole library product
```

- Generated targets use `accessModifier: package` (visible to the facade,
  unreachable from Spud even by accident); fall back to `public` +
  non-product targets + `internal import` if the generator version balks.
- Two-stage Spud migration: stage 1, a LemmyKit tag publishes neutral
  vocabulary names as typealiases of the existing generated v3 types, and
  Spud does the mechanical rename (zero behavior change, reviewable dumb
  diffs); stage 2, the aliases swap to hand-written neutral types, the
  neutral DTO layer + V4 backend arrive, generated namespaces go
  package-private — Spud diffs concentrate where semantics actually changed.
  Rejected: big-bang (rename + reshape + v4 in one release is unreviewable
  and unbisectable).
- Facade keeps the one-file-per-endpoint idiom; each method switches on the
  injected `ApiVersion` and delegates to a V3 or V4 adapter. The 107 existing
  wrappers become the V3 adapter's starting material.

### D8 — Remaining branches (decided without further grilling)

- **LemmyKit pin cadence:** develop against LemmyKit's own tests in-package;
  prerelease tags (`2.0.0-alpha.N`) at milestone boundaries; Spud pin bumps
  at integration points only. No local-path override — the remote pin
  architecture stays.
- **Spec resync cadence:** stay pinned to the current js-client snapshot
  (`dafc558`); resync deliberately at 1.0 beta/rc/final via `sync-v4.sh`,
  not chasing upstream `main`.
- **Testing:** LemmyKit adapters get in-package tests with recorded fixtures
  for both flavors (the injectable `ClientTransport` seam exists); Spud
  keeps testing against `LemmyServiceType` fakes; end-to-end against
  `voyager.lemmy.ml` / `ds9.lemmy.ml` (official 1.0 test servers) and a
  self-hosted 1.0 instance alongside the existing 0.19 test1/test2 pair.
- **v4-only features** (multi-communities, community tags, OAuth providers):
  out of scope for this initiative; the capability mechanism hides them on
  v3 instances when they eventually ship.

## Phases

| # | Repo | Deliverable | Depends on |
|---|---|---|---|
| 1 | Spud | Detection + capability gating (ships alone; useful the day any instance upgrades) | — |
| 2 | Lemmy-OpenAPI-Spec | `overlay.yaml` strips the `RequestState` envelope; rebuilt + codegen-verified v4 spec | — |
| 3 | LemmyKit | Package restructure + neutral vocabulary typealiases; `2.0.0-alpha.1` tag | — |
| 4 | Spud | Mechanical vocabulary rename (~378 files), pin bump | 3 |
| 5 | LemmyKit | Neutral DTOs, V3/V4 backend adapters, `ApiVersion` injection, probe utility | 2, 3 |
| 6 | Spud | v4 semantics adoption (cursors, inbox, sort, my_user, follow codec, outbox audit) + version routing + rebuild-on-flip | 4, 5 |

Phases 1–3 are mutually independent and can proceed in parallel.
