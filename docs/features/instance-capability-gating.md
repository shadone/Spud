# Instance capability gating

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped, now **dormant for Lemmy** — the capability mechanism (UI gates, service backstop, diagnostic event) is retained, but the version-derivation table gates nothing on any Lemmy version now that Spud speaks the native v4 API. The seven features it once withheld on Lemmy 1.0 (person profiles, inbox, private messages, image upload, hide post, profile/settings save, and server read-state sync) all work natively there. The mechanism stays for non-Lemmy software and a possible future version-varying capability.
- **Related:** [Inbox](inbox.md), [Private messages](private-messages.md), [Person / user profile](person-profile.md), [Account Activity](account-activity.md), [Image upload](image-upload.md), [Edit your profile](profile-editing.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [Instance software detection](instance-software-detection.md), [Diagnostics logging](diagnostics-logging.md), [docs/superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md](../superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md), [docs/superpowers/plans/2026-07-07-lemmy-v4-phase1-capability-gating.md](../superpowers/plans/2026-07-07-lemmy-v4-phase1-capability-gating.md)

## What it does

This was a Phase-1 stopgap. When Spud spoke only Lemmy's v3 API, a home instance on Lemmy 1.0
served a partial v3 compatibility shim that was missing exactly seven endpoints, so Spud
gated those seven features on a 1.0 instance — explaining them instead of failing with a raw
server error — while everything else kept working.

Spud now speaks the **native v4 API** (initiative Phase 6), so all seven of those features
work on a Lemmy 1.0 instance directly. The gating therefore **no longer fires for any Lemmy
version**: the version-derivation table reports every capability available on both 0.19.x and
1.0+. What remains is the *mechanism* — the `InstanceCapabilities` type, the UI gates in each
feature, the service-layer backstop, and the `capability.blocked` diagnostic event — kept
intact so a future capability whose support genuinely varies by software or version can be
re-gated without re-plumbing anything, and so non-Lemmy software (which can't be a home
connection at all) still fails open on the Lemmy version scale.

## Behavior and rules

- **The version-derivation table gates nothing today.** `InstanceCapabilities.capabilities(software:version:)`
  returns "everything available" for every input. The Phase-1 rule (Lemmy major ≥ 1 withholds
  seven capabilities) has been removed now that Spud speaks native v4; the seven endpoints the
  1.0 v3-shim lacked — person profiles, the replies/mentions inbox, private-message operations,
  image upload, `/post/hide`, `save_user_settings`, and server read-state sync — are all reached
  through the v4 neutral surface instead.
- **The gating UI and service backstop are retained but inert.** Every previously-gated
  `LemmyService` operation still calls `requireCapability(...)` first, each feature still has its
  explanatory gated state, and `LemmyServiceError.unsupportedByInstance` still exists and is
  still classified permanent by the outboxes. None of these fire for a Lemmy instance now,
  because the capability they check always reads as available. They are kept as the ready-made
  seam for a future gated capability, not deleted.
- **How a capability could gate again.** A capability is withheld only if a capability set is
  constructed that lists it — either by re-adding a real gated branch to the derivation table
  (for a future version-varying Lemmy capability) or by constructing
  `InstanceCapabilities(unavailable:)` directly. When that happens, the existing UI gates and
  backstop light up automatically for exactly those capabilities.
- **Fail-open is unchanged.** Non-Lemmy software, an unknown/unparseable version, and a
  not-yet-imported site row all still resolve to every capability available — the same
  conservative default (a mis-gate is worse than an occasional raw server error) that governed
  the mechanism from the start.
- **Federated content browsing was, and remains, entirely unaffected.** Feeds, posts, comments,
  communities, search, and voting/saving never read a capability.

## Scenarios

### Home instance on Lemmy 1.0 — the previously-gated features work

- **Given** I am signed in to a home instance running Lemmy 1.0
- **When** I open the Inbox, open a person profile, attach an image to a new post, hide a post,
  edit my profile, or use a DM thread
- **Then** each feature works normally — Spud reaches its native v4 endpoint — with no
  "isn't available yet" explanatory state, because the capability gating has been retired for
  Lemmy

### Home instance still on Lemmy 0.19 — unchanged

- **Given** my home instance's persisted version is 0.19.x
- **When** I use any part of the app
- **Then** everything works exactly as before — 0.19.x was never gated, and Spud speaks its v3
  API directly

### Instance version is unknown, unparseable, or non-Lemmy — fails open

- **Given** the home instance's version hasn't been imported yet, its version string doesn't
  parse, or the software isn't Lemmy
- **When** any capability is checked
- **Then** every capability resolves to available — the mechanism's unchanged fail-open default

### The mechanism can still gate a directly-constructed capability set

- **Given** a capability set is constructed that lists a capability as unavailable (a future
  version-varying gate, or a test constructing `InstanceCapabilities(unavailable:)`)
- **When** an operation or screen guarded by that capability is reached
- **Then** the retained UI gate / service backstop fires for exactly that capability — proving
  the mechanism is intact even though no live Lemmy version triggers it today

## Not supported / out of scope

- **No manual override.** There is still no user setting to force a capability on or off; the
  derivation is driven entirely by software + version (and today gates nothing for Lemmy).
- **Not a software-compatibility gate.** Blocking a non-Lemmy home connection outright is a
  separate feature — see [Instance software detection](instance-software-detection.md). This
  feature only ever concerned version gaps *within* Lemmy, which native v4 support has now
  closed.
- **Federated/remote content browsing is never gated.** Reading feeds, posts, comments, and
  communities is unaffected regardless of any instance's version.
