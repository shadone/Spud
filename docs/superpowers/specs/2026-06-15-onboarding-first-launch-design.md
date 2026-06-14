# Onboarding-first launch (slice A) — design

Date: 2026-06-15
Status: approved (design), pending implementation plan

## Problem

On a fresh install the app crashes:

```
Fatal error: Cannot bootstrap default account: no sites available
AccountService.bootstrapDefaultKeychainId()  (AccountService.swift:221)
  <- AccountService.defaultAccountKeychainId()
  <- MainWindow.init(windowScene:dependencies:)   (MainWindow.swift:79)
  <- SceneDelegate.scene(_:willConnectTo:)
```

`MainWindow.init` synchronously calls `accountService.defaultAccountKeychainId()`,
which — when no account exists — falls through to `bootstrapDefaultKeychainId()`.
That helper requires at least one row from `allSiteListRowsSync()` (the `site`
table) and `fatalError`s when empty. Both the `SiteService` default-site seed and
the bundled Lemmy Explorer seed are imported asynchronously (`DependencyContainer.start()`
kicks off detached `Task`s), so on a cold first launch the `site` table is still
empty when the synchronous bootstrap runs.

Root behavioural issue: the app forces a default account to exist before the user
has chosen anything. The intended design is **onboarding-first** — first launch
should present a Welcome screen and an instance-selection flow, not silently
bootstrap an anonymous account on a hardcoded instance.

## Goal (this slice — "A")

Replace the first-launch auto-bootstrap with an onboarding gate:

- A new **Welcome** screen with a single **Get started** CTA.
- **Get started** opens the existing instance picker (`SiteListViewController`),
  whose existing downstream — `InstanceDetailViewController` / `LoginViewController`
  / `RegisterViewController`, and the existing "Browse without an account" action —
  is reused unchanged. This is where anonymous browsing is reached.
- `MainWindow` shows onboarding as its root when **no non-service account exists**,
  and swaps to the tab bar the moment the flow creates the first account.
- The `bootstrapDefaultKeychainId()` `fatalError` path is deleted.

## Non-goals (deferred to later slices)

- The de-jargoned curated "Pick your home base" screen (recommended instance card,
  "Browse all servers"). This slice reuses the existing `SiteList` picker.
- Interests selection and suggested-communities feed seeding.
- The account-application "why do you want to join" flow polish and the dedicated
  Pending-review screen (the existing `Register` outcome alerts remain).
- A separate "Browse without an account" CTA on the Welcome screen (removed by
  decision — anonymous browse is reached inside the `SiteList` flow).
- Login 2FA wiring, captcha, forgot-password screens.

## Approach

`MainWindow` gates its **root view controller** on account presence, and the
existing `observeDefaultAccount()` stream drives the transition.

- On `init`, query account presence with a new **non-mutating** accessor.
  - Account present -> build the tab bar from that account (today's behaviour).
  - No account -> set `rootViewController` to an onboarding `UINavigationController`
    rooted at `OnboardingWelcomeViewController`.
- `startObservingDefaultAccount()` already fires when the default account changes.
  When the first account appears while onboarding is showing, cross-fade
  `rootViewController` from onboarding to a freshly built tab bar.

Rejected alternative: present onboarding modally over the tab bar. The tabs
(feed, communities, inbox, account) are all built around a default account, so
they cannot be constructed in the no-account state — onboarding must be the root,
not an overlay.

## Components and changes

### New: `OnboardingWelcomeViewController`

- Location: `Spud/Scenes/Onboarding/OnboardingWelcomeViewController.swift`.
- Native rendition of the Welcome design (`onboarding.jsx` `Welcome`), minus the
  removed secondary button:
  - brand mark (existing app brand/icon asset), "Spud" wordmark,
  - tagline "Communities worth your time.",
  - body line "Thousands of communities, real threaded discussion, and a feed you
    actually control — no ads, no algorithm.",
  - a single primary **Get started** button.
- Uses the app's existing accent/theme (the same accent `MainWindow.applyAccent`
  drives). Accent-tinted radial background consistent with the design.
