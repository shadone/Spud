# Sign-in gate on write actions

- **Surfaces:** `iphone`, `ipad`
- **Status:** shipped
- **Related:** [Signed-out browsing](signed-out-browsing.md), [Login](login.md), [Replying](replying.md), [Voting](voting.md), [Saving](saving.md), [Accounts and switching](accounts-and-switching.md), [DESIGN-BRIEF.md](../design/DESIGN-BRIEF.md)

## What it does

While the active account is signed out (anonymous), write actions are blocked up front with
a "Sign in to …" sheet and a warning haptic, instead of being attempted and failing. This
keeps anonymous browsing read-only and tells you exactly what needs an account. This doc is
the canonical description of that gate; the per-feature docs reference it.

## Behavior and rules

- **Pre-emptive gate.** Gated actions check the signed-out state before doing anything: if the active account is signed out, they fire a warning haptic, present the "Sign in to …" sheet, and make no API call. A signed-in account is never gated.
- **It is a sheet, not an alert.** The gate is `SignInGateViewController`, presented as a page sheet: an accent icon, a "Sign in to `<action>`" title, an explanatory line, and three buttons — **Create account**, **Log in** (both dismiss the sheet and route to the Account tab to start that flow), and **Not now** (dismiss).
- **The gated write actions.** The following present the gate before attempting:
  - **Vote** on a post or comment — "Sign in to vote".
  - **Save / unsave** a post or comment — "Sign in to save".
  - **Reply / comment** on a post or comment — "Sign in to comment".
  - **Report** a post or comment — "Sign in to report".
  - **New post** (compose) — "Sign in to post".
  - **Subscribe** to a community — "Sign in to subscribe".
  - **Block** a person or community — "Sign in to block".
- **Warning haptic.** Each gate fires a warning haptic alongside the sheet.
- **Defense in depth at the service layer.** Beyond the UI gate, the data layer also rejects writes from a signed-out account, so a gated action that somehow slipped through still cannot mutate server state.
- **Where it shows up.** The same gate guards these actions wherever they appear — the post list, the post detail and its comment tree, community screens, Discover, person profiles, and search.

## Scenarios

### Voting while signed out is gated

- **Given** a signed-out active account
- **When** I tap upvote or downvote
- **Then** a "Sign in to vote" sheet appears with a warning haptic and no vote is sent

### Saving while signed out is gated

- **Given** a signed-out active account
- **When** I tap save on a post or comment
- **Then** a "Sign in to save" sheet appears with a warning haptic and nothing is saved

### Replying while signed out is gated

- **Given** a signed-out active account
- **When** I try to reply or comment
- **Then** a "Sign in to comment" sheet appears and the composer is not presented

### Reporting while signed out is gated

- **Given** a signed-out active account
- **When** I try to report a post or comment
- **Then** a "Sign in to report" sheet appears with a warning haptic

### Creating a post while signed out is gated

- **Given** a signed-out active account
- **When** I tap compose
- **Then** a "Sign in to post" sheet appears and the composer is not presented

### Subscribing or blocking while signed out is gated

- **Given** a signed-out active account
- **When** I try to subscribe to a community, or block a person or community
- **Then** the matching "Sign in to subscribe" / "Sign in to block" sheet appears

### Signed-in accounts are never gated

- **Given** a signed-in active account
- **When** I perform any of the above write actions
- **Then** the action proceeds with no sign-in prompt

## Not supported / out of scope

- The gate's **Create account** / **Log in** buttons route to the Account tab to begin that flow; the gate itself does not embed the login form. See [login.md](login.md) and [accounts-and-switching.md](accounts-and-switching.md).
- Reading actions (opening feeds, posts, comments, profiles, communities) are never gated — see [signed-out-browsing.md](signed-out-browsing.md).
