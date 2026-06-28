# Signed-out browsing

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Accounts and switching](accounts-and-switching.md), [Login](login.md), [Instance picker](instance-picker.md), [Sign-in gate on write actions](sign-in-gate.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

Spud is usable immediately on first launch with no sign-in. On the very first run it
creates a signed-out (anonymous) account on a default instance and makes it active, so you
land straight in a browsable feed. Signed-out browsing is read-only: you can read feeds,
posts, comments, communities, and profiles, but any write action prompts you to sign in.

## Behavior and rules

- **First-run bootstrap.** When no account exists yet, Spud seeds its site list with a single default instance and creates a signed-out, non-service account on it, marking it the default. The default seeded instance is `discuss.tchncs.de`. This happens with no I/O against the instance and no UI step — the app opens directly into the feed.
- **Signed-out is a real account type.** The bootstrap account is a first-class account row flagged as a signed-out type, with no Keychain credential. It is the active default until you sign in, switch, or add an account.
- **Read-only.** A signed-out account can read everything but cannot perform write actions. Each write surface checks the signed-out state and presents a "Sign in to …" prompt instead of acting. See [sign-in-gate.md](sign-in-gate.md) for the exact set.
- **The Account tab when signed out.** The Account tab shows a "You're browsing as a guest" screen explaining anonymous browsing, with Log in and Sign up buttons; both open the add-account flow (instance picker → login / sign up). The account switcher remains available.
- **"Browse without an account" on the login screen.** The login screen offers "Browse without an account", which pushes a confirmation screen (AnonymousBrowseConfirmViewController) before the signed-out account for the chosen instance becomes active — a way to stay anonymous on a specific instance.
- **Returning to anonymous.** Logging out drops you back to anonymous browsing (a signed-out account on the same instance) when no other account remains.

## Scenarios

### First launch lands in a browsable feed

- **Given** a fresh install with no accounts
- **When** I open the app for the first time
- **Then** a signed-out account is created on the default instance and I see a feed immediately, with no sign-in required

### Reading is unrestricted while signed out

- **Given** the signed-out account is active
- **When** I open feeds, posts, comments, communities, or profiles
- **Then** they load and are fully readable

### A write action prompts sign-in

- **Given** the signed-out account is active
- **When** I try a write action such as save, reply, report, post, or subscribe
- **Then** a "Sign in to …" alert is shown and nothing is written

### The Account tab offers ways in

- **Given** the signed-out account is active
- **When** I open the Account tab
- **Then** I see a "browsing as a guest" screen with Log in and Sign up, plus the account switcher

### Stay anonymous on a chosen instance

- **Given** the login screen for an instance
- **When** I tap "Browse without an account"
- **Then** a confirmation screen appears
- **When** I confirm
- **Then** the signed-out account for that instance becomes active and the screen dismisses

## Not supported / out of scope

- The default bootstrap instance is fixed (`discuss.tchncs.de`); there is no first-run instance chooser before the feed appears (you change instances later via the account flow).
- All write actions including voting are pre-gated with a sign-in sheet before any server attempt. See [voting.md](voting.md) and [sign-in-gate.md](sign-in-gate.md).
- Signed-out browsing has no personalized feed, inbox, or saved list — those require a signed-in account.
