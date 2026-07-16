# Instance capability gating

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped and **live for PieFed**. The mechanism (per-software capability sets, UI
  gates, service backstop, diagnostic event) actively withholds two capabilities on a PieFed
  home instance — **image upload** and **server-side profile/settings save** — explaining them
  instead of failing with a raw error. It gates **nothing** on any Lemmy version (Spud speaks
  the native v4 API there), so for Lemmy the machinery is present but inert.
- **Related:** [PieFed instances](piefed.md), [Inbox](inbox.md), [Private messages](private-messages.md), [Person / user profile](person-profile.md), [Account Activity](account-activity.md), [Image upload](image-upload.md), [Edit your profile](profile-editing.md), [Marking posts read and hiding read posts](mark-read-and-hiding.md), [Instance software detection](instance-software-detection.md), [Diagnostics logging](diagnostics-logging.md), [docs/superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md](../superpowers/specs/2026-07-07-lemmy-v4-initiative-design.md)

## What it does

Some server software supports most of Spud's features but not all of them. Rather than let an
unsupported action fail with a raw server error, Spud derives a per-instance **capability set**
from the detected software (and, for Lemmy, potentially its version) and, when a capability is
withheld, **explains** it in the UI and skips the round-trip.

Originally a Lemmy-1.0 stopgap, the mechanism now has its first real, shipping use: **PieFed**.
Spud can log in to and interact with a PieFed instance, but PieFed's API doesn't expose
**image upload** or **server-side profile/settings save** the way Spud needs, so those two
capabilities are withheld on a PieFed home instance. Everything else on PieFed — voting, saving,
subscribing, mark-read, hide, commenting, posting, the inbox, and DMs — is available. On Lemmy
(any version) the capability set is "everything available", so the gates never fire there.

## Behavior and rules

- **The capability set is derived from the detected software.** `InstanceCapabilities` is built
  per home instance from the NodeInfo-detected software: **PieFed** resolves to a set that marks
  `imageUpload` and `serverUserSettings` unavailable; every Lemmy version resolves to "all
  available". The software is resolved per-call from the NodeInfo software cache and **fails open
  to Lemmy** (all available) when the software is unknown, unparseable, or not yet probed.
- **Two withheld capabilities on PieFed.**
  - **Image upload (`imageUpload`).** Attaching an image to a new post (and uploading an
    avatar/banner) is gated. The "Attach image" affordance stays visible and enabled — tapping
    it presents an "Image upload isn't available yet" sheet instead of the photo picker. Text and
    link posts are unaffected.
  - **Server-side profile / settings save (`serverUserSettings`).** Pushing profile edits and
    account settings to the server is gated. Tapping "Edit profile" presents a "Profile editing
    isn't available yet" sheet. Local, on-device preferences (sort, appearance, and the like)
    still apply — only the server *push* is withheld, and setters that would push a server-side
    setting soft-degrade to the local write rather than erroring.
- **How a withheld capability presents.**
  - **Feature affordances (image upload, edit profile)** show the short explanatory
    **capability-gate sheet** ("… isn't available yet") at tap time — the affordance is shown,
    not hidden ("explain, don't hide"). The sheet's body copy is **software-aware**: on a
    Lemmy account it keeps the version framing ("runs a newer version of Lemmy"); on PieFed
    (or any other software) it uses neutral wording ("This isn't available on <host> yet.")
    rather than misattributing the gap to a Lemmy version.
  - **A read surface** that hits an unsupported operation renders the inline **"Not available on
    this instance"** state ("This isn't available on your account's instance.") — the one
    error-state variant with **no Retry button**, since retrying can't help.
  - **A write action** that hits a withheld/undialected operation surfaces an alert with the same
    "This isn't available on your account's instance." copy.
- **The service backstop.** Every gated `LemmyService` operation calls `requireCapability(...)`
  first; when the capability is withheld it throws `unsupportedByInstance` and records a
  `capability.blocked` diagnostic event (visible in About → Logs). Both `unsupportedByInstance`
  (a gated capability) and `unsupportedByDialect` (a neutral endpoint with no PieFed arm) are
  classified **permanent** by the outboxes, so a gated write parks/rolls back rather than
  retrying forever.
- **Lemmy is unaffected.** On any Lemmy version the capability set is "everything available", so
  none of the gates fire and every feature reaches its native endpoint. The machinery is retained
  as the ready-made seam for a future version-varying Lemmy capability, but it withholds nothing
  on Lemmy today.
- **Fail-open is unchanged.** Unknown/unparseable software, a not-yet-probed host, or a
  not-yet-imported site row all resolve to "everything available" — a conservative default (a
  mis-gate is worse than an occasional raw server error).
- **Federated/remote content browsing is never gated.** Feeds, posts, comments, communities,
  search, and voting/saving never read a capability.

## Scenarios

### Image upload is withheld on a PieFed home instance

- **Given** I am signed in to a PieFed instance and composing a new post
- **When** I tap "Attach image"
- **Then** an "Image upload isn't available yet" gate sheet appears instead of the photo picker,
  and the rest of the composer keeps working

### Editing your profile is withheld on a PieFed home instance

- **Given** I am signed in to a PieFed instance
- **When** I tap "Edit profile" on the Account screen
- **Then** a "Profile editing isn't available yet" gate sheet appears; my local preferences are
  unaffected

### A withheld read surface shows a no-retry state

- **Given** a screen reaches an operation the home instance's capability set withholds (or the
  dialect has no arm for)
- **When** the operation fails as unsupported
- **Then** the screen renders the inline "Not available on this instance" state with no Retry
  button, and a `capability.blocked` (or dialect-unsupported) diagnostic is recorded

### Home instance on any Lemmy version — nothing is gated

- **Given** I am signed in to a Lemmy home instance (0.19.x or 1.0+)
- **When** I use any feature, including image upload and edit-profile
- **Then** everything works normally with no "isn't available yet" gate — the capability set is
  "all available" for Lemmy

### Instance software is unknown, unparseable, or not yet probed — fails open

- **Given** the home instance's software hasn't been resolved yet, or is unrecognized
- **When** any capability is checked
- **Then** every capability resolves to available — the mechanism's unchanged fail-open default

## Not supported / out of scope

- **No manual override.** There is no user setting to force a capability on or off; the
  derivation is driven entirely by the detected software (and, for Lemmy, potentially version).
- **Not a software-compatibility gate.** Blocking a non-Lemmy home connection that Spud can't
  speak at all is a separate feature — see [Instance software detection](instance-software-detection.md).
  This feature governs which *features* are available once a supported home connection (Lemmy or
  PieFed) is established.
- **Federated/remote content browsing is never gated.** Reading feeds, posts, comments, and
  communities is unaffected regardless of any instance's software.
