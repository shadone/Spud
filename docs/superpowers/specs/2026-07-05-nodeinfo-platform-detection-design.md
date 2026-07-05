# NodeInfo platform detection — design

- **Date:** 2026-07-05
- **Status:** Approved (design). Not yet planned/implemented.
- **Topic:** Detect instance software (Lemmy / PieFed / Mbin / Mastodon / …) via NodeInfo, and use a capability-descriptor + router seam to interact honestly with non-Lemmy hosts.

## Summary

Spud assumes every instance it talks to speaks the Lemmy `/api/v3` API. Point it at a
PieFed, Mbin, or Mastodon host — as an account, a signed-out browse target, or a bare
link — and it fails at runtime with a generic error or a silent Safari punt, with no
explanation of *why*.

This design adds a **detection layer** (fetch `/.well-known/nodeinfo`, read
`software.name` / `software.version`, cache it) and a lightweight **capability seam** (a
`PlatformProfile` describing what each software supports, and a `PlatformRouter` that
consults it) so that:

- Trying to make a non-Lemmy instance a **home connection** (login / register /
  signed-out browse) is **blocked with an honest reason** and an "Open in Safari" escape
  hatch, instead of a confusing failure.
- An instance's **detail screen shows a software badge** ("Lemmy · 0.19.5", "PieFed · 1.0").
- Tapping a **bare-instance link** to a detected non-Lemmy host **signposts** it instead
  of silently opening Safari.

The seam is a *decision-maker*, not an API adapter. LemmyService is untouched. This is
deliberately step 1 of a possible future multi-platform roadmap, structured so a real
PieFed/Mbin client could slot in later — but **no** second API client, importer, or
normalized model is built now.

## Motivation

- **Honest, native UX** (quality bar): today's non-Lemmy failures are silent or
  cryptic. Detection converts them into clear, actionable messages.