- Exposes an `onGetStarted: () -> Void` closure (set by `MainWindow`) rather than
  reaching into navigation itself, so the screen stays testable in isolation.

### `MainWindow`

- Replace the `defaultAccountKeychainId()` bootstrap call in `init` with a
  non-mutating presence check (see `AccountService` below).
  - Present: build tabs via `applyDefaultAccount(...)` exactly as today.
  - Absent: build the onboarding nav controller and set it as `rootViewController`;
    do **not** build the tab bar yet.
- Add a small `showOnboarding()` that builds `UINavigationController(rootVC:
  OnboardingWelcomeViewController)`, wiring `onGetStarted` to push the existing
  `SiteListViewController` onto that same nav controller. The existing
  `SiteList -> InstanceDetail/Login/Register` chain and the "Browse without an
  account" action run unchanged within this stack.
- In `startObservingDefaultAccount()`, when a default account first appears while
  onboarding is the root, build the tab bar and cross-fade `rootViewController`
  (e.g. `UIView.transition(with: self, .transitionCrossDissolve)`), then drop the
  onboarding nav controller. The existing "keychain id changed" guard already
  prevents redundant rebuilds.
- Track whether onboarding is currently shown so the observation knows to swap
  (vs. the existing in-place tab rebuild on account switch).

### `AccountService` / `AccountServiceType`

- Replace the bootstrapping `defaultAccountKeychainId() -> String` with a
  non-mutating `currentDefaultAccountKeychainId() -> String?`: it returns the
  existing default / first non-service account, or `nil`. No writes, no bootstrap.
- Delete `bootstrapDefaultKeychainId()` (and its `fatalError`).
- Repoint the three current callers of `defaultAccountKeychainId()`:
  - `MainWindow.init` (`MainWindow.swift:79`) — the gate; `nil` -> onboarding.
  - `MainWindow` tab-build fallback (`MainWindow.swift:422`) — runs only with tabs
    present; use the tracked `currentDefaultAccountKeychainId` property, falling
    back to the new optional accessor and bailing if somehow `nil`.
  - `AccountService` logout/remove path (`AccountService.swift:571`,
    `defaultAccountKeychainId() == keychainId`) — runs only with an account
    present; an optional comparison (`currentDefaultAccountKeychainId() == keychainId`)
    is equivalent (`nil` never matches a real keychainId).

## Flow

```
Fresh install (zero non-service accounts)
  -> MainWindow root = Onboarding nav (Welcome)
  -> "Get started"  -> push SiteListViewController
       -> pick instance -> InstanceDetail / Login / Register
            -> Login success / Register .loggedIn / "Browse without an account"
                 -> account created + set default
  -> observeDefaultAccount() yields the new default
  -> MainWindow builds tab bar, cross-fades root onboarding -> tabs

Returning user (>= 1 non-service account)
  -> MainWindow builds tab bar directly (unchanged)
```

## Edge cases

- **Logout** keeps today's behaviour (switches to a signed-out account on the same
  instance), so a non-service account still exists and onboarding does not
  re-trigger. Onboarding is therefore first-launch-only in practice.
- **Deep link / open-URL while onboarding** (no account): ignored until an account
  exists. Rare and out of scope; `AppCoordinator.open(url:in:)` already assumes an
  account context.
- **Widget** with no account uses its existing empty/placeholder state. Out of scope.
- `SiteService`'s async `discuss.tchncs.de` seed is no longer load-bearing for the
  bootstrap; left in place this slice (harmless).

## Testing

- Snapshot test for `OnboardingWelcomeViewController` (light + dark, pinned device
  config like the other screen snapshots).
- Unit test: `currentDefaultAccountKeychainId()` returns `nil` against an empty
  in-memory `AppDatabase` (proves the crash is gone — no `fatalError`).
- Unit test: with a seeded default account it returns that account's keychainId.
- Manual: fresh-install run shows Welcome; completing sign-in / register / "Browse
  without an account" lands in the tab bar; relaunch goes straight to tabs.