- **NodeInfo is the right primitive.** It's the cross-platform standard, and it breaks a
  chicken-and-egg: you cannot detect PieFed by "did the Lemmy API respond," because you
  don't know to call PieFed's API until you already know it's PieFed. NodeInfo tells you
  the dialect *before* you pick one. It's also the foundation the leading unified
  Threadiverse client (`aeharding/threadiverse`, by Voyager's author) uses.
- **The pieces already exist.** The `DiasporaNodeInfo` SPM package (denis's, released
  1.4.0) is a production-ready NodeInfo client; the app already carries a kept-but-unwired
  `NodeInfoRecord` GRDB row and `NodeInfoSoftware` enum that this design repurposes.

## Locked decisions

1. **Scope:** Detection **plus** a capability-descriptor + router seam. Not data-only;
   not a full API abstraction.
2. **Seam altitude:** `InstanceSoftware` + `PlatformProfile` capability descriptor + a
   `PlatformRouter` consulted at decision points. **LemmyService stays concrete.** A
   future PieFed = a new profile (and, eventually, its own service) — not a rework of v1.
3. **Privacy boundary:** Probe a host **only on explicit engagement** — adding/logging
   into an account, opening a specific instance's detail screen, or tapping a link the
   user chose to open. Results cached (multi-day TTL). Feeds and Discover **list** rows
   never trigger a probe; list badges show only already-cached data.
4. **Non-Lemmy home connection:** **Block uniformly** across all non-Lemmy software, with
   a clear reason + "Open in Safari." Federated browsing of a PieFed/Mbin community *from
   an existing Lemmy account* is unaffected (that routes through the user's home instance).

## Goals

- Detect instance software/version via NodeInfo, cached, probed only on explicit engagement.
- Block non-Lemmy home connections (login/register) honestly; badge instance detail.
  (Bare-instance link signposting deferred — see §Integration 3.)
- Leave a clean extension point (`PlatformProfile`/`PlatformRouter`) for future adaptation.

## Non-goals (the YAGNI boundary)

- **Link *classification* is unchanged.** The existing Explorer-directory "known
  instance" gate (`InternalLinkRouting.isKnown` → `AppDatabase.explorerInstanceSync`)
  stays exactly as-is. We do **not** probe NodeInfo during feed rendering or link
  classification (violates the privacy rule). Object links (`/post/123`, `/comment/…`)
  and mention shorthands keep today's behavior — object resolution still runs through the
  user's home instance's `resolve_object` and is unaffected by the target host's software.
- **No second API client, no PieFed/Mbin importers, no normalized cross-platform model.**
- **No per-account software badge** — every account is Lemmy (the rest are blocked), so it
  would be redundant.
- **Mastodon-class software is never a Spud client target** — detect + hand off to the
  browser only.

## Architecture

All new code lives in `SpudDataKit` (domain layer), consistent with the dependency
direction (`Spud → SpudDataKit → SpudUtilKit`).

```
DiasporaNodeInfo (remote SPM pin)
        │  fetch(for: host) -> NodeInfo (software.name / .version)
        ▼
NodeInfoFetching (protocol)  ──fake in tests
        ▲
NodeInfoService (actor)  ──reads/writes──▶  NodeInfoRecord (GRDB cache)
        │  detect(host:) -> Detection(.known | .unknown)
        ▼
InstanceSoftware (enum)  ──▶  PlatformProfile (capabilities)
        ▼
PlatformRouter  ──▶  HomeConnectionDecision(.allow | .block)
        │
        ├─ AccountService pre-flight  (login / register / signInAsSignedOut)
        ├─ Instance detail badge
        └─ Bare-instance link tap signpost
```

### Component responsibilities

| Component | Purpose | Depends on |
|---|---|---|
| `DiasporaNodeInfo` (SPM pin) | `/.well-known/nodeinfo` discovery + parse. Already built. | — |
| `NodeInfoFetching` (protocol) | One-method seam over the package for hermetic tests. | DiasporaNodeInfo |
| `InstanceSoftware` (enum) | Map `software.name` → known case or `.other(String)`. | — |
| `NodeInfoService` (actor) | `detect(host:)`: cache read → fetch → map → cache write; TTL; timeout; never throws. | NodeInfoFetching, `NodeInfoCacheRecord` |
| `NodeInfoCacheRecord` (GRDB, new) | Host-keyed cache row: `host` (unique), `softwareName`, `softwareVersion`, `fetchedAt`. New `v30_nodeInfoCache` migration. | AppDatabase |
| `PlatformProfile` (struct) | Capability lookup from `InstanceSoftware`. No I/O. | InstanceSoftware |
| `PlatformRouter` | `evaluateHomeConnection(host:)` → allow/block. The seam. | NodeInfoService, PlatformProfile |
| `PlatformUnsupportedError` | Typed error carrying software + display name for the UI. | InstanceSoftware |

## Detection layer

### `InstanceSoftware`

```swift
enum InstanceSoftware: Sendable, Equatable {
    case lemmy, piefed, mbin, kbin, mastodon, misskey, pleroma, peertube, friendica, gotosocial
    case other(String)          // unrecognized name, preserved verbatim
    init(softwareName: String)  // lowercased match → known case, else .other
}
```

Replaces the kept `SpudDataKit/Utils/NodeInfoSoftware.swift` (same idea, now the single
mapping site). Recognition is a **strong hint, not gospel** — forks report their own name
(e.g. `.other("sublinks")`) and `.other` is a first-class, handled outcome.

### `NodeInfoService`

```swift
actor NodeInfoService {
    enum Reason: Sendable { case probeFailed, notAdvertised, blocked(status: Int) }
    enum Detection: Sendable {
        case known(InstanceSoftware, version: String?)
        case unknown(Reason)
    }
    init(fetcher: NodeInfoFetching, database: AppDatabase)
    func detect(host: String, maxAge: TimeInterval = 7 * 24 * 3600) async -> Detection
}
```

Flow:
1. Normalize `host` (lowercase, strip scheme/path).
2. **Cache read** (`NodeInfoRecord` by host). If `now - fetchedAt < maxAge`, return the
   cached `.known`.
3. Else `await fetcher.fetch(host:)` under a **short timeout (default 4s** — a login
   pre-flight must not hang; fail-open after); map `software.name` → `InstanceSoftware`;
   **cache write**; return `.known`.
4. Any thrown error (transport, 403/WAF, no 2.x schema advertised, decode) or timeout is
   caught → `.unknown(reason)`. **`detect` never throws.**

**Critical invariant:** `.unknown` ≠ "not Lemmy." It means "couldn't determine." Every
caller treats `.unknown` as *proceed with today's behavior* (fail-open), never as a hard
block. Some healthy Lemmy instances sit behind a CDN/WAF that 403s automated probes (the
same wall as the recurring `getSite` 403 we already see) — those must still work.

### Cache — new host-keyed `NodeInfoCacheRecord`

Recon (2026-07-05) showed the existing `NodeInfoRecord` is **not** the right cache shape:
it is *instance-scoped* (`instanceId` NOT-NULL unique FK to the `instance` table, plus
counts/registration columns), created in `v1`, and currently unused. The feature needs a
**host-keyed** cache available *before* an instance row exists (the pre-flight probes a
host the user hasn't committed to). Contorting the instance-scoped record is worse than a
small dedicated table.

Therefore: create a new `NodeInfoCacheRecord` — columns `host` (TEXT, unique),
`softwareName` (TEXT), `softwareVersion` (TEXT, nullable), `fetchedAt` (datetime) — via a
new **`v30_nodeInfoCache`** migration (the latest live migration is
`v29_ephemeralAccountAndSiteGiveUp`; re-confirm at implementation time). `fetchedAt` drives
the TTL; a stale row is refreshed on the next explicit engagement (instances migrate
software — no permanent pinning). The legacy instance-scoped `NodeInfoRecord` is left
**untouched** (it is unused and kept for a possible later instance-detail data feature).

### Concurrency

`NodeInfoService` as an actor serializes cache access. Concurrent `detect` calls for the
*same* host that both miss cache could double-fetch — acceptable in v1 (rare; both write
the same row). In-flight coalescing is a possible later optimization, not built now. All
new types are `Sendable`; Swift 6 / strict concurrency, consistent with SpudDataKit.

## The seam

### `PlatformProfile`

```swift
struct PlatformProfile: Sendable {
    let software: InstanceSoftware
    let version: String?
    var displayName: String       // "Lemmy" / "PieFed" / "Mastodon" / raw name
    var speaksLemmyAPI: Bool       // v1: true ONLY for .lemmy
    var canBeHomeConnection: Bool  // v1: == speaksLemmyAPI
    var federatesAsLemmy: Bool     // informational; not a v1 gate
    static func profile(for: InstanceSoftware) -> PlatformProfile
}
```

In v1, `speaksLemmyAPI` is true only for `.lemmy`. `.other("…")` → `false` (we detected
real non-Lemmy software; be honest about it — do not assume Lemmy-compat).

### `PlatformRouter`

```swift
enum HomeConnectionDecision: Sendable {
    case allow
    case block(software: InstanceSoftware, displayName: String, version: String?)
}
func evaluateHomeConnection(host: String) async -> HomeConnectionDecision
```

Logic — **detected-non-Lemmy blocks; couldn't-detect never blocks:**
- `.known(.lemmy, v)` → `.allow`
- `.known(other, v)` → `.block(…)` (includes `.other(name)` — real non-Lemmy detection)
- `.unknown(_)` → `.allow` (fail-open; if it genuinely isn't Lemmy, the normal login call
  surfaces its own error, exactly as today)

## Integration surfaces & behavior

### 1. Home-connection pre-flight (primary)

In `SpudDataKit/Services/Account/AccountService.swift`, before the unauthenticated
`api.login(...)` (L516→520) and `api.register(...)` (L568→572) calls — both already
`async throws`, and both taking `instance: InstanceActorId` (use `instance.host`) — call
`router.evaluateHomeConnection(host:)`.

**Recon-driven scoping:** `signInAsSignedOut(atInstance:)` (L377) is **excluded** from v1.
It is synchronous / non-throwing and is also the automatic first-launch **bootstrap** path
(a hardcoded known-Lemmy instance); guarding it would force it `async` and probe a known
instance on every launch for no benefit. User-initiated signed-out "visit this instance"
guarding (if such an entry exists in instance detail) is a follow-up, not v1.

- `.block` → throw `PlatformUnsupportedError(software, displayName)`. The login /
  instance-picker scene catches it and presents a sheet:
  - Title: *"PieFed isn't supported yet"* (or *"That's a Mastodon server"*).
  - Body: *"lemmy.example runs PieFed. Spud can only connect to Lemmy instances right now."*
  - Actions: **[Open in Safari]** **[Cancel]**.
- `.allow` → proceed exactly as today.

The pre-flight adds one network hop before login, but it is cached + timeout-bounded +
fail-open, so the worst case is a brief delay then today's behavior. Exact presenting VC
(`LoginViewModel` / SiteList flow) identified at implementation time.

### 2. Instance-detail badge (secondary)

The instance detail screen (Discover → instance) calls `detect(host:)` on appear and
renders a small "Lemmy · 0.19.5" / "PieFed · 1.0" label. `.unknown` → hide the badge (no
error state). Cached → re-opens are instant.

### 3. Bare-instance link tap (tertiary) — DEFERRED pending scoping decision

Recon (2026-07-05) showed the intended insertion point — `InternalLinkRouting`'s
`routeToExternal(url)` fallback (L79) — is the fallback for **all** unclassified external
links (news articles, images, arbitrary sites), not just bare instances. Probing NodeInfo
there would fire against arbitrary websites, conflicting with decision #3 (probe only
instance-y hosts on explicit engagement). So the originally-approved approach is unsound as
specified.

This surface is **deferred out of v1** pending a scoping decision. The better-scoped
candidate is the **Search paste-to-open** path (`SearchURLDetector`): when the user
explicitly pastes a URL and it is a bare host that returns no Lemmy suggestion today,
probe it and, if `.known(non-Lemmy)`, offer "Open <host> (<software>) in Safari." That is
explicit (a paste), narrow (search only), and never touches the generic tap fallback. v1
ships the two solid surfaces (login/register pre-flight + instance-detail badge); this
surface is decided separately.

## Error handling & edge cases

- **Probe failure / timeout / WAF-403** → `.unknown` → fail-open everywhere. Never blocks.
- **`.other` vs `.unknown`** — `.other(name)` is a *successful* detection of non-Lemmy
  software (blocks home connection, honest message); `.unknown` is *no determination*
  (proceeds). Keeping these distinct is the crux of not wrongly blocking healthy Lemmy
  instances.
- **Lemmy forks / renamed software** could be `.other` and get blocked; rare, the block is
  honest and has a Safari escape hatch. Real Lemmy reports `software.name: "lemmy"`.
- **Stale cache** — TTL refresh on next explicit engagement; software migrations self-heal.

## Dependency changes — DiasporaNodeInfo (denis's package)

**Required (blocking):**
- **A git tag to pin.** Spud pins remote SPM packages by `exactVersion:` in `project.yml`
  (same model as LemmyKit). Need a released **tag** (confirm `1.4.0` is tagged on a stable
  branch, or cut a new tag). Step 0 of implementation. No code change — release hygiene.

**Optional (nice; makes Spud's call site cleaner — denis's call):**
- **A version-agnostic software accessor** on the package's `NodeInfo` enum, e.g.
  `var softwareName: String` / `var softwareVersion: String?` (or a unified
  `var software: (name: String, version: String?)`), so a consumer need not switch on
  `.v2_0` / `.v2_1`. General-purpose. If declined, Spud coalesces locally
  (`info.v2_1?.software.name ?? info.v2_0?.software.name`).

No behavioral changes to the package (async, `Sendable`, spec-compliant errors, no
caching-by-design are all already present).

## Wiring into Spud

- Add `DiasporaNodeInfo` to `packages` in `Spud/project.yml` (`url:` + `exactVersion:`),
  then `make project` + `xcodebuild -resolvePackageDependencies`.
- Construct `NodeInfoService` once in the DI graph (production fetcher wraps
  `NodeInfoManager`); inject `PlatformRouter` where `AccountService` and the instance-detail
  / link-tap scenes need it.

## Testing

Hermetic — inject a fake `NodeInfoFetching`; **never hit live hosts** (avoids the known
flaky-real-network trap). Swift Testing; `AppDatabase.inMemory()` for cache tests.

- **`InstanceSoftware` mapping** — `"lemmy"`→`.lemmy`; `"PieFed"`→`.piefed`
  (case-insensitive); `"kbin"`→`.kbin`; `"sublinks"`→`.other("sublinks")`.
- **`NodeInfoService`** — fresh cache hit returns without fetching; stale row refetches;
  fetch throw → `.unknown(reason)`; timeout → `.unknown(.probeFailed)`; success writes the
  cache row.
- **`PlatformProfile`** — `.lemmy` `speaksLemmyAPI == true`; every other case `false`.
- **`PlatformRouter.evaluateHomeConnection`** — `.known(.lemmy)`→`.allow`;
  `.known(.piefed)`→`.block`; `.unknown`→`.allow` (fail-open explicitly asserted).
- **`AccountService` pre-flight** — inject a fake router; `.block` throws
  `PlatformUnsupportedError`; `.allow` proceeds to the existing login path.
- **Snapshot** — the block sheet and instance-detail badge states (Lemmy / PieFed /
  hidden-when-unknown), reference device via `deterministicPhone`.
- **UITest (should, not must)** — signed-out add-instance flow with `/.well-known/nodeinfo`
  + `/nodeinfo/2.1` stubbed via SBTUITestTunnel to a PieFed payload, asserting the block
  sheet appears. Covers the tap-gated path unit/snapshot tests can't.

## Documentation (three-tier discipline)

- **Feature doc** — new `docs/features/instance-software-detection.md`: behavior/rules +
  Given/When/Then scenarios (block on non-Lemmy home connection; badge on instance detail;
  bare-instance signpost; fail-open on probe failure/WAF-403). Update `README.md`
  capability table **and** by-area map; reconcile adjacent account-login and link-handling
  docs.
- **API docs** — `///` on `InstanceSoftware`, `NodeInfoService`, `PlatformProfile`,
  `PlatformRouter`, `PlatformUnsupportedError`.
- **Internal comments** — the `.other`-vs-`.unknown` distinction, the fail-open rationale,
  the WAF-403 caveat.

## Prerequisites & open items

- [ ] DiasporaNodeInfo: confirm/cut a release tag to pin (blocking).
- [ ] New migration is `v30_nodeInfoCache` (latest live is `v29_ephemeralAccountAndSiteGiveUp`) — re-confirm at implementation.
- [x] Block-sheet presenters identified: `LoginViewModel.login()` generic catch (L131) and `RegisterViewModel.register()` generic catch (L140); badge in `InstanceDetailViewController` (existing "Software" row ~L426).
- [ ] Decide (denis) whether to add the optional version-agnostic accessor to the package.
- [ ] Decide (denis) the deferred bare-instance signpost scoping (Search paste-to-open vs drop) — see §Integration 3.

## Future (out of scope — recorded for continuity)

If the Threadiverse consolidates, the adaptation layer follows as a **separate
initiative**: PieFed first (Threadiverse-native, models the same
community/post/comment/vote concepts, but a Lemmy-*incompatible* `/api/alpha`), Mbin
second. Each would be a new `PlatformProfile` + its own service conforming to a
then-justified protocol seam. Mastodon stays detect-and-hand-off, never a full client.
